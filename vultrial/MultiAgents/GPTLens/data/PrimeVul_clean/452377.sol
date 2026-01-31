change_indent(
    int		type,
    int		amount,
    int		round,
    int		replaced,	
    int		call_changed_bytes)	
{
    int		vcol;
    int		last_vcol;
    int		insstart_less;		
    int		new_cursor_col;
    int		i;
    char_u	*ptr;
    int		save_p_list;
    int		start_col;
    colnr_T	vc;
    colnr_T	orig_col = 0;		
    char_u	*new_line, *orig_line = NULL;	
    if (State & VREPLACE_FLAG)
    {
	orig_line = vim_strsave(ml_get_curline());  
	orig_col = curwin->w_cursor.col;
    }
    save_p_list = curwin->w_p_list;
    curwin->w_p_list = FALSE;
    vc = getvcol_nolist(&curwin->w_cursor);
    vcol = vc;
    start_col = curwin->w_cursor.col;
    new_cursor_col = curwin->w_cursor.col;
    beginline(BL_WHITE);
    new_cursor_col -= curwin->w_cursor.col;
    insstart_less = curwin->w_cursor.col;
    if (new_cursor_col < 0)
	vcol = get_indent() - vcol;
    if (new_cursor_col > 0)	    
	start_col = -1;
    if (type == INDENT_SET)
	(void)set_indent(amount, call_changed_bytes ? SIN_CHANGED : 0);
    else
    {
	int	save_State = State;
	if (State & VREPLACE_FLAG)
	    State = INSERT;
	shift_line(type == INDENT_DEC, round, 1, call_changed_bytes);
	State = save_State;
    }
    insstart_less -= curwin->w_cursor.col;
    if (new_cursor_col >= 0)
    {
	if (new_cursor_col == 0)
	    insstart_less = MAXCOL;
	new_cursor_col += curwin->w_cursor.col;
    }
    else if (!(State & INSERT))
	new_cursor_col = curwin->w_cursor.col;
    else
    {
	vcol = get_indent() - vcol;
	curwin->w_virtcol = (colnr_T)((vcol < 0) ? 0 : vcol);
	vcol = last_vcol = 0;
	new_cursor_col = -1;
	ptr = ml_get_curline();
	while (vcol <= (int)curwin->w_virtcol)
	{
	    last_vcol = vcol;
	    if (has_mbyte && new_cursor_col >= 0)
		new_cursor_col += (*mb_ptr2len)(ptr + new_cursor_col);
	    else
		++new_cursor_col;
	    if (ptr[new_cursor_col] == NUL)
		break;
	    vcol += lbr_chartabsize(ptr, ptr + new_cursor_col, (colnr_T)vcol);
	}
	vcol = last_vcol;
	if (vcol != (int)curwin->w_virtcol)
	{
	    curwin->w_cursor.col = (colnr_T)new_cursor_col;
	    i = (int)curwin->w_virtcol - vcol;
	    ptr = alloc(i + 1);
	    if (ptr != NULL)
	    {
		new_cursor_col += i;
		ptr[i] = NUL;
		while (--i >= 0)
		    ptr[i] = ' ';
		ins_str(ptr);
		vim_free(ptr);
	    }
	}
	insstart_less = MAXCOL;
    }
    curwin->w_p_list = save_p_list;
    if (new_cursor_col <= 0)
	curwin->w_cursor.col = 0;
    else
	curwin->w_cursor.col = (colnr_T)new_cursor_col;
    curwin->w_set_curswant = TRUE;
    changed_cline_bef_curs();
    if (State & INSERT)
    {
	if (curwin->w_cursor.lnum == Insstart.lnum && Insstart.col != 0)
	{
	    if ((int)Insstart.col <= insstart_less)
		Insstart.col = 0;
	    else
		Insstart.col -= insstart_less;
	}
	if ((int)ai_col <= insstart_less)
	    ai_col = 0;
	else
	    ai_col -= insstart_less;
    }
    if (REPLACE_NORMAL(State) && start_col >= 0)
    {
	while (start_col > (int)curwin->w_cursor.col)
	{
	    replace_join(0);	    
	    --start_col;
	}
	while (start_col < (int)curwin->w_cursor.col || replaced)
	{
	    replace_push(NUL);
	    if (replaced)
	    {
		replace_push(replaced);
		replaced = NUL;
	    }
	    ++start_col;
	}
    }
    if (State & VREPLACE_FLAG)
    {
	if (orig_line == NULL)
	    return;
	new_line = vim_strsave(ml_get_curline());
	if (new_line == NULL)
	    return;
	new_line[curwin->w_cursor.col] = NUL;
	ml_replace(curwin->w_cursor.lnum, orig_line, FALSE);
	curwin->w_cursor.col = orig_col;
	backspace_until_column(0);
	ins_bytes(new_line);
	vim_free(new_line);
    }
}