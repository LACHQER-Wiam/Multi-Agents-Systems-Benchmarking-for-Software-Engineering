ex_copy(linenr_T line1, linenr_T line2, linenr_T n)
{
    linenr_T	count;
    char_u	*p;
    count = line2 - line1 + 1;
    if ((cmdmod.cmod_flags & CMOD_LOCKMARKS) == 0)
    {
	curbuf->b_op_start.lnum = n + 1;
	curbuf->b_op_end.lnum = n + count;
	curbuf->b_op_start.col = curbuf->b_op_end.col = 0;
    }
    if (u_save(n, n + 1) == FAIL)
	return;
    curwin->w_cursor.lnum = n;
    while (line1 <= line2)
    {
	p = vim_strsave(ml_get(line1));
	if (p != NULL)
	{
	    ml_append(curwin->w_cursor.lnum, p, (colnr_T)0, FALSE);
	    vim_free(p);
	}
	if (line1 == n)
	    line1 = curwin->w_cursor.lnum;
	++line1;
	if (curwin->w_cursor.lnum < line1)
	    ++line1;
	if (curwin->w_cursor.lnum < line2)
	    ++line2;
	++curwin->w_cursor.lnum;
    }
    appended_lines_mark(n, count);
    if (VIsual_active)
	check_pos(curbuf, &VIsual);
    msgmore((long)count);
}