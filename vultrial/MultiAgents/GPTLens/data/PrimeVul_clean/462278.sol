static pj_status_t decode_errcode_attr(pj_pool_t *pool, 
				       const pj_uint8_t *buf,
				       const pj_stun_msg_hdr *msghdr, 
				       void **p_attr)
{
    pj_stun_errcode_attr *attr;
    pj_str_t value;
    PJ_UNUSED_ARG(msghdr);
    attr = PJ_POOL_ZALLOC_T(pool, pj_stun_errcode_attr);
    GETATTRHDR(buf, &attr->hdr);
    attr->err_code = buf[6] * 100 + buf[7];
    value.ptr = ((char*)buf + ATTR_HDR_LEN + 4);
    value.slen = attr->hdr.length - 4;
    if (value.slen < 0)
    	value.slen = 0;
    pj_strdup(pool, &attr->reason, &value);
    *p_attr = attr;
    return PJ_SUCCESS;
}