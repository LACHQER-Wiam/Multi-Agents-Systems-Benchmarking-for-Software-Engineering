Status ShapeRefiner::InferShapesForFunctionSubNode(
    const Node* node, InferenceContext* outer_context) {
  TF_RETURN_IF_ERROR(AddNodeInternal(node, outer_context));
  InferenceContext* node_context = CHECK_NOTNULL(GetContext(node));
  if (StringPiece(node->type_string()) == kArgOp) {
    int index;
    TF_RETURN_IF_ERROR(GetNodeAttr(AttrSlice(node->def()), "index", &index));
    if (index < 0 || outer_context->num_inputs() <= index) {
      return errors::Internal(
          "Function instantiation included invalid input index: ", index,
          " not in [0, ", outer_context->num_inputs(), ").");
    }
    if (outer_context->input(index).SameHandle(ShapeHandle())) {
      VLOG(1) << "Function instantiation has undefined input shape at "
              << "index: " << index << " in the outer inference context.";
      node_context->set_output(0, node_context->UnknownShape());
    } else {
      node_context->set_output(0, outer_context->input(index));
    }
    auto* resource = outer_context->input_handle_shapes_and_types(index);
    if (resource) {
      node_context->set_output_handle_shapes_and_types(0, *resource);
    }
  } else if (StringPiece(node->type_string()) == kRetvalOp) {
    int index;
    TF_RETURN_IF_ERROR(GetNodeAttr(AttrSlice(node->def()), "index", &index));
    if (index < 0 || outer_context->num_outputs() <= index) {
      return errors::Internal(
          "Function instantiation included invalid output index: ", index,
          " not in [0, ", outer_context->num_outputs(), ").");
    }
    ShapeHandle handle;
    TensorShapeProto proto;
    node_context->ShapeHandleToProto(node_context->input(0), &proto);
    TF_RETURN_IF_ERROR(outer_context->MakeShapeFromShapeProto(proto, &handle));
    outer_context->set_output(index, handle);
    auto* resource = node_context->input_handle_shapes_and_types(0);
    if (resource) {
      outer_context->set_output_handle_shapes_and_types(index, *resource);
    }
  }
  return Status::OK();
}