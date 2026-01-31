void Compute(OpKernelContext* ctx) override {
    const Tensor& input = ctx->input(kInputTensorIndex);
    const Tensor& input_min = ctx->input(kInputMinIndex);
    const Tensor& input_max = ctx->input(kInputMaxIndex);
    const size_t depth = input_max.NumElements();
    OP_REQUIRES(
        ctx, input_min.dim_size(0) == depth,
        errors::InvalidArgument("input_min has incorrect size, expected ",
                                depth, " was ", input_min.dim_size(0)));
    OP_REQUIRES(
        ctx, input_max.dim_size(0) == depth,
        errors::InvalidArgument("input_max has incorrect size, expected ",
                                depth, " was ", input_max.dim_size(0)));
    const float* input_min_data = input_min.flat<float>().data();
    const float* input_max_data = input_max.flat<float>().data();
    std::vector<float> ranges(depth);
    bool is_non_negative = true;
    Eigen::array<int, 2> shuffling({1, 0});
    auto input_matrix = input.flat_inner_dims<qint32>();
    auto transposed_input = input_matrix.shuffle(shuffling);
    float out_min_max = std::numeric_limits<float>::min();
#ifdef ENABLE_ONEDNN_OPENMP
#ifdef _MSC_VER
#pragma omp parallel for
#else
#pragma omp parallel for reduction(max : out_min_max)
#endif
#endif  
    for (int64_t i = 0; i < depth; ++i) {
      Eigen::Tensor<qint32, 0, Eigen::RowMajor> min =
          transposed_input.chip<0>(i).minimum();
      Eigen::Tensor<qint32, 0, Eigen::RowMajor> max =
          transposed_input.chip<0>(i).maximum();
      const int32_t min_per_channel = min();
      const int32_t max_per_channel = max();
      const int32_t abs_max =
          std::max(std::abs(min_per_channel), std::abs(max_per_channel));
      float scale =
          std::max(std::abs(input_min_data[i]), std::abs(input_max_data[i]));
      ranges[i] =
          scale * static_cast<float>(abs_max) / static_cast<float>(1L << 31);
      if (min_per_channel < 0) is_non_negative = false;
      out_min_max = std::max(out_min_max, ranges[i]);
    }
    if (out_min_max > clip_value_max_) out_min_max = clip_value_max_;
    Tensor* output_min = nullptr;
    Tensor* output_max = nullptr;
    OP_REQUIRES_OK(ctx, ctx->allocate_output(kOutputMinIndex, {}, &output_min));
    OP_REQUIRES_OK(ctx, ctx->allocate_output(kOutputMaxIndex, {}, &output_max));
    output_min->flat<float>()(0) = is_non_negative ? 0.0f : -out_min_max;
    output_max->flat<float>()(0) = out_min_max;
  }