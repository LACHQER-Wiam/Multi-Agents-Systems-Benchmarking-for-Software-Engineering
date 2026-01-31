GF_Err BD_DecMFFieldVec(GF_BifsDecoder * codec, GF_BitStream *bs, GF_Node *node, GF_FieldInfo *field, Bool is_mem_com)
{
	GF_Err e;
	u32 NbBits, nbFields;
	u32 i;
	GF_ChildNodeItem *last;
	u8 qp_local, qp_on, initial_qp;
	GF_FieldInfo sffield;
	memset(&sffield, 0, sizeof(GF_FieldInfo));
	sffield.fieldIndex = field->fieldIndex;
	sffield.fieldType = gf_sg_vrml_get_sf_type(field->fieldType);
	sffield.NDTtype = field->NDTtype;
	sffield.name = field->name;
	initial_qp = qp_local = qp_on = 0;
	NbBits = gf_bs_read_int(bs, 5);
	nbFields = gf_bs_read_int(bs, NbBits);
	if (codec->ActiveQP) {
		initial_qp = 1;
		gf_bifs_dec_qp14_set_length(codec, nbFields);
	}
	if (field->fieldType != GF_SG_VRML_MFNODE) {
		e = gf_sg_vrml_mf_alloc(field->far_ptr, field->fieldType, nbFields);
		if (e) return e;
		for (i=0; i<nbFields; i++) {
			e = gf_sg_vrml_mf_get_item(field->far_ptr, field->fieldType, & sffield.far_ptr, i);
			if (e) return e;
			e = gf_bifs_dec_sf_field(codec, bs, node, &sffield, GF_FALSE);
			if (e) return e;
		}
	} else {
		last = NULL;
		for (i=0; i<nbFields; i++) {
			GF_Node *new_node = gf_bifs_dec_node(codec, bs, field->NDTtype);
			if (new_node) {
				e = gf_node_register(new_node, is_mem_com ? NULL : node);
				if (e) return e;
				if (node) {
					if (gf_node_get_tag(new_node) == TAG_MPEG4_QuantizationParameter) {
						qp_local = ((M_QuantizationParameter *)new_node)->isLocal;
						if (qp_on) gf_bifs_dec_qp_remove(codec, GF_FALSE);
						e = gf_bifs_dec_qp_set(codec, new_node);
						if (e) return e;
						qp_on = 1;
						if (qp_local) qp_local = 2;
						if (codec->force_keep_qp) {
							e = gf_node_list_add_child_last(field->far_ptr, new_node, &last);
							if (e) return e;
						} else {
							gf_node_register(new_node, NULL);
							gf_node_unregister(new_node, node);
						}
					} else {
						e = gf_node_list_add_child_last(field->far_ptr, new_node, &last);
						if (e) return e;
					}
				}
				else if (codec->pCurrentProto) {
					e = gf_node_list_add_child_last( (GF_ChildNodeItem **)field->far_ptr, new_node, &last);
					if (e) return e;
				}
			} else {
				return codec->LastError ? codec->LastError : GF_NON_COMPLIANT_BITSTREAM;
			}
		}
		if (qp_on && qp_local) {
			if (qp_local == 2) {
			} else {
				gf_bifs_dec_qp_remove(codec, initial_qp);
			}
		}
	}
	if (qp_on) gf_bifs_dec_qp_remove(codec, GF_TRUE);
	return GF_OK;
}