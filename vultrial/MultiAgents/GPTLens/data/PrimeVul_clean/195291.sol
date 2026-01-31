void Compute(OpKernelContext* context) override {
    const Tensor& rhs = context->input(1);
    context->forward_ref_input_to_ref_output(0, 0);
    AllocatorAttributes attr;
    if (!relax_constraints_) {
      attr.set_gpu_compatible(true);
      attr.set_nic_compatible(true);
    }
    {
      mutex_lock l(*context->input_ref_mutex(0));
      const Tensor& old_lhs = context->mutable_input(0,  true);
      const bool same_shape = old_lhs.shape().IsSameSize(rhs.shape());
      if (validate_shape_) {
        OP_REQUIRES(context, same_shape,
                    errors::InvalidArgument(
                        "Assign requires shapes of both tensors to match. "
                        "lhs shape= ",
                        old_lhs.shape().DebugString(),
                        " rhs shape= ", rhs.shape().DebugString()));
      }
      if (old_lhs.IsInitialized() &&
          old_lhs.shape().num_elements() == rhs.shape().num_elements()) {
        Tensor reshaped_old_lhs;
        if (same_shape) {
          reshaped_old_lhs = old_lhs;
        } else {
          CHECK(reshaped_old_lhs.CopyFrom(old_lhs, rhs.shape()));
          context->replace_ref_input(0, reshaped_old_lhs,
                                      true);
        }
        if (use_exclusive_lock_) {
          Copy(context, &reshaped_old_lhs, rhs);
          return;
        }
      } else {
        std::unique_ptr<Tensor> input_alias = context->forward_input(
            1, OpKernelContext::Params::kNoReservation ,
            rhs.dtype(), rhs.shape(), DEVICE_MEMORY, attr);
        if (input_alias != nullptr) {
          context->replace_ref_input(0, *input_alias,  true);
          return;
        }
        Tensor copy_tensor;
        OP_REQUIRES_OK(context,
                       context->allocate_temp(old_lhs.dtype(), rhs.shape(),
                                              &copy_tensor, attr));
        context->clear_recorded_memory();
        context->replace_ref_input(0, copy_tensor,  true);
        if (use_exclusive_lock_) {
          Copy(context, &copy_tensor, rhs);
          return;
        }
      }
    }
    Tensor old_unlocked_lhs = context->mutable_input(0,  false);
    Copy(context, &old_unlocked_lhs, rhs);
  }