void MakeDataset(OpKernelContext* ctx, DatasetBase** output) override {
    const Tensor* indices;
    OP_REQUIRES_OK(ctx, ctx->input("indices", &indices));
    const Tensor* values;
    OP_REQUIRES_OK(ctx, ctx->input("values", &values));
    const Tensor* dense_shape;
    OP_REQUIRES_OK(ctx, ctx->input("dense_shape", &dense_shape));
    OP_REQUIRES(ctx, TensorShapeUtils::IsMatrix(indices->shape()),
                errors::InvalidArgument("Input indices must be a matrix. Got: ",
                                        indices->shape().DebugString()));
    OP_REQUIRES(ctx, TensorShapeUtils::IsVector(values->shape()),
                errors::InvalidArgument("Input values must be a vector. Got: ",
                                        values->shape().DebugString()));
    OP_REQUIRES(ctx, TensorShapeUtils::IsVector(dense_shape->shape()),
                errors::InvalidArgument("Input shape must be a vector. Got: ",
                                        dense_shape->shape().DebugString()));
    OP_REQUIRES(
        ctx, values->shape().dim_size(0) == indices->shape().dim_size(0),
        errors::InvalidArgument(
            "Number of values must match first dimension of indices. ", "Got ",
            values->shape().dim_size(0),
            " values, indices shape: ", indices->shape().DebugString()));
    OP_REQUIRES(
        ctx, dense_shape->shape().dim_size(0) == indices->shape().dim_size(1),
        errors::InvalidArgument(
            "Number of dimensions must match second dimension of indices. ",
            "Got ", dense_shape->shape().dim_size(0),
            " dimensions, indices shape: ", indices->shape().DebugString()));
    OP_REQUIRES(ctx, dense_shape->NumElements() > 0,
                errors::InvalidArgument(
                    "The shape argument requires at least one element."));
    int64_t previous_batch_index = -1;
    for (int64_t i = 0; i < indices->dim_size(0); ++i) {
      int64_t next_batch_index = indices->matrix<int64_t>()(i, 0);
      OP_REQUIRES(
          ctx, next_batch_index >= previous_batch_index,
          errors::Unimplemented("The SparseTensor must be ordered in the batch "
                                "dimension; handling arbitrarily ordered input "
                                "is not currently supported."));
      previous_batch_index = next_batch_index;
    }
    gtl::InlinedVector<int64_t, 8> std_order(dense_shape->NumElements(), 0);
    sparse::SparseTensor tensor;
    OP_REQUIRES_OK(
        ctx, sparse::SparseTensor::Create(
                 *indices, *values, TensorShape(dense_shape->vec<int64_t>()),
                 std_order, &tensor));
    *output = new Dataset<T>(ctx, std::move(tensor));
  }