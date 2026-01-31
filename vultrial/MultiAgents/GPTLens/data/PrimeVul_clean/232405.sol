void MakeDataset(OpKernelContext* ctx, DatasetBase** output) override {
    const Tensor* indices;
    OP_REQUIRES_OK(ctx, ctx->input("indices", &indices));
    const Tensor* values;
    OP_REQUIRES_OK(ctx, ctx->input("values", &values));
    const Tensor* dense_shape;
    OP_REQUIRES_OK(ctx, ctx->input("dense_shape", &dense_shape));
    OP_REQUIRES(ctx, TensorShapeUtils::IsMatrix(indices->shape()),
                errors::InvalidArgument(
                    "Input indices should be a matrix but received shape ",
                    indices->shape().DebugString()));
    const auto num_indices = indices->NumElements();
    const auto num_values = values->NumElements();
    if (num_indices == 0 || num_values == 0) {
      OP_REQUIRES(ctx, num_indices == num_values,
                  errors::InvalidArgument(
                      "If indices or values are empty, the other one must also "
                      "be. Got indices of shape ",
                      indices->shape().DebugString(), " and values of shape ",
                      values->shape().DebugString()));
    }
    OP_REQUIRES(ctx, TensorShapeUtils::IsVector(values->shape()),
                errors::InvalidArgument(
                    "Input values should be a vector but received shape ",
                    indices->shape().DebugString()));
    OP_REQUIRES(ctx, TensorShapeUtils::IsVector(dense_shape->shape()),
                errors::InvalidArgument(
                    "Input shape should be a vector but received shape ",
                    dense_shape->shape().DebugString()));
    int64_t previous_batch_index = -1;
    for (int64_t i = 0; i < indices->dim_size(0); ++i) {
      int64_t next_batch_index = indices->matrix<int64>()(i, 0);
      OP_REQUIRES(
          ctx, next_batch_index >= previous_batch_index,
          errors::Unimplemented("The SparseTensor must be ordered in the batch "
                                "dimension; handling arbitrarily ordered input "
                                "is not currently supported."));
      previous_batch_index = next_batch_index;
    }
    gtl::InlinedVector<int64, 8> std_order(dense_shape->NumElements(), 0);
    sparse::SparseTensor tensor;
    OP_REQUIRES_OK(
        ctx, sparse::SparseTensor::Create(
                 *indices, *values, TensorShape(dense_shape->vec<int64>()),
                 std_order, &tensor));
    *output = new Dataset<T>(ctx, std::move(tensor));
  }