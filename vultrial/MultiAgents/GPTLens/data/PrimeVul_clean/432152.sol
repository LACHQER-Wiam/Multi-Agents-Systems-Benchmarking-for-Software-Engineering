createRandomCursorExecutor(const CollectionPtr& coll,
                           const boost::intrusive_ptr<ExpressionContext>& expCtx,
                           long long sampleSize,
                           long long numRecords,
                           boost::optional<BucketUnpacker> bucketUnpacker) {
    OperationContext* opCtx = expCtx->opCtx;
    invariant(opCtx->lockState()->isCollectionLockedForMode(coll->ns(), MODE_IS));
    static const double kMaxSampleRatioForRandCursor = 0.05;
    if (!expCtx->ns.isTimeseriesBucketsCollection()) {
        if (sampleSize > numRecords * kMaxSampleRatioForRandCursor || numRecords <= 100) {
            return std::pair{nullptr, false};
        }
    } else {
        static const double kCoefficient = 0.01;
        if (sampleSize > kCoefficient * numRecords * gTimeseriesBucketMaxCount) {
            return std::pair{nullptr, false};
        }
    }
    auto rsRandCursor = coll->getRecordStore()->getRandomCursor(opCtx);
    if (!rsRandCursor) {
        return std::pair{nullptr, false};
    }
    auto ws = std::make_unique<WorkingSet>();
    std::unique_ptr<PlanStage> root =
        std::make_unique<MultiIteratorStage>(expCtx.get(), ws.get(), coll);
    static_cast<MultiIteratorStage*>(root.get())->addIterator(std::move(rsRandCursor));
    TrialStage* trialStage = nullptr;
    static const size_t kMaxPresampleSize = 100;
    if (auto css = CollectionShardingState::get(opCtx, coll->ns());
        css->getCollectionDescription(opCtx).isSharded() &&
        !expCtx->ns.isTimeseriesBucketsCollection()) {
        const auto minAdvancedToWorkRatio = std::max(
            sampleSize / (numRecords * kMaxSampleRatioForRandCursor), kMaxSampleRatioForRandCursor);
        auto collectionFilter = css->getOwnershipFilter(
            opCtx, CollectionShardingState::OrphanCleanupPolicy::kDisallowOrphanCleanup);
        auto randomCursorPlan = std::make_unique<ShardFilterStage>(
            expCtx.get(), collectionFilter, ws.get(), std::move(root));
        std::unique_ptr<PlanStage> collScanPlan = std::make_unique<CollectionScan>(
            expCtx.get(), coll, CollectionScanParams{}, ws.get(), nullptr);
        collScanPlan = std::make_unique<ShardFilterStage>(
            expCtx.get(), collectionFilter, ws.get(), std::move(collScanPlan));
        root = std::make_unique<TrialStage>(expCtx.get(),
                                            ws.get(),
                                            std::move(randomCursorPlan),
                                            std::move(collScanPlan),
                                            kMaxPresampleSize,
                                            minAdvancedToWorkRatio);
        trialStage = static_cast<TrialStage*>(root.get());
    } else if (expCtx->ns.isTimeseriesBucketsCollection()) {
        if (!(bucketUnpacker && numRecords)) {
            return std::pair{nullptr, false};
        }
        static const auto kCoefficient = 0.02;
        static const auto kMinBucketFullness = 0.25;
        const auto minAdvancedToWorkRatio = std::max(
            std::min(sampleSize / (kCoefficient * numRecords * gTimeseriesBucketMaxCount), 1.0),
            kMinBucketFullness);
        auto arhashPlan = std::make_unique<SampleFromTimeseriesBucket>(
            expCtx.get(),
            ws.get(),
            std::move(root),
            *bucketUnpacker,
            kMaxPresampleSize + 5,
            sampleSize,
            gTimeseriesBucketMaxCount);
        std::unique_ptr<PlanStage> collScanPlan = std::make_unique<CollectionScan>(
            expCtx.get(), coll, CollectionScanParams{}, ws.get(), nullptr);
        auto topkSortPlan = std::make_unique<UnpackTimeseriesBucket>(
            expCtx.get(), ws.get(), std::move(collScanPlan), *bucketUnpacker);
        root = std::make_unique<TrialStage>(expCtx.get(),
                                            ws.get(),
                                            std::move(arhashPlan),
                                            std::move(topkSortPlan),
                                            kMaxPresampleSize,
                                            minAdvancedToWorkRatio);
        trialStage = static_cast<TrialStage*>(root.get());
    }
    auto execStatus = plan_executor_factory::make(expCtx,
                                                  std::move(ws),
                                                  std::move(root),
                                                  &coll,
                                                  opCtx->inMultiDocumentTransaction()
                                                      ? PlanYieldPolicy::YieldPolicy::INTERRUPT_ONLY
                                                      : PlanYieldPolicy::YieldPolicy::YIELD_AUTO,
                                                  QueryPlannerParams::RETURN_OWNED_DATA);
    if (!execStatus.isOK()) {
        return execStatus.getStatus();
    }
    return std::pair{std::move(execStatus.getValue()),
                     !trialStage || !trialStage->pickedBackupPlan()};
}