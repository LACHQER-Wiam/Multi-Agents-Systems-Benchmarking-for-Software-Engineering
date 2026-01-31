search_impl(i_ctx_t *i_ctx_p, bool forward)
{
    os_ptr op = osp;
    os_ptr op1 = op - 1;
    uint size = r_size(op);
    uint count;
    byte *pat;
    byte *ptr;
    byte ch;
    int incr = forward ? 1 : -1;
    check_read_type(*op1, t_string);
    check_read_type(*op, t_string);
    if (size > r_size(op1)) {	
        make_false(op);
        return 0;
    }
    count = r_size(op1) - size;
    ptr = op1->value.bytes;
    if (size == 0)
        goto found;
    if (!forward)
        ptr += count;
    pat = op->value.bytes;
    ch = pat[0];
    do {
        if (*ptr == ch && (size == 1 || !memcmp(ptr, pat, size)))
            goto found;
        ptr += incr;
    }
    while (count--);
    make_false(op);
    return 0;
found:
    op->tas.type_attrs = op1->tas.type_attrs;
    op->value.bytes = ptr;				
    op->tas.rsize = size;				
    push(2);
    op[-1] = *op1;					
    op[-3].value.bytes = ptr + size;			
    if (forward) {
        op[-1].tas.rsize = ptr - op[-1].value.bytes;	
        op[-3].tas.rsize = count;			
    } else {
        op[-1].tas.rsize = count;			
        op[-3].tas.rsize -= count + size;		
    }
    make_true(op);
    return 0;
}