update_topline(void)
{
    long	line_count;
    int		halfheight;
    int		n;
    linenr_T	old_topline;
#ifdef FEAT_DIFF
    int		old_topfill;
#endif
#ifdef FEAT_FOLDING
    linenr_T	lnum;
#endif
    int		check_topline = FALSE;
    int		check_botline = FALSE;
    long        *so_ptr = curwin->w_p_so >= 0 ? &curwin->w_p_so : &p_so;
    int		save_so = *so_ptr;
    if (!screen_valid(TRUE) || curwin->w_height == 0)
    {
	check_cursor_lnum();
	curwin->w_topline = curwin->w_cursor.lnum;
	curwin->w_botline = curwin->w_topline;
	curwin->w_scbind_pos = 1;
	return;
    }
    check_cursor_moved(curwin);
    if (curwin->w_valid & VALID_TOPLINE)
	return;
    if (mouse_dragging > 0)
	*so_ptr = mouse_dragging - 1;
    old_topline = curwin->w_topline;
#ifdef FEAT_DIFF
    old_topfill = curwin->w_topfill;
#endif
    if (BUFEMPTY())		
    {
	if (curwin->w_topline != 1)
	    redraw_later(NOT_VALID);
	curwin->w_topline = 1;
	curwin->w_botline = 2;
	curwin->w_valid |= VALID_BOTLINE|VALID_BOTLINE_AP;
	curwin->w_scbind_pos = 1;
    }
    else
    {
	if (curwin->w_topline > 1)
	{
	    if (curwin->w_cursor.lnum < curwin->w_topline)
		check_topline = TRUE;
	    else if (check_top_offset())
		check_topline = TRUE;
	}
#ifdef FEAT_DIFF
	if (!check_topline && curwin->w_topfill > diff_check_fill(curwin,
							   curwin->w_topline))
	    check_topline = TRUE;
#endif
	if (check_topline)
	{
	    halfheight = curwin->w_height / 2 - 1;
	    if (halfheight < 2)
		halfheight = 2;
#ifdef FEAT_FOLDING
	    if (hasAnyFolding(curwin))
	    {
		n = 0;
		for (lnum = curwin->w_cursor.lnum;
				    lnum < curwin->w_topline + *so_ptr; ++lnum)
		{
		    ++n;
		    if (lnum >= curbuf->b_ml.ml_line_count || n >= halfheight)
			break;
		    (void)hasFolding(lnum, NULL, &lnum);
		}
	    }
	    else
#endif
		n = curwin->w_topline + *so_ptr - curwin->w_cursor.lnum;
	    if (n >= halfheight)
		scroll_cursor_halfway(FALSE);
	    else
	    {
		scroll_cursor_top(scrolljump_value(), FALSE);
		check_botline = TRUE;
	    }
	}
	else
	{
#ifdef FEAT_FOLDING
	    (void)hasFolding(curwin->w_topline, &curwin->w_topline, NULL);
#endif
	    check_botline = TRUE;
	}
    }
    if (check_botline)
    {
	if (!(curwin->w_valid & VALID_BOTLINE_AP))
	    validate_botline();
	if (curwin->w_botline <= curbuf->b_ml.ml_line_count)
	{
	    if (curwin->w_cursor.lnum < curwin->w_botline)
	    {
	      if (((long)curwin->w_cursor.lnum
					     >= (long)curwin->w_botline - *so_ptr
#ifdef FEAT_FOLDING
			|| hasAnyFolding(curwin)
#endif
			))
	      {
		lineoff_T	loff;
		n = curwin->w_empty_rows;
		loff.lnum = curwin->w_cursor.lnum;
#ifdef FEAT_FOLDING
		(void)hasFolding(loff.lnum, NULL, &loff.lnum);
#endif
#ifdef FEAT_DIFF
		loff.fill = 0;
		n += curwin->w_filler_rows;
#endif
		loff.height = 0;
		while (loff.lnum < curwin->w_botline
#ifdef FEAT_DIFF
			&& (loff.lnum + 1 < curwin->w_botline || loff.fill == 0)
#endif
			)
		{
		    n += loff.height;
		    if (n >= *so_ptr)
			break;
		    botline_forw(&loff);
		}
		if (n >= *so_ptr)
		    check_botline = FALSE;
	      }
	      else
		  check_botline = FALSE;
	    }
	    if (check_botline)
	    {
#ifdef FEAT_FOLDING
		if (hasAnyFolding(curwin))
		{
		    line_count = 0;
		    for (lnum = curwin->w_cursor.lnum;
				   lnum >= curwin->w_botline - *so_ptr; --lnum)
		    {
			++line_count;
			if (lnum <= 0 || line_count > curwin->w_height + 1)
			    break;
			(void)hasFolding(lnum, &lnum, NULL);
		    }
		}
		else
#endif
		    line_count = curwin->w_cursor.lnum - curwin->w_botline
								   + 1 + *so_ptr;
		if (line_count <= curwin->w_height + 1)
		    scroll_cursor_bot(scrolljump_value(), FALSE);
		else
		    scroll_cursor_halfway(FALSE);
	    }
	}
    }
    curwin->w_valid |= VALID_TOPLINE;
    if (curwin->w_topline != old_topline
#ifdef FEAT_DIFF
	    || curwin->w_topfill != old_topfill
#endif
	    )
    {
	dollar_vcol = -1;
	if (curwin->w_skipcol != 0)
	{
	    curwin->w_skipcol = 0;
	    redraw_later(NOT_VALID);
	}
	else
	    redraw_later(VALID);
	if (curwin->w_cursor.lnum == curwin->w_topline)
	    validate_cursor();
    }
    *so_ptr = save_so;
}