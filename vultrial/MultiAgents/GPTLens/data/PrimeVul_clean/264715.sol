bool IsConstantFoldable(
    const Node* n,
    const std::unordered_map<string, std::vector<PartialTensorShape>>*
        shape_map,
    const std::function<bool(const Node*)>& consider,
    int64_t max_constant_size_in_bytes,
    std::unordered_map<const Node*, std::vector<Tensor>>*
        shape_replacement_map) {
  if (n->IsConstant()) {
    return n->output_type(0) != DT_RESOURCE;
  }
  if (MaybeReplaceShapeOp(n, shape_map, shape_replacement_map)) {
    return true;
  }
  if (n->op_def().is_stateful()) {
    return false;
  }
  if (consider && !consider(n)) {
    return false;
  }
  if (shape_map != nullptr) {
    auto shape_it = shape_map->find(n->name());
    if (shape_it != shape_map->end()) {
      for (int64_t i = 0; i < shape_it->second.size(); ++i) {
        const auto& out_shape = shape_it->second[i];
        if (out_shape.IsFullyDefined() &&
            out_shape.num_elements() * DataTypeSize(n->output_type(i)) >
                max_constant_size_in_bytes) {
          return false;
        }
      }
    }
  }
  if (n->IsControlFlow() || n->IsSend() || n->IsRecv()) {
    return false;
  }
  if (n->IsGetSessionHandle() || n->IsGetSessionTensor() ||
      n->IsDeleteSessionTensor()) {
    return false;
  }
  if (n->IsSource()) {
    return false;
  }
  if (n->IsSink()) {
    return false;
  }
  if (n->IsFakeParam()) {
    return false;
  }
  if (!KernelDefAvailable(DeviceType(DEVICE_CPU), n->def())) {
    return false;
  }
  if (n->attrs().Find(kScopedAllocatorAttrName) != nullptr) {
    VLOG(2) << "Skip node [" << n->DebugString()
            << "] for constant folding due to scoped allocator";
    return false;
  }
  return true;
}