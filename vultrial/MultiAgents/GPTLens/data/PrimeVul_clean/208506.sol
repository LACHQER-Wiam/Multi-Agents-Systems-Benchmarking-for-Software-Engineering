tgs_build_reply(astgs_request_t priv,
		hdb_entry_ex *krbtgt,
		krb5_enctype krbtgt_etype,
		const krb5_keyblock *replykey,
		int rk_is_subkey,
		krb5_ticket *ticket,
		const char **e_text,
		AuthorizationData **auth_data,
		const struct sockaddr *from_addr)
{
    krb5_context context = priv->context;
    krb5_kdc_configuration *config = priv->config;
    KDC_REQ *req = &priv->req;
    KDC_REQ_BODY *b = &priv->req.req_body;
    const char *from = priv->from;
    krb5_error_code ret, ret2;
    krb5_principal cp = NULL, sp = NULL, rsp = NULL, tp = NULL, dp = NULL;
    krb5_principal krbtgt_out_principal = NULL;
    char *spn = NULL, *cpn = NULL, *tpn = NULL, *dpn = NULL, *krbtgt_out_n = NULL;
    hdb_entry_ex *server = NULL, *client = NULL, *s4u2self_impersonated_client = NULL;
    HDB *clientdb, *s4u2self_impersonated_clientdb;
    krb5_realm ref_realm = NULL;
    EncTicketPart *tgt = &ticket->ticket;
    krb5_principals spp = NULL;
    const EncryptionKey *ekey;
    krb5_keyblock sessionkey;
    krb5_kvno kvno;
    krb5_data rspac;
    const char *tgt_realm = 
        krb5_principal_get_realm(context, krbtgt->entry.principal);
    const char *our_realm = 
        krb5_principal_get_comp_string(context, krbtgt->entry.principal, 1);
    char **capath = NULL;
    size_t num_capath = 0;
    hdb_entry_ex *krbtgt_out = NULL;
    METHOD_DATA enc_pa_data;
    PrincipalName *s;
    Realm r;
    EncTicketPart adtkt;
    char opt_str[128];
    int signedpath = 0;
    Key *tkey_check;
    Key *tkey_sign;
    int flags = HDB_F_FOR_TGS_REQ;
    memset(&sessionkey, 0, sizeof(sessionkey));
    memset(&adtkt, 0, sizeof(adtkt));
    krb5_data_zero(&rspac);
    memset(&enc_pa_data, 0, sizeof(enc_pa_data));
    s = b->sname;
    r = b->realm;
    if (b->kdc_options.canonicalize)
	flags |= HDB_F_CANON;
    if(b->kdc_options.enc_tkt_in_skey){
	Ticket *t;
	hdb_entry_ex *uu;
	krb5_principal p;
	Key *uukey;
	krb5uint32 second_kvno = 0;
	krb5uint32 *kvno_ptr = NULL;
	if(b->additional_tickets == NULL ||
	   b->additional_tickets->len == 0){
	    ret = KRB5KDC_ERR_BADOPTION; 
	    kdc_log(context, config, 4,
		    "No second ticket present in user-to-user request");
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "No second ticket present in user-to-user request");
	    goto out;
	}
	t = &b->additional_tickets->val[0];
	if(!get_krbtgt_realm(&t->sname)){
	    kdc_log(context, config, 4,
		    "Additional ticket is not a ticket-granting ticket");
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Additional ticket is not a ticket-granting ticket");
	    ret = KRB5KDC_ERR_POLICY;
	    goto out;
	}
	_krb5_principalname2krb5_principal(context, &p, t->sname, t->realm);
	ret = krb5_unparse_name(context, p, &tpn);
	if (ret)
		goto out;
	if(t->enc_part.kvno){
	    second_kvno = *t->enc_part.kvno;
	    kvno_ptr = &second_kvno;
	}
	ret = _kdc_db_fetch(context, config, p,
			    HDB_F_GET_KRBTGT, kvno_ptr,
			    NULL, &uu);
	krb5_free_principal(context, p);
	if(ret){
	    if (ret == HDB_ERR_NOENTRY)
		ret = KRB5KDC_ERR_S_PRINCIPAL_UNKNOWN;
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "User-to-user service principal (TGS) unknown");
	    goto out;
	}
	ret = hdb_enctype2key(context, &uu->entry, NULL,
			      t->enc_part.etype, &uukey);
	if(ret){
	    _kdc_free_ent(context, uu);
	    ret = KRB5KDC_ERR_ETYPE_NOSUPP; 
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "User-to-user enctype not supported");
	    goto out;
	}
	ret = krb5_decrypt_ticket(context, t, &uukey->key, &adtkt, 0);
	_kdc_free_ent(context, uu);
	if(ret) {
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "User-to-user TGT decrypt failure");
	    goto out;
        }
	ret = verify_flags(context, config, &adtkt, tpn);
	if (ret) {
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "User-to-user TGT expired or invalid");
	    goto out;
        }
	s = &adtkt.cname;
	r = adtkt.crealm;
    }
    _krb5_principalname2krb5_principal(context, &sp, *s, r);
    ret = krb5_unparse_name(context, sp, &priv->sname);
    if (ret)
	goto out;
    spn = priv->sname;
    _krb5_principalname2krb5_principal(context, &cp, tgt->cname, tgt->crealm);
    ret = krb5_unparse_name(context, cp, &priv->cname);
    if (ret)
	goto out;
    cpn = priv->cname;
    unparse_flags (KDCOptions2int(b->kdc_options),
		   asn1_KDCOptions_units(),
		   opt_str, sizeof(opt_str));
    if(*opt_str)
	kdc_log(context, config, 4,
		"TGS-REQ %s from %s for %s [%s]",
		cpn, from, spn, opt_str);
    else
	kdc_log(context, config, 4,
		"TGS-REQ %s from %s for %s", cpn, from, spn);
server_lookup:
    ret = _kdc_db_fetch(context, config, sp,
                        HDB_F_GET_SERVER | HDB_F_DELAY_NEW_KEYS | flags,
			NULL, NULL, &server);
    priv->server = server;
    if (ret == HDB_ERR_NOT_FOUND_HERE) {
	kdc_log(context, config, 5, "target %s does not have secrets at this KDC, need to proxy", spn);
        _kdc_audit_addreason((kdc_request_t)priv, "Target not found here");
	goto out;
    } else if (ret == HDB_ERR_WRONG_REALM) {
        free(ref_realm);
	ref_realm = strdup(server->entry.principal->realm);
	if (ref_realm == NULL) {
            ret = krb5_enomem(context);
	    goto out;
	}
	kdc_log(context, config, 4,
		"Returning a referral to realm %s for "
		"server %s.",
		ref_realm, spn);
	krb5_free_principal(context, sp);
	sp = NULL;
	ret = krb5_make_principal(context, &sp, r, KRB5_TGS_NAME,
				  ref_realm, NULL);
	if (ret)
	    goto out;
	free(priv->sname);
        priv->sname = NULL;
	ret = krb5_unparse_name(context, sp, &priv->sname);
	if (ret)
	    goto out;
	spn = priv->sname;
	goto server_lookup;
    } else if (ret) {
	const char *new_rlm, *msg;
	Realm req_rlm;
	krb5_realm *realms;
	if ((req_rlm = get_krbtgt_realm(&sp->name)) != NULL) {
            if (capath == NULL) {
                ret2 = _krb5_find_capath(context, tgt->crealm, our_realm,
                                         req_rlm, TRUE, &capath, &num_capath);
                if (ret2) {
                    ret = ret2;
                    _kdc_audit_addreason((kdc_request_t)priv,
                                         "No trusted path from client realm to ours");
                    goto out;
                }
            }
            new_rlm = num_capath > 0 ? capath[--num_capath] : NULL;
            if (new_rlm) {
                kdc_log(context, config, 5, "krbtgt from %s via %s for "
                        "realm %s not found, trying %s", tgt->crealm,
                        our_realm, req_rlm, new_rlm);
                free(ref_realm);
                ref_realm = strdup(new_rlm);
                if (ref_realm == NULL) {
                    ret = krb5_enomem(context);
                    goto out;
                }
                krb5_free_principal(context, sp);
                sp = NULL;
                krb5_make_principal(context, &sp, r,
                                    KRB5_TGS_NAME, ref_realm, NULL);
                free(priv->sname);
                priv->sname = NULL;
                ret = krb5_unparse_name(context, sp, &priv->sname);
                if (ret)
                    goto out;
                spn = priv->sname;
                goto server_lookup;
            }
	} else if (need_referral(context, config, &b->kdc_options, sp, &realms)) {
	    if (strcmp(realms[0], sp->realm) != 0) {
		kdc_log(context, config, 4,
			"Returning a referral to realm %s for "
			"server %s that was not found",
			realms[0], spn);
		krb5_free_principal(context, sp);
                sp = NULL;
		krb5_make_principal(context, &sp, r, KRB5_TGS_NAME,
				    realms[0], NULL);
		free(priv->sname);
                priv->sname = NULL;
		ret = krb5_unparse_name(context, sp, &priv->sname);
		if (ret) {
		    krb5_free_host_realm(context, realms);
		    goto out;
		}
		spn = priv->sname;
                free(ref_realm);
		ref_realm = strdup(realms[0]);
		krb5_free_host_realm(context, realms);
		goto server_lookup;
	    }
	    krb5_free_host_realm(context, realms);
	}
	msg = krb5_get_error_message(context, ret);
	kdc_log(context, config, 3,
		"Server not found in database: %s: %s", spn, msg);
	krb5_free_error_message(context, msg);
	if (ret == HDB_ERR_NOENTRY)
	    ret = KRB5KDC_ERR_S_PRINCIPAL_UNKNOWN;
        _kdc_audit_addreason((kdc_request_t)priv,
                             "Service principal unknown");
	goto out;
    }
    if (server->entry.flags.force_canonicalize)
	rsp = server->entry.principal;
    else
	rsp = sp;
    {
	krb5_enctype etype;
	if(b->kdc_options.enc_tkt_in_skey) {
	    size_t i;
	    ekey = &adtkt.key;
	    for(i = 0; i < b->etype.len; i++)
		if (b->etype.val[i] == adtkt.key.keytype)
		    break;
	    if(i == b->etype.len) {
		kdc_log(context, config, 4,
			"Addition ticket have not matching etypes");
		krb5_clear_error_message(context);
		ret = KRB5KDC_ERR_ETYPE_NOSUPP;
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "No matching enctypes for 2nd ticket");
		goto out;
	    }
	    etype = b->etype.val[i];
	    kvno = 0;
	} else {
	    Key *skey;
	    ret = _kdc_find_etype(priv, krb5_principal_is_krbtgt(context, sp)
							     ? KFE_IS_TGS : 0,
				  b->etype.val, b->etype.len, &etype, NULL,
				  NULL);
	    if(ret) {
		kdc_log(context, config, 4,
			"Server (%s) has no support for etypes", spn);
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "Enctype not supported");
		goto out;
	    }
	    ret = _kdc_get_preferred_key(context, config, server, spn,
					 NULL, &skey);
	    if(ret) {
		kdc_log(context, config, 4,
			"Server (%s) has no supported etypes", spn);
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "Enctype not supported");
		goto out;
	    }
	    ekey = &skey->key;
	    kvno = server->entry.kvno;
	}
	ret = krb5_generate_random_keyblock(context, etype, &sessionkey);
	if (ret)
	    goto out;
    }
    ret = hdb_enctype2key(context, &krbtgt->entry, NULL, 
			  krbtgt_etype, &tkey_check);
    if(ret) {
	kdc_log(context, config, 4,
		    "Failed to find key for krbtgt PAC check");
        _kdc_audit_addreason((kdc_request_t)priv,
                             "No key for krbtgt PAC check");
	goto out;
    }
    ret = krb5_make_principal(context,
                              &krbtgt_out_principal,
                              our_realm,
                              KRB5_TGS_NAME,
                              our_realm,
                              NULL);
    if (ret) {
        kdc_log(context, config, 4,
                "Failed to make krbtgt principal name object for "
                "authz-data signatures");
        goto out;
    }
    ret = krb5_unparse_name(context, krbtgt_out_principal, &krbtgt_out_n);
    if (ret) {
        kdc_log(context, config, 4,
                "Failed to make krbtgt principal name object for "
                "authz-data signatures");
        goto out;
    }
    ret = _kdc_db_fetch(context, config, krbtgt_out_principal,
			HDB_F_GET_KRBTGT, NULL, NULL, &krbtgt_out);
    if (ret) {
	char *ktpn = NULL;
	ret = krb5_unparse_name(context, krbtgt->entry.principal, &ktpn);
	kdc_log(context, config, 4,
		"No such principal %s (needed for authz-data signature keys) "
		"while processing TGS-REQ for service %s with krbtg %s",
		krbtgt_out_n, spn, (ret == 0) ? ktpn : "<unknown>");
	free(ktpn);
	ret = KRB5KRB_AP_ERR_NOT_US;
	goto out;
    }
    if (strcmp(krb5_principal_get_realm(context, server->entry.principal),
	       krb5_principal_get_realm(context, krbtgt_out->entry.principal)) != 0) {
	char *ktpn;
	ret = krb5_unparse_name(context, krbtgt_out->entry.principal, &ktpn);
	kdc_log(context, config, 4,
		"Request with wrong krbtgt: %s",
		(ret == 0) ? ktpn : "<unknown>");
	if(ret == 0)
	    free(ktpn);
	ret = KRB5KRB_AP_ERR_NOT_US;
        _kdc_audit_addreason((kdc_request_t)priv, "Request with wrong TGT");
	goto out;
    }
    ret = _kdc_get_preferred_key(context, config, krbtgt_out, krbtgt_out_n,
				 NULL, &tkey_sign);
    if (ret) {
	kdc_log(context, config, 4,
		    "Failed to find key for krbtgt PAC signature");
        _kdc_audit_addreason((kdc_request_t)priv,
                             "Failed to find key for krbtgt PAC signature");
	goto out;
    }
    ret = hdb_enctype2key(context, &krbtgt_out->entry, NULL,
			  tkey_sign->key.keytype, &tkey_sign);
    if(ret) {
	kdc_log(context, config, 4,
		    "Failed to find key for krbtgt PAC signature");
        _kdc_audit_addreason((kdc_request_t)priv,
                             "Failed to find key for krbtgt PAC signature");
	goto out;
    }
    {
        krb5_data verified_cas;
        ret = krb5_ticket_get_authorization_data_type(context, ticket,
                                                      KRB5_AUTHDATA_INITIAL_VERIFIED_CAS,
                                                      &verified_cas);
        if (ret == 0) {
            krb5_data_free(&verified_cas);
            flags |= HDB_F_SYNTHETIC_OK;
        }
    }
    ret = _kdc_db_fetch(context, config, cp, HDB_F_GET_CLIENT | flags,
			NULL, &clientdb, &client);
    flags &= ~HDB_F_SYNTHETIC_OK;
    priv->client = client;
    if(ret == HDB_ERR_NOT_FOUND_HERE) {
    } else if(ret){
	const char *krbtgt_realm, *msg;
	krbtgt_realm = krb5_principal_get_realm(context, krbtgt_out->entry.principal);
	if(strcmp(krb5_principal_get_realm(context, cp), krbtgt_realm) == 0) {
	    if (ret == HDB_ERR_NOENTRY)
		ret = KRB5KDC_ERR_C_PRINCIPAL_UNKNOWN;
	    kdc_log(context, config, 4, "Client no longer in database: %s",
		    cpn);
            _kdc_audit_addreason((kdc_request_t)priv, "Client no longer in HDB");
	    goto out;
	}
	msg = krb5_get_error_message(context, ret);
	kdc_log(context, config, 4, "Client not found in database: %s", msg);
        _kdc_audit_addreason((kdc_request_t)priv, "Client does not exist");
	krb5_free_error_message(context, msg);
    } else if (ret == 0 &&
               (client->entry.flags.invalid || !client->entry.flags.client)) {
        _kdc_audit_addreason((kdc_request_t)priv, "Client has invalid bit set");
        kdc_log(context, config, 4, "Client has invalid bit set");
        ret = KRB5KDC_ERR_POLICY;
        goto out;
    }
    ret = check_PAC(context, config, cp, NULL,
		    client, server, krbtgt,
		    &tkey_check->key,
		    ekey, &tkey_sign->key,
		    tgt, &rspac, &signedpath);
    if (ret) {
	const char *msg = krb5_get_error_message(context, ret);
        _kdc_audit_addreason((kdc_request_t)priv, "PAC check failed");
	kdc_log(context, config, 4,
		"Verify PAC failed for %s (%s) from %s with %s",
		spn, cpn, from, msg);
	krb5_free_error_message(context, msg);
	goto out;
    }
    ret = check_KRB5SignedPath(context,
			       config,
			       krbtgt,
			       cp,
			       tgt,
			       &spp,
			       &signedpath);
    if (ret) {
	const char *msg = krb5_get_error_message(context, ret);
        _kdc_audit_addreason((kdc_request_t)priv, "KRB5SignedPath check failed");
	kdc_log(context, config, 4,
		"KRB5SignedPath check failed for %s (%s) from %s with %s",
		spn, cpn, from, msg);
	krb5_free_error_message(context, msg);
	goto out;
    }
    tp = cp;
    tpn = cpn;
    if (client) {
	const PA_DATA *sdata;
	int i = 0;
	sdata = _kdc_find_padata(req, &i, KRB5_PADATA_FOR_USER);
	if (sdata) {
	    struct astgs_request_desc imp_req;
	    krb5_crypto crypto;
	    krb5_data datack;
	    PA_S4U2Self self;
	    const char *str;
	    ret = decode_PA_S4U2Self(sdata->padata_value.data,
				     sdata->padata_value.length,
				     &self, NULL);
	    if (ret) {
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "Failed to decode PA-S4U2Self");
		kdc_log(context, config, 4, "Failed to decode PA-S4U2Self");
		goto out;
	    }
	    if (!krb5_checksum_is_keyed(context, self.cksum.cksumtype)) {
		free_PA_S4U2Self(&self);
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "PA-S4U2Self with unkeyed checksum");
		kdc_log(context, config, 4, "Reject PA-S4U2Self with unkeyed checksum");
		ret = KRB5KRB_AP_ERR_INAPP_CKSUM;
		goto out;
	    }
	    ret = _krb5_s4u2self_to_checksumdata(context, &self, &datack);
	    if (ret)
		goto out;
	    ret = krb5_crypto_init(context, &tgt->key, 0, &crypto);
	    if (ret) {
		const char *msg = krb5_get_error_message(context, ret);
		free_PA_S4U2Self(&self);
		krb5_data_free(&datack);
		kdc_log(context, config, 4, "krb5_crypto_init failed: %s", msg);
		krb5_free_error_message(context, msg);
		goto out;
	    }
	    if (self.cksum.cksumtype == CKSUMTYPE_HMAC_MD5) {
		struct krb5_crypto_iov iov;
		unsigned char csdata[16];
		Checksum cs;
		cs.checksum.length = sizeof(csdata);
		cs.checksum.data = &csdata;
		iov.data.data = datack.data;
		iov.data.length = datack.length;
		iov.flags = KRB5_CRYPTO_TYPE_DATA;
		ret = _krb5_HMAC_MD5_checksum(context, NULL, &crypto->key,
					      KRB5_KU_OTHER_CKSUM, &iov, 1,
					      &cs);
		if (ret == 0 &&
		    krb5_data_ct_cmp(&cs.checksum, &self.cksum.checksum) != 0)
		    ret = KRB5KRB_AP_ERR_BAD_INTEGRITY;
	    }
	    else {
		ret = krb5_verify_checksum(context,
					   crypto,
					   KRB5_KU_OTHER_CKSUM,
					   datack.data,
					   datack.length,
					   &self.cksum);
	    }
	    krb5_data_free(&datack);
	    krb5_crypto_destroy(context, crypto);
	    if (ret) {
		const char *msg = krb5_get_error_message(context, ret);
		free_PA_S4U2Self(&self);
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "S4U2Self checksum failed");
		kdc_log(context, config, 4,
			"krb5_verify_checksum failed for S4U2Self: %s", msg);
		krb5_free_error_message(context, msg);
		goto out;
	    }
	    ret = _krb5_principalname2krb5_principal(context,
						     &tp,
						     self.name,
						     self.realm);
	    free_PA_S4U2Self(&self);
	    if (ret)
		goto out;
	    ret = krb5_unparse_name(context, tp, &tpn);
	    if (ret)
		goto out;
	    ret = _kdc_db_fetch(context, config, tp, HDB_F_GET_CLIENT | flags,
				NULL, &s4u2self_impersonated_clientdb,
				&s4u2self_impersonated_client);
	    if (ret) {
		const char *msg;
		if (ret == HDB_ERR_NOENTRY)
		    ret = KRB5KDC_ERR_C_PRINCIPAL_UNKNOWN;
		msg = krb5_get_error_message(context, ret);
                _kdc_audit_addreason((kdc_request_t)priv,
                                     "S4U2Self principal to impersonate not found");
		kdc_log(context, config, 2,
			"S4U2Self principal to impersonate %s not found in database: %s",
			tpn, msg);
		krb5_free_error_message(context, msg);
		goto out;
	    }
	    s4u2self_impersonated_client->entry.flags.require_pwchange = FALSE;
	    free(s4u2self_impersonated_client->entry.pw_end);
	    s4u2self_impersonated_client->entry.pw_end = NULL;
	    imp_req = *priv;
	    imp_req.client = s4u2self_impersonated_client;
	    imp_req.client_princ = tp;
	    ret = kdc_check_flags(&imp_req, FALSE);
	    if (ret)
		goto out; 
	    if(rspac.data) {
		krb5_pac p = NULL;
		krb5_data_free(&rspac);
		ret = _kdc_pac_generate(context, s4u2self_impersonated_client, &p);
		if (ret) {
                    _kdc_audit_addreason((kdc_request_t)priv,
                                         "KRB5SignedPath missing");
		    kdc_log(context, config, 4, "PAC generation failed for -- %s",
			    tpn);
		    goto out;
		}
		if (p != NULL) {
		    ret = _krb5_pac_sign(context, p, ticket->ticket.authtime,
					 s4u2self_impersonated_client->entry.principal,
					 ekey, &tkey_sign->key,
					 &rspac);
		    krb5_pac_free(context, p);
		    if (ret) {
			kdc_log(context, config, 4, "PAC signing failed for -- %s",
				tpn);
			goto out;
		    }
		}
	    }
	    ret = check_s4u2self(context, config, clientdb, client, sp);
	    if (ret) {
		kdc_log(context, config, 4, "S4U2Self: %s is not allowed "
			"to impersonate to service "
			"(tried for user %s to service %s)",
			cpn, tpn, spn);
		goto out;
	    }
	    if (client->entry.flags.trusted_for_delegation &&
		s4u2self_impersonated_client->entry.flags.forwardable) {
		str = "[forwardable]";
	    } else {
		b->kdc_options.forwardable = 0;
		str = "";
	    }
	    kdc_log(context, config, 4, "s4u2self %s impersonating %s to "
		    "service %s %s", cpn, tpn, spn, str);
	}
    }
    if (client != NULL
	&& b->additional_tickets != NULL
	&& b->additional_tickets->len != 0
	&& b->kdc_options.cname_in_addl_tkt
	&& b->kdc_options.enc_tkt_in_skey == 0)
    {
	int ad_signedpath = 0;
	Key *clientkey;
	Ticket *t;
	if (!signedpath) {
	    ret = KRB5KDC_ERR_BADOPTION;
            _kdc_audit_addreason((kdc_request_t)priv, "KRB5SignedPath missing");
	    kdc_log(context, config, 4,
		    "Constrained delegation done on service ticket %s/%s",
		    cpn, spn);
	    goto out;
	}
	t = &b->additional_tickets->val[0];
	ret = hdb_enctype2key(context, &client->entry,
			      hdb_kvno2keys(context, &client->entry,
					    t->enc_part.kvno ? * t->enc_part.kvno : 0),
			      t->enc_part.etype, &clientkey);
	if(ret){
	    ret = KRB5KDC_ERR_ETYPE_NOSUPP; 
	    goto out;
	}
	ret = krb5_decrypt_ticket(context, t, &clientkey->key, &adtkt, 0);
	if (ret) {
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Failed to decrypt constrained delegation ticket");
	    kdc_log(context, config, 4,
		    "failed to decrypt ticket for "
		    "constrained delegation from %s to %s ", cpn, spn);
	    goto out;
	}
	ret = _krb5_principalname2krb5_principal(context,
						 &tp,
						 adtkt.cname,
						 adtkt.crealm);
	if (ret)
	    goto out;
	ret = krb5_unparse_name(context, tp, &tpn);
	if (ret)
	    goto out;
        _kdc_audit_addkv((kdc_request_t)priv, 0, "impersonatee", "%s", tpn);
	ret = _krb5_principalname2krb5_principal(context,
						 &dp,
						 t->sname,
						 t->realm);
	if (ret)
	    goto out;
	ret = krb5_unparse_name(context, dp, &dpn);
	if (ret)
	    goto out;
	if (adtkt.flags.forwardable == 0) {
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Missing forwardable flag on ticket for constrained delegation");
	    kdc_log(context, config, 4,
		    "Missing forwardable flag on ticket for "
		    "constrained delegation from %s (%s) as %s to %s ",
		    cpn, dpn, tpn, spn);
	    ret = KRB5KDC_ERR_BADOPTION;
	    goto out;
	}
	ret = check_constrained_delegation(context, config, clientdb,
					   client, server, sp);
	if (ret) {
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Constrained delegation not allowed");
	    kdc_log(context, config, 4,
		    "constrained delegation from %s (%s) as %s to %s not allowed",
		    cpn, dpn, tpn, spn);
	    goto out;
	}
	ret = verify_flags(context, config, &adtkt, tpn);
	if (ret) {
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Constrained delegation ticket expired or invalid");
	    goto out;
	}
	krb5_data_free(&rspac);
	ret = check_PAC(context, config, tp, dp,
			client, server, krbtgt,
			&clientkey->key,
			ekey, &tkey_sign->key,
			&adtkt, &rspac, &ad_signedpath);
	if (ret) {
	    const char *msg = krb5_get_error_message(context, ret);
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Constrained delegation ticket PAC check failed");
	    kdc_log(context, config, 4,
		    "Verify delegated PAC failed to %s for client"
		    "%s (%s) as %s from %s with %s",
		    spn, cpn, dpn, tpn, from, msg);
	    krb5_free_error_message(context, msg);
	    goto out;
	}
	ret = check_KRB5SignedPath(context,
				   config,
				   krbtgt,
				   cp,
				   &adtkt,
				   NULL,
				   &ad_signedpath);
	if (ret) {
	    const char *msg = krb5_get_error_message(context, ret);
	    kdc_log(context, config, 4,
		    "KRB5SignedPath check from service %s failed "
		    "for delegation to %s for client %s (%s)"
		    "from %s failed with %s",
		    spn, tpn, dpn, cpn, from, msg);
	    krb5_free_error_message(context, msg);
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "KRB5SignedPath check failed");
	    goto out;
	}
	if (!ad_signedpath) {
	    ret = KRB5KDC_ERR_BADOPTION;
	    kdc_log(context, config, 4,
		    "Ticket not signed with PAC nor SignedPath service %s failed "
		    "for delegation to %s for client %s (%s)"
		    "from %s",
		    spn, tpn, dpn, cpn, from);
            _kdc_audit_addreason((kdc_request_t)priv,
                                 "Constrained delegation ticket not signed");
	    goto out;
	}
	kdc_log(context, config, 4, "constrained delegation for %s "
		"from %s (%s) to %s", tpn, cpn, dpn, spn);
    }
    ret = kdc_check_flags(priv, FALSE);
    if(ret)
	goto out;
    if((b->kdc_options.validate || b->kdc_options.renew) &&
       !krb5_principal_compare(context,
			       krbtgt->entry.principal,
			       server->entry.principal)){
        _kdc_audit_addreason((kdc_request_t)priv, "Inconsistent request");
	kdc_log(context, config, 4, "Inconsistent request.");
	ret = KRB5KDC_ERR_SERVER_NOMATCH;
	goto out;
    }
    if (!_kdc_check_addresses(priv, tgt->caddr, from_addr)) {
        if (config->check_ticket_addresses) {
            ret = KRB5KRB_AP_ERR_BADADDR;
            _kdc_audit_addkv((kdc_request_t)priv, 0, "wrongaddr", "yes");
            kdc_log(context, config, 4, "Request from wrong address");
            _kdc_audit_addreason((kdc_request_t)priv, "Request from wrong address");
            goto out;
        } else if (config->warn_ticket_addresses) {
            _kdc_audit_addkv((kdc_request_t)priv, 0, "wrongaddr", "yes");
        }
    }
    if (is_anon_tgs_request_p(b, tgt)) {
	ret = _kdc_check_anon_policy(priv);
	if (ret)
	    goto out;
    }
    if (ref_realm) {
	PA_DATA pa;
	krb5_crypto crypto;
	kdc_log(context, config, 3,
		"Adding server referral to %s", ref_realm);
	ret = krb5_crypto_init(context, &sessionkey, 0, &crypto);
	if (ret)
	    goto out;
	ret = build_server_referral(context, config, crypto, ref_realm,
				    NULL, s, &pa.padata_value);
	krb5_crypto_destroy(context, crypto);
	if (ret) {
            _kdc_audit_addreason((kdc_request_t)priv, "Referral build failed");
	    kdc_log(context, config, 4,
		    "Failed building server referral");
	    goto out;
	}
	pa.padata_type = KRB5_PADATA_SERVER_REFERRAL;
	ret = add_METHOD_DATA(&enc_pa_data, &pa);
	krb5_data_free(&pa.padata_value);
	if (ret) {
	    kdc_log(context, config, 4,
		    "Add server referral METHOD-DATA failed");
	    goto out;
	}
    }
    ret = tgs_make_reply(priv,
			 tp,
			 tgt,
			 replykey,
			 rk_is_subkey,
			 ekey,
			 &sessionkey,
			 kvno,
			 *auth_data,
			 server,
			 rsp,
			 client,
			 cp,
                         tgt_realm,
			 krbtgt_out,
			 tkey_sign->key.keytype,
			 spp,
			 &rspac,
			 &enc_pa_data);
out:
    if (tpn != cpn)
	    free(tpn);
    free(dpn);
    free(krbtgt_out_n);
    _krb5_free_capath(context, capath);
    krb5_data_free(&rspac);
    krb5_free_keyblock_contents(context, &sessionkey);
    if(krbtgt_out)
	_kdc_free_ent(context, krbtgt_out);
    if(server)
	_kdc_free_ent(context, server);
    if(client)
	_kdc_free_ent(context, client);
    if(s4u2self_impersonated_client)
	_kdc_free_ent(context, s4u2self_impersonated_client);
    if (tp && tp != cp)
	krb5_free_principal(context, tp);
    krb5_free_principal(context, cp);
    krb5_free_principal(context, dp);
    krb5_free_principal(context, sp);
    krb5_free_principal(context, krbtgt_out_principal);
    free(ref_realm);
    free_METHOD_DATA(&enc_pa_data);
    free_EncTicketPart(&adtkt);
    return ret;
}