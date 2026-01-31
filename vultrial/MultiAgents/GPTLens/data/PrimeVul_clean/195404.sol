void Compute(OpKernelContext* context) override {
    typedef Eigen::Map<const Eigen::Matrix<T, Eigen::Dynamic, Eigen::Dynamic>>
        ConstEigenMatrixMap;
    typedef Eigen::Map<Eigen::Matrix<T, Eigen::Dynamic, Eigen::Dynamic>>
        EigenMatrixMap;
    constexpr int tensor_in_and_out_dims = 4;
    const Tensor& tensor_in = context->input(0);
    OP_REQUIRES(context, tensor_in.dims() == tensor_in_and_out_dims,
                errors::InvalidArgument("tensor_in must be 4-dimensional"));
    std::vector<int> input_size(tensor_in_and_out_dims);
    std::vector<int> output_size(tensor_in_and_out_dims);
    for (int i = 0; i < tensor_in_and_out_dims; ++i) {
      input_size[i] = tensor_in.dim_size(i);
    }
    for (int i = 0; i < tensor_in_and_out_dims; ++i) {
      output_size[i] =
          static_cast<int>(std::floor(input_size[i] / pooling_ratio_[i]));
      DCHECK_GT(output_size[i], 0);
    }
    std::vector<int64_t> height_cum_seq;
    std::vector<int64_t> width_cum_seq;
    GuardedPhiloxRandom generator;
    generator.Init(seed_, seed2_);
    height_cum_seq = GeneratePoolingSequence(input_size[1], output_size[1],
                                             &generator, pseudo_random_);
    width_cum_seq = GeneratePoolingSequence(input_size[2], output_size[2],
                                            &generator, pseudo_random_);
    Tensor* output_tensor = nullptr;
    OP_REQUIRES_OK(context, context->allocate_output(
                                0,
                                TensorShape({output_size[0], output_size[1],
                                             output_size[2], output_size[3]}),
                                &output_tensor));
    Tensor* output_height_seq_tensor = nullptr;
    OP_REQUIRES_OK(
        context,
        context->allocate_output(
            1, TensorShape({static_cast<int64_t>(height_cum_seq.size())}),
            &output_height_seq_tensor));
    Tensor* output_width_seq_tensor = nullptr;
    OP_REQUIRES_OK(
        context,
        context->allocate_output(
            2, TensorShape({static_cast<int64_t>(width_cum_seq.size())}),
            &output_width_seq_tensor));
    ConstEigenMatrixMap in_mat(tensor_in.flat<T>().data(), input_size[3],
                               input_size[2] * input_size[1] * input_size[0]);
    EigenMatrixMap out_mat(output_tensor->flat<T>().data(), output_size[3],
                           output_size[2] * output_size[1] * output_size[0]);
    output_tensor->flat<T>().setConstant(Eigen::NumTraits<T>::lowest());
    auto output_height_seq_flat = output_height_seq_tensor->flat<int64_t>();
    auto output_width_seq_flat = output_width_seq_tensor->flat<int64_t>();
    for (int i = 0; i < height_cum_seq.size(); ++i) {
      output_height_seq_flat(i) = height_cum_seq[i];
    }
    for (int i = 0; i < width_cum_seq.size(); ++i) {
      output_width_seq_flat(i) = width_cum_seq[i];
    }
    const int64_t height_max = input_size[1] - 1;
    const int64_t width_max = input_size[2] - 1;
    for (int64_t b = 0; b < input_size[0]; ++b) {
      for (int64_t hs = 0; hs < height_cum_seq.size() - 1; ++hs) {
        const int64_t height_start = height_cum_seq[hs];
        int64_t height_end =
            overlapping_ ? height_cum_seq[hs + 1] : height_cum_seq[hs + 1] - 1;
        height_end = std::min(height_end, height_max);
        for (int64_t ws = 0; ws < width_cum_seq.size() - 1; ++ws) {
          const int64_t out_offset =
              (b * output_size[1] + hs) * output_size[2] + ws;
          const int64_t width_start = width_cum_seq[ws];
          int64_t width_end =
              overlapping_ ? width_cum_seq[ws + 1] : width_cum_seq[ws + 1] - 1;
          width_end = std::min(width_end, width_max);
          for (int64_t h = height_start; h <= height_end; ++h) {
            for (int64_t w = width_start; w <= width_end; ++w) {
              const int64_t in_offset =
                  (b * input_size[1] + h) * input_size[2] + w;
              out_mat.col(out_offset) =
                  out_mat.col(out_offset).cwiseMax(in_mat.col(in_offset));
            }
          }
        }
      }
    }
  }