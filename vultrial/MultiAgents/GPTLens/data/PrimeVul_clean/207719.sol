display_dollar(colnr_T col)
{
    colnr_T save_col;
    if (!redrawing())
	return;
    cursor_off();
    save_col = curwin->w_cursor.col;
    curwin->w_cursor.col = col;
    if (has_mbyte)
    {
	char_u *p;
	p = ml_get_curline();
	curwin->w_cursor.col -= (*mb_head_off)(p, p + col);
    }
    curs_columns(FALSE);	    
    if (curwin->w_wcol < curwin->w_width)
    {
	edit_putchar('$', FALSE);
	dollar_vcol = curwin->w_virtcol;
    }
    curwin->w_cursor.col = save_col;
}