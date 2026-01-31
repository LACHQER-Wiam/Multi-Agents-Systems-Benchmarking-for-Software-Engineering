Status ImmutableExecutorState::Initialize(const Graph& graph) {
  TF_RETURN_IF_ERROR(gview_.Initialize(&graph));
  ControlFlowInfo cf_info;
  TF_RETURN_IF_ERROR(BuildControlFlowInfo(&graph, &cf_info));
  for (auto& it : cf_info.unique_frame_names) {
    EnsureFrameInfo(it)->nodes =
        absl::make_unique<std::vector<const NodeItem*>>();
  }
  root_frame_info_ = frame_info_[""].get();
  pending_ids_.resize(gview_.num_nodes());
  requires_control_flow_ = false;
  for (const Node* n : graph.nodes()) {
    if (IsSink(n)) continue;
    if (IsSwitch(n) || IsMerge(n) || IsEnter(n) || IsExit(n)) {
      requires_control_flow_ = true;
    } else if (IsRecv(n)) {
      string send_device;
      string recv_device;
      TF_RETURN_IF_ERROR(GetNodeAttr(n->attrs(), "send_device", &send_device));
      TF_RETURN_IF_ERROR(GetNodeAttr(n->attrs(), "recv_device", &recv_device));
      if (send_device != recv_device) {
        requires_control_flow_ = true;
      }
    }
    const int id = n->id();
    const string& frame_name = cf_info.frame_names[id];
    FrameInfo* frame_info = EnsureFrameInfo(frame_name);
    NodeItem* item = gview_.node(id);
    item->node_id = id;
    item->input_start = frame_info->total_inputs;
    frame_info->total_inputs += n->num_inputs();
    Status s = params_.create_kernel(n->properties(), &item->kernel);
    if (!s.ok()) {
      params_.delete_kernel(item->kernel);
      item->kernel = nullptr;
      s = AttachDef(s, *n);
      return s;
    }
    CHECK(item->kernel);
    item->kernel_is_async = (item->kernel->AsAsync() != nullptr);
    item->is_merge = IsMerge(n);
    item->is_any_consumer_merge_or_control_trigger = false;
    for (const Node* consumer : n->out_nodes()) {
      if (IsMerge(consumer) || IsControlTrigger(consumer)) {
        item->is_any_consumer_merge_or_control_trigger = true;
        break;
      }
    }
    const Tensor* const_tensor = item->kernel->const_tensor();
    if (const_tensor) {
      const_tensors_.emplace_back(*const_tensor);
    }
    item->const_tensor = const_tensor;
    item->is_noop = (item->kernel->type_string_view() == "NoOp");
    item->is_enter = IsEnter(n);
    if (item->is_enter) {
      bool is_constant_enter;
      TF_RETURN_IF_ERROR(
          GetNodeAttr(n->attrs(), "is_constant", &is_constant_enter));
      item->is_constant_enter = is_constant_enter;
      string frame_name;
      TF_RETURN_IF_ERROR(GetNodeAttr(n->attrs(), "frame_name", &frame_name));
      FrameInfo* frame_info = frame_info_[frame_name].get();
      int parallel_iterations;
      TF_RETURN_IF_ERROR(
          GetNodeAttr(n->attrs(), "parallel_iterations", &parallel_iterations));
      if (frame_info->parallel_iterations == -1) {
        frame_info->parallel_iterations = parallel_iterations;
      } else if (frame_info->parallel_iterations != parallel_iterations) {
        LOG(WARNING) << "Loop frame \"" << frame_name
                     << "\" had two different values for parallel_iterations: "
                     << frame_info->parallel_iterations << " vs. "
                     << parallel_iterations << ".";
      }
      if (enter_frame_info_.size() <= id) {
        enter_frame_info_.resize(id + 1);
      }
      enter_frame_info_[id] = frame_info;
    } else {
      item->is_constant_enter = false;
    }
    item->is_exit = IsExit(n);
    item->is_control_trigger = IsControlTrigger(n);
    item->is_source = IsSource(n);
    item->is_enter_exit_or_next_iter =
        (IsEnter(n) || IsExit(n) || IsNextIteration(n));
    item->is_transfer_node = IsTransferNode(n);
    item->is_initialization_op = IsInitializationOp(n);
    item->is_recv_or_switch = IsRecv(n) || IsSwitch(n);
    item->is_next_iteration = IsNextIteration(n);
    item->is_distributed_communication = IsDistributedCommunication(n);
    size_t max_pending, max_dead;
    GetMaxPendingCounts(n, &max_pending, &max_dead);
    pending_ids_[id] =
        frame_info->pending_counts_layout.CreateHandle(max_pending, max_dead);
    if (n->in_edges().empty()) {
      root_nodes_.push_back(item);
    }
    frame_info->nodes->push_back(item);
    if (item->is_enter) {
      string enter_name;
      TF_RETURN_IF_ERROR(GetNodeAttr(n->attrs(), "frame_name", &enter_name));
      EnsureFrameInfo(enter_name)->input_count++;
    }
    std::unique_ptr<bool[]> outputs_required(new bool[n->num_outputs()]);
    std::fill(&outputs_required[0], &outputs_required[n->num_outputs()], false);
    int32_t unused_outputs = n->num_outputs();
    for (const Edge* e : n->out_edges()) {
      if (IsSink(e->dst())) continue;
      if (e->src_output() >= 0) {
        if (!outputs_required[e->src_output()]) {
          --unused_outputs;
          outputs_required[e->src_output()] = true;
        }
      }
    }
    if (unused_outputs > 0) {
      for (int i = 0; i < n->num_outputs(); ++i) {
        if (!outputs_required[i]) {
          metrics::RecordUnusedOutput(n->type_string());
        }
      }
      item->outputs_required = std::move(outputs_required);
    }
  }
  for (const Node* n : graph.nodes()) {
    if (IsSink(n)) continue;
    const int id = n->id();
    NodeItem* item = gview_.node(id);
    for (EdgeInfo& e : item->mutable_output_edges()) {
      const int dst_id = e.dst_id;
      NodeItem* dst_item = gview_.node(dst_id);
      e.input_slot += dst_item->input_start;
    }
  }
  InitializePending(&graph, cf_info);
  return gview_.SetAllocAttrs(&graph, params_.device);
}