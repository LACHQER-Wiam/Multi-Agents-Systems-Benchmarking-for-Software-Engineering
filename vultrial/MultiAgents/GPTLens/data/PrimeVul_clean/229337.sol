Status GetDeviceForInput(const EagerOperation& op, const EagerContext& ctx,
                         TensorHandle* tensor_handle, Device** result) {
  Device* cpu_device = ctx.HostCPU();
  string device_name;
  if (tensor_handle->Type() != TensorHandle::LOCAL) {
    Device* device = tensor_handle->device();
    device_name = device != nullptr ? device->name() : cpu_device->name();
    *result = (device == nullptr ? cpu_device : device);
  } else if (tensor_handle->dtype == DT_RESOURCE) {
    const Tensor* tensor;
    TF_RETURN_IF_ERROR(tensor_handle->Tensor(&tensor));
    if (tensor->NumElements() == 0) {
      return errors::InvalidArgument("Empty resource handle");
    }
    const ResourceHandle& handle = tensor->flat<ResourceHandle>()(0);
    device_name = handle.device();
    Device* input_device;
    TF_RETURN_IF_ERROR(
        ctx.FindDeviceFromName(device_name.c_str(), &input_device));
    *result = input_device;
  } else {
    Device* device = tensor_handle->device();
    const bool is_tpu = device != nullptr && device->device_type() == "TPU";
    const bool use_host_memory =
        is_tpu ? MTypeFromDTypeIntsOnDevice(tensor_handle->dtype)
               : MTypeFromDType(tensor_handle->dtype);
    if (use_host_memory) {
      *result = cpu_device;
    } else {
      if (!op.is_function() && device != nullptr && device != cpu_device) {
        device = absl::get<Device*>(op.Device());
      }
      *result = (device == nullptr ? cpu_device : device);
    }
  }
  return Status::OK();
}