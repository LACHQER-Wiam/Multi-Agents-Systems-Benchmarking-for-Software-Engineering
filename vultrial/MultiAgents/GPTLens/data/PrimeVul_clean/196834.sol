Status SparseCountSparseOutputShapeFn(InferenceContext *c) {
  auto rank = c->Dim(c->input(0), 1);
  auto nvals = c->UnknownDim();
  c->set_output(0, c->Matrix(nvals, rank));  
  c->set_output(1, c->Vector(nvals));        
  c->set_output(2, c->Vector(rank));         
  return Status::OK();
}