qf_fill_buffer(qf_list_T *qfl, buf_T *buf, qfline_T *old_last, int qf_winid)
{
    linenr_T	lnum;
    qfline_T	*qfp;
    int		old_KeyTyped = KeyTyped;
    list_T	*qftf_list = NULL;
    listitem_T	*qftf_li = NULL;
    if (old_last == NULL)
    {
	if (buf != curbuf)
	{
	    internal_error("qf_fill_buffer()");
	    return;
	}
	while ((curbuf->b_ml.ml_flags & ML_EMPTY) == 0)
	    (void)ml_delete((linenr_T)1);
    }
    if (qfl != NULL && qfl->qf_start != NULL)
    {
	char_u		dirname[MAXPATHL];
	int		invalid_val = FALSE;
	int		prev_bufnr = -1;
	*dirname = NUL;
	if (old_last == NULL)
	{
	    qfp = qfl->qf_start;
	    lnum = 0;
	}
	else
	{
	    if (old_last->qf_next != NULL)
		qfp = old_last->qf_next;
	    else
		qfp = old_last;
	    lnum = buf->b_ml.ml_line_count;
	}
	qftf_list = call_qftf_func(qfl, qf_winid, (long)(lnum + 1),
							(long)qfl->qf_count);
	if (qftf_list != NULL)
	    qftf_li = qftf_list->lv_first;
	while (lnum < qfl->qf_count)
	{
	    char_u	*qftf_str = NULL;
	    if (qftf_li != NULL && !invalid_val)
	    {
		qftf_str = tv_get_string_chk(&qftf_li->li_tv);
		if (qftf_str == NULL)
		    invalid_val = TRUE;
	    }
	    if (qf_buf_add_line(buf, lnum, qfp, dirname,
			prev_bufnr != qfp->qf_fnum, qftf_str) == FAIL)
		break;
	    prev_bufnr = qfp->qf_fnum;
	    ++lnum;
	    qfp = qfp->qf_next;
	    if (qfp == NULL)
		break;
	    if (qftf_li != NULL)
		qftf_li = qftf_li->li_next;
	}
	if (old_last == NULL)
	    (void)ml_delete(lnum + 1);
    }
    check_lnums(TRUE);
    if (old_last == NULL)
    {
	++curbuf_lock;
	set_option_value_give_err((char_u *)"ft",
						0L, (char_u *)"qf", OPT_LOCAL);
	curbuf->b_p_ma = FALSE;
	keep_filetype = TRUE;		
	apply_autocmds(EVENT_BUFREADPOST, (char_u *)"quickfix", NULL,
							       FALSE, curbuf);
	apply_autocmds(EVENT_BUFWINENTER, (char_u *)"quickfix", NULL,
							       FALSE, curbuf);
	keep_filetype = FALSE;
	--curbuf_lock;
	redraw_curbuf_later(UPD_NOT_VALID);
    }
    KeyTyped = old_KeyTyped;
}