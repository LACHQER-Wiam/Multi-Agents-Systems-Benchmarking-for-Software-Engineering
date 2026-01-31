void Compute(OpKernelContext* context) override {
    OpInputList ragged_nested_splits_in;
    OP_REQUIRES_OK(context, context->input_list("rt_nested_splits",
                                                &ragged_nested_splits_in));
    const int ragged_nested_splits_len = ragged_nested_splits_in.size();
    RaggedTensorVariant batched_ragged_input;
    batched_ragged_input.set_values(context->input(ragged_nested_splits_len));
    batched_ragged_input.mutable_nested_splits()->reserve(
        ragged_nested_splits_len);
    for (int i = 0; i < ragged_nested_splits_len; i++) {
      batched_ragged_input.append_splits(ragged_nested_splits_in[i]);
    }
    if (!batched_input_) {
      Tensor* encoded_scalar;
      OP_REQUIRES_OK(context, context->allocate_output(0, TensorShape({}),
                                                       &encoded_scalar));
      encoded_scalar->scalar<Variant>()() = std::move(batched_ragged_input);
      return;
    }
    std::vector<RaggedTensorVariant> unbatched_ragged_input;
    auto batched_splits_top_vec =
        batched_ragged_input.splits(0).vec<SPLIT_TYPE>();
    int num_components = batched_splits_top_vec.size() - 1;
    OP_REQUIRES(context, num_components >= 0,
                errors::Internal("Invalid split argument."));
    OP_REQUIRES_OK(context, UnbatchRaggedZerothDim<VALUE_TYPE, SPLIT_TYPE>(
                                batched_ragged_input, &unbatched_ragged_input));
    Tensor* encoded_vector;
    int output_size = unbatched_ragged_input.size();
    OP_REQUIRES_OK(context,
                   context->allocate_output(0, TensorShape({output_size}),
                                            &encoded_vector));
    auto encoded_vector_t = encoded_vector->vec<Variant>();
    for (int i = 0; i < output_size; i++) {
      encoded_vector_t(i) = unbatched_ragged_input[i];
    }
  }