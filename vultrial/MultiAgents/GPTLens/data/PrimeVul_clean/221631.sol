llvm::Optional<Value> simplifyBroadcast(ShapeComponentAnalysis& analysis,
                                        ValueRange shapes, Location loc,
                                        OpBuilder* builder) {
  SmallVector<ArrayRef<ShapeComponentAnalysis::SymbolicExpr>> shapes_found;
  size_t maxRank = 0;
  for (const auto &shape : llvm::enumerate(shapes)) {
    auto found_shape = analysis.GetValueInfo(shape.value());
    if (!found_shape) return {};
    shapes_found.push_back(*found_shape);
    maxRank = std::max(maxRank, found_shape->size());
  }
  if (maxRank == 0) {
    return Value(builder->create<tensor::FromElementsOp>(
        loc, shapes[0].getType(), SmallVector<Value>()));
  }
  SmallVector<const ShapeComponentAnalysis::SymbolicExpr*> joined_dimensions(
      maxRank);
  SmallVector<std::pair<Value, int64_t>> shape_and_rank_for_dim(maxRank);
  for (const auto &shape : llvm::enumerate(shapes_found)) {
    for (const auto &dim : llvm::enumerate(llvm::reverse(shape.value()))) {
      if (dim.value().isConstant(1)) continue;
      auto index = maxRank - dim.index() - 1;
      if (!joined_dimensions[index]) {
        joined_dimensions[index] = &dim.value();
        shape_and_rank_for_dim[index] =
            std::make_pair(shapes[shape.index()], shape.value().size());
        continue;
      }
      if (*joined_dimensions[index] != dim.value()) return {};
    }
  }
  if (llvm::is_splat(shape_and_rank_for_dim) &&
      shape_and_rank_for_dim[0].first) {
    return shape_and_rank_for_dim[0].first;
  }
  SmallVector<Value> elements;
  for (int i = 0; i != maxRank; ++i) {
    if (!shape_and_rank_for_dim[i].first) {
      auto one = builder->getIntegerAttr(
          shapes[0].getType().cast<RankedTensorType>().getElementType(), 1);
      elements.push_back(builder->create<ConstantOp>(loc, one));
      continue;
    }
    Value index = builder->create<ConstantIndexOp>(
        loc, i - maxRank + shape_and_rank_for_dim[i].second);
    elements.push_back(builder->create<tensor::ExtractOp>(
        loc, shape_and_rank_for_dim[i].first, index));
  }
  return Value(builder->create<tensor::FromElementsOp>(loc, elements));
}