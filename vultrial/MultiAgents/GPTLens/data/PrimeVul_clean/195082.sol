void recalc_intercepts(struct vcpu_svm *svm)
{
	struct vmcb_control_area *c, *h, *g;
	unsigned int i;
	vmcb_mark_dirty(svm->vmcb, VMCB_INTERCEPTS);
	if (!is_guest_mode(&svm->vcpu))
		return;
	c = &svm->vmcb->control;
	h = &svm->vmcb01.ptr->control;
	g = &svm->nested.ctl;
	for (i = 0; i < MAX_INTERCEPT; i++)
		c->intercepts[i] = h->intercepts[i];
	if (g->int_ctl & V_INTR_MASKING_MASK) {
		vmcb_clr_intercept(c, INTERCEPT_CR8_READ);
		vmcb_clr_intercept(c, INTERCEPT_CR8_WRITE);
		vmcb_clr_intercept(c, INTERCEPT_VINTR);
	}
	vmcb_clr_intercept(c, INTERCEPT_VMMCALL);
	for (i = 0; i < MAX_INTERCEPT; i++)
		c->intercepts[i] |= g->intercepts[i];
	if (!intercept_smi)
		vmcb_clr_intercept(c, INTERCEPT_SMI);
}