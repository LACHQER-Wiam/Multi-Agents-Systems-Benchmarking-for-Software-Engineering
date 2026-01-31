int kvmppc_rtas_hcall(struct kvm_vcpu *vcpu)
{
	struct rtas_token_definition *d;
	struct rtas_args args;
	rtas_arg_t *orig_rets;
	gpa_t args_phys;
	int rc;
	args_phys = kvmppc_get_gpr(vcpu, 4) & KVM_PAM;
	vcpu->srcu_idx = srcu_read_lock(&vcpu->kvm->srcu);
	rc = kvm_read_guest(vcpu->kvm, args_phys, &args, sizeof(args));
	srcu_read_unlock(&vcpu->kvm->srcu, vcpu->srcu_idx);
	if (rc)
		goto fail;
	orig_rets = args.rets;
	if (be32_to_cpu(args.nargs) >= ARRAY_SIZE(args.args)) {
		rc = -EINVAL;
		goto fail;
	}
	args.rets = &args.args[be32_to_cpu(args.nargs)];
	mutex_lock(&vcpu->kvm->arch.rtas_token_lock);
	rc = -ENOENT;
	list_for_each_entry(d, &vcpu->kvm->arch.rtas_tokens, list) {
		if (d->token == be32_to_cpu(args.token)) {
			d->handler->handler(vcpu, &args);
			rc = 0;
			break;
		}
	}
	mutex_unlock(&vcpu->kvm->arch.rtas_token_lock);
	if (rc == 0) {
		args.rets = orig_rets;
		rc = kvm_write_guest(vcpu->kvm, args_phys, &args, sizeof(args));
		if (rc)
			goto fail;
	}
	return rc;
fail:
	return rc;
}