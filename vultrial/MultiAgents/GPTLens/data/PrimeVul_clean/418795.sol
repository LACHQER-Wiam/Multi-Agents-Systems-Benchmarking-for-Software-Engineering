do_mouse(
    oparg_T	*oap,		
    int		c,		
    int		dir,		
    long	count,
    int		fixindent)	
{
    static int	do_always = FALSE;	
    static int	got_click = FALSE;	
    int		which_button;	
    int		is_click = FALSE; 
    int		is_drag = FALSE;  
    int		jump_flags = 0;	
    pos_T	start_visual;
    int		moved;		
    int		in_status_line;	
    static int	in_tab_line = FALSE; 
    int		in_sep_line;	
    int		c1, c2;
#if defined(FEAT_FOLDING)
    pos_T	save_cursor;
#endif
    win_T	*old_curwin = curwin;
    static pos_T orig_cursor;
    colnr_T	leftcol, rightcol;
    pos_T	end_visual;
    int		diff;
    int		old_active = VIsual_active;
    int		old_mode = VIsual_mode;
    int		regname;
#if defined(FEAT_FOLDING)
    save_cursor = curwin->w_cursor;
#endif
    if (do_always)
	do_always = FALSE;
    else
#ifdef FEAT_GUI
	if (!gui.in_use)
#endif
	{
	    if (VIsual_active)
	    {
		if (!mouse_has(MOUSE_VISUAL))
		    return FALSE;
	    }
	    else if (State == MODE_NORMAL && !mouse_has(MOUSE_NORMAL))
		return FALSE;
	}
    for (;;)
    {
	which_button = get_mouse_button(KEY2TERMCAP1(c), &is_click, &is_drag);
	if (is_drag)
	{
	    if (!KeyStuffed && vpeekc() != NUL)
	    {
		int nc;
		int save_mouse_row = mouse_row;
		int save_mouse_col = mouse_col;
		nc = safe_vgetc();
		if (c == nc)
		    continue;
		vungetc(nc);
		mouse_row = save_mouse_row;
		mouse_col = save_mouse_col;
	    }
	}
	break;
    }
    if (c == K_MOUSEMOVE)
    {
#ifdef FEAT_BEVAL_TERM
	ui_may_remove_balloon();
	if (p_bevalterm)
	{
	    profile_setlimit(p_bdlay, &bevalexpr_due);
	    bevalexpr_due_set = TRUE;
	}
#endif
#ifdef FEAT_PROP_POPUP
	popup_handle_mouse_moved();
#endif
	return FALSE;
    }
#ifdef FEAT_MOUSESHAPE
    if (!is_drag && drag_status_line)
    {
	drag_status_line = FALSE;
	update_mouseshape(SHAPE_IDX_STATUS);
    }
    if (!is_drag && drag_sep_line)
    {
	drag_sep_line = FALSE;
	update_mouseshape(SHAPE_IDX_VSEP);
    }
#endif
    if (is_click)
	got_click = TRUE;
    else
    {
	if (!got_click)			
	    return FALSE;
	if (!is_drag)			
	{
	    got_click = FALSE;
	    if (in_tab_line)
	    {
		in_tab_line = FALSE;
		return FALSE;
	    }
	}
    }
    if (is_click && (mod_mask & MOD_MASK_CTRL) && which_button == MOUSE_RIGHT)
    {
	if (State & MODE_INSERT)
	    stuffcharReadbuff(Ctrl_O);
	if (count > 1)
	    stuffnumReadbuff(count);
	stuffcharReadbuff(Ctrl_T);
	got_click = FALSE;		
	return FALSE;
    }
    if ((mod_mask & MOD_MASK_CTRL) && which_button != MOUSE_LEFT)
	return FALSE;
    if ((mod_mask & (MOD_MASK_SHIFT | MOD_MASK_CTRL | MOD_MASK_ALT
							     | MOD_MASK_META))
	    && (!is_click
		|| (mod_mask & MOD_MASK_MULTI_CLICK)
		|| which_button == MOUSE_MIDDLE)
	    && !((mod_mask & (MOD_MASK_SHIFT|MOD_MASK_ALT))
		&& mouse_model_popup()
		&& which_button == MOUSE_LEFT)
	    && !((mod_mask & MOD_MASK_ALT)
		&& !mouse_model_popup()
		&& which_button == MOUSE_RIGHT)
	    )
	return FALSE;
    if (!is_click && which_button == MOUSE_MIDDLE)
	return FALSE;
    if (oap != NULL)
	regname = oap->regname;
    else
	regname = 0;
    if (which_button == MOUSE_MIDDLE)
    {
	if (State == MODE_NORMAL)
	{
	    if (oap != NULL && oap->op_type != OP_NOP)
	    {
		clearopbeep(oap);
		return FALSE;
	    }
	    if (VIsual_active)
	    {
		if (VIsual_select)
		{
		    stuffcharReadbuff(Ctrl_G);
		    stuffReadbuff((char_u *)"\"+p");
		}
		else
		{
		    stuffcharReadbuff('y');
		    stuffcharReadbuff(K_MIDDLEMOUSE);
		}
		do_always = TRUE;	
		return FALSE;
	    }
	}
	else if ((State & MODE_INSERT) == 0)
	    return FALSE;
	if ((State & MODE_INSERT) || !mouse_has(MOUSE_NORMAL))
	{
	    if (regname == '.')
		insert_reg(regname, TRUE);
	    else
	    {
#ifdef FEAT_CLIPBOARD
		if (clip_star.available && regname == 0)
		    regname = '*';
#endif
		if ((State & REPLACE_FLAG) && !yank_register_mline(regname))
		    insert_reg(regname, TRUE);
		else
		{
		    do_put(regname, NULL, BACKWARD, 1L,
						      fixindent | PUT_CURSEND);
		    AppendCharToRedobuff(Ctrl_R);
		    AppendCharToRedobuff(fixindent ? Ctrl_P : Ctrl_O);
		    AppendCharToRedobuff(regname == 0 ? '"' : regname);
		}
	    }
	    return FALSE;
	}
    }
    if (!is_click)
	jump_flags |= MOUSE_FOCUS | MOUSE_DID_MOVE;
    start_visual.lnum = 0;
    if (TabPageIdxs != NULL)  
    {
	if (mouse_row == 0 && firstwin->w_winrow > 0)
	{
	    if (is_drag)
	    {
		if (in_tab_line)
		{
		    c1 = TabPageIdxs[mouse_col];
		    tabpage_move(c1 <= 0 ? 9999 : c1 < tabpage_index(curtab)
								    ? c1 - 1 : c1);
		}
		return FALSE;
	    }
	    if (is_click
# ifdef FEAT_CMDWIN
		    && cmdwin_type == 0
# endif
		    && mouse_col < Columns)
	    {
		in_tab_line = TRUE;
		c1 = TabPageIdxs[mouse_col];
		if (c1 >= 0)
		{
		    if ((mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_2CLICK)
		    {
			end_visual_mode_keep_button();
			tabpage_new();
			tabpage_move(c1 == 0 ? 9999 : c1 - 1);
		    }
		    else
		    {
			goto_tabpage(c1);
			if (curwin != old_curwin)
			    end_visual_mode_keep_button();
		    }
		}
		else
		{
		    tabpage_T	*tp;
		    if (c1 == -999)
			tp = curtab;
		    else
			tp = find_tabpage(-c1);
		    if (tp == curtab)
		    {
			if (first_tabpage->tp_next != NULL)
			    tabpage_close(FALSE);
		    }
		    else if (tp != NULL)
			tabpage_close_other(tp, FALSE);
		}
	    }
	    return TRUE;
	}
	else if (is_drag && in_tab_line)
	{
	    c1 = TabPageIdxs[mouse_col];
	    tabpage_move(c1 <= 0 ? 9999 : c1 - 1);
	    return FALSE;
	}
    }
    if (mouse_model_popup())
    {
	if (which_button == MOUSE_RIGHT
			    && !(mod_mask & (MOD_MASK_SHIFT | MOD_MASK_CTRL)))
	{
#ifdef USE_POPUP_SETPOS
# ifdef FEAT_GUI
	    if (gui.in_use)
	    {
#  if defined(FEAT_GUI_MOTIF) || defined(FEAT_GUI_GTK) \
			  || defined(FEAT_GUI_PHOTON)
		if (!is_click)
		    return FALSE;
#  endif
#  if defined(FEAT_GUI_MSWIN) || defined(FEAT_GUI_HAIKU)
		if (is_click || is_drag)
		    return FALSE;
#  endif
	    }
# endif
# if defined(FEAT_GUI) && defined(FEAT_TERM_POPUP_MENU)
	    else
# endif
# if defined(FEAT_TERM_POPUP_MENU)
	    if (!is_click)
		return FALSE;
#endif
	    jump_flags = 0;
	    if (STRCMP(p_mousem, "popup_setpos") == 0)
	    {
		if (VIsual_active)
		{
		    pos_T    m_pos;
		    if (mouse_row < curwin->w_winrow
			 || mouse_row
				  > (curwin->w_winrow + curwin->w_height))
			jump_flags = MOUSE_MAY_STOP_VIS;
		    else if (get_fpos_of_mouse(&m_pos) != IN_BUFFER)
			jump_flags = MOUSE_MAY_STOP_VIS;
		    else
		    {
			if ((LT_POS(curwin->w_cursor, VIsual)
				    && (LT_POS(m_pos, curwin->w_cursor)
					|| LT_POS(VIsual, m_pos)))
				|| (LT_POS(VIsual, curwin->w_cursor)
				    && (LT_POS(m_pos, VIsual)
				      || LT_POS(curwin->w_cursor, m_pos))))
			{
			    jump_flags = MOUSE_MAY_STOP_VIS;
			}
			else if (VIsual_mode == Ctrl_V)
			{
			    getvcols(curwin, &curwin->w_cursor, &VIsual,
						     &leftcol, &rightcol);
			    getvcol(curwin, &m_pos, NULL, &m_pos.col, NULL);
			    if (m_pos.col < leftcol || m_pos.col > rightcol)
				jump_flags = MOUSE_MAY_STOP_VIS;
			}
		    }
		}
		else
		    jump_flags = MOUSE_MAY_STOP_VIS;
	    }
	    if (jump_flags)
	    {
		jump_flags = jump_to_mouse(jump_flags, NULL, which_button);
		update_curbuf(VIsual_active ? UPD_INVERTED : UPD_VALID);
		setcursor();
		out_flush();    
	    }
# ifdef FEAT_MENU
	    show_popupmenu();
	    got_click = FALSE;	
# endif
	    return (jump_flags & CURSOR_MOVED) != 0;
#else
	    return FALSE;
#endif
	}
	if (which_button == MOUSE_LEFT
				&& (mod_mask & (MOD_MASK_SHIFT|MOD_MASK_ALT)))
	{
	    which_button = MOUSE_RIGHT;
	    mod_mask &= ~MOD_MASK_SHIFT;
	}
    }
    if ((State & (MODE_NORMAL | MODE_INSERT))
			    && !(mod_mask & (MOD_MASK_SHIFT | MOD_MASK_CTRL)))
    {
	if (which_button == MOUSE_LEFT)
	{
	    if (is_click)
	    {
		if (VIsual_active)
		    jump_flags |= MOUSE_MAY_STOP_VIS;
	    }
	    else if (mouse_has(MOUSE_VISUAL))
		jump_flags |= MOUSE_MAY_VIS;
	}
	else if (which_button == MOUSE_RIGHT)
	{
	    if (is_click && VIsual_active)
	    {
		if (LT_POS(curwin->w_cursor, VIsual))
		{
		    start_visual = curwin->w_cursor;
		    end_visual = VIsual;
		}
		else
		{
		    start_visual = VIsual;
		    end_visual = curwin->w_cursor;
		}
	    }
	    jump_flags |= MOUSE_FOCUS;
	    if (mouse_has(MOUSE_VISUAL))
		jump_flags |= MOUSE_MAY_VIS;
	}
    }
    if (!is_drag && oap != NULL && oap->op_type != OP_NOP)
    {
	got_click = FALSE;
	oap->motion_type = MCHAR;
    }
    if (!is_click && !is_drag)
	jump_flags |= MOUSE_RELEASED;
    jump_flags = jump_to_mouse(jump_flags,
			oap == NULL ? NULL : &(oap->inclusive), which_button);
#ifdef FEAT_MENU
    if (jump_flags & MOUSE_WINBAR)
	return FALSE;
#endif
    moved = (jump_flags & CURSOR_MOVED);
    in_status_line = (jump_flags & IN_STATUS_LINE);
    in_sep_line = (jump_flags & IN_SEP_LINE);
#ifdef FEAT_NETBEANS_INTG
    if (isNetbeansBuffer(curbuf)
			    && !(jump_flags & (IN_STATUS_LINE | IN_SEP_LINE)))
    {
	int key = KEY2TERMCAP1(c);
	if (key == (int)KE_LEFTRELEASE || key == (int)KE_MIDDLERELEASE
					       || key == (int)KE_RIGHTRELEASE)
	    netbeans_button_release(which_button);
    }
#endif
    if (curwin != old_curwin && oap != NULL && oap->op_type != OP_NOP)
	clearop(oap);
#ifdef FEAT_FOLDING
    if (mod_mask == 0
	    && !is_drag
	    && (jump_flags & (MOUSE_FOLD_CLOSE | MOUSE_FOLD_OPEN))
	    && which_button == MOUSE_LEFT)
    {
	if (jump_flags & MOUSE_FOLD_OPEN)
	    openFold(curwin->w_cursor.lnum, 1L);
	else
	    closeFold(curwin->w_cursor.lnum, 1L);
	if (curwin == old_curwin)
	    curwin->w_cursor = save_cursor;
    }
#endif
#if defined(FEAT_CLIPBOARD) && defined(FEAT_CMDWIN)
    if ((jump_flags & IN_OTHER_WIN) && !VIsual_active && clip_star.available)
    {
	clip_modeless(which_button, is_click, is_drag);
	return FALSE;
    }
#endif
    if (VIsual_active && is_drag && get_scrolloff_value())
    {
	if (mouse_row == 0)
	    mouse_dragging = 2;
	else
	    mouse_dragging = 1;
    }
    if (is_drag && mouse_row < 0 && !in_status_line)
    {
	scroll_redraw(FALSE, 1L);
	mouse_row = 0;
    }
    if (start_visual.lnum)		
    {
       if (mod_mask & MOD_MASK_ALT)
	   VIsual_mode = Ctrl_V;
	if (VIsual_mode == Ctrl_V)
	{
	    getvcols(curwin, &start_visual, &end_visual, &leftcol, &rightcol);
	    if (curwin->w_curswant > (leftcol + rightcol) / 2)
		end_visual.col = leftcol;
	    else
		end_visual.col = rightcol;
	    if (curwin->w_cursor.lnum >=
				    (start_visual.lnum + end_visual.lnum) / 2)
		end_visual.lnum = start_visual.lnum;
	    start_visual = curwin->w_cursor;	    
	    curwin->w_cursor = end_visual;
	    coladvance(end_visual.col);
	    VIsual = curwin->w_cursor;
	    curwin->w_cursor = start_visual;	    
	}
	else
	{
	    if (LT_POS(curwin->w_cursor, start_visual))
		VIsual = end_visual;
	    else if (LT_POS(end_visual, curwin->w_cursor))
		VIsual = start_visual;
	    else
	    {
		if (end_visual.lnum == start_visual.lnum)
		{
		    if (curwin->w_cursor.col - start_visual.col >
				    end_visual.col - curwin->w_cursor.col)
			VIsual = start_visual;
		    else
			VIsual = end_visual;
		}
		else
		{
		    diff = (curwin->w_cursor.lnum - start_visual.lnum) -
				(end_visual.lnum - curwin->w_cursor.lnum);
		    if (diff > 0)		
			VIsual = start_visual;
		    else if (diff < 0)	
			VIsual = end_visual;
		    else			
		    {
			if (curwin->w_cursor.col <
					(start_visual.col + end_visual.col) / 2)
			    VIsual = end_visual;
			else
			    VIsual = start_visual;
		    }
		}
	    }
	}
    }
    else if ((State & MODE_INSERT) && VIsual_active)
	stuffcharReadbuff(Ctrl_O);
    if (which_button == MOUSE_MIDDLE)
    {
#ifdef FEAT_CLIPBOARD
	if (clip_star.available && regname == 0)
	    regname = '*';
#endif
	if (yank_register_mline(regname))
	{
	    if (mouse_past_bottom)
		dir = FORWARD;
	}
	else if (mouse_past_eol)
	    dir = FORWARD;
	if (fixindent)
	{
	    c1 = (dir == BACKWARD) ? '[' : ']';
	    c2 = 'p';
	}
	else
	{
	    c1 = (dir == FORWARD) ? 'p' : 'P';
	    c2 = NUL;
	}
	prep_redo(regname, count, NUL, c1, NUL, c2, NUL);
	if (restart_edit != 0)
	    where_paste_started = curwin->w_cursor;
	do_put(regname, NULL, dir, count, fixindent | PUT_CURSEND);
    }
#if defined(FEAT_QUICKFIX)
    else if (((mod_mask & MOD_MASK_CTRL)
		|| (mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_2CLICK)
	    && bt_quickfix(curbuf))
    {
	if (curwin->w_llist_ref == NULL)	
	    do_cmdline_cmd((char_u *)".cc");
	else					
	    do_cmdline_cmd((char_u *)".ll");
	got_click = FALSE;		
    }
#endif
    else if ((mod_mask & MOD_MASK_CTRL) || (curbuf->b_help
		     && (mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_2CLICK))
    {
	if (State & MODE_INSERT)
	    stuffcharReadbuff(Ctrl_O);
	stuffcharReadbuff(Ctrl_RSB);
	got_click = FALSE;		
    }
    else if ((mod_mask & MOD_MASK_SHIFT))
    {
	if ((State & MODE_INSERT) || (VIsual_active && VIsual_select))
	    stuffcharReadbuff(Ctrl_O);
	if (which_button == MOUSE_LEFT)
	    stuffcharReadbuff('*');
	else	
	    stuffcharReadbuff('#');
    }
    else if (in_status_line)
    {
#ifdef FEAT_MOUSESHAPE
	if ((is_drag || is_click) && !drag_status_line)
	{
	    drag_status_line = TRUE;
	    update_mouseshape(-1);
	}
#endif
    }
    else if (in_sep_line)
    {
#ifdef FEAT_MOUSESHAPE
	if ((is_drag || is_click) && !drag_sep_line)
	{
	    drag_sep_line = TRUE;
	    update_mouseshape(-1);
	}
#endif
    }
    else if ((mod_mask & MOD_MASK_MULTI_CLICK)
				       && (State & (MODE_NORMAL | MODE_INSERT))
	     && mouse_has(MOUSE_VISUAL))
    {
	if (is_click || !VIsual_active)
	{
	    if (VIsual_active)
		orig_cursor = VIsual;
	    else
	    {
		check_visual_highlight();
		VIsual = curwin->w_cursor;
		orig_cursor = VIsual;
		VIsual_active = TRUE;
		VIsual_reselect = TRUE;
		may_start_select('o');
		setmouse();
	    }
	    if ((mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_2CLICK)
	    {
		if (mod_mask & MOD_MASK_ALT)
		    VIsual_mode = Ctrl_V;
		else
		    VIsual_mode = 'v';
	    }
	    else if ((mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_3CLICK)
		VIsual_mode = 'V';
	    else if ((mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_4CLICK)
		VIsual_mode = Ctrl_V;
#ifdef FEAT_CLIPBOARD
	    clip_star.vmode = NUL;
#endif
	}
	if ((mod_mask & MOD_MASK_MULTI_CLICK) == MOD_MASK_2CLICK)
	{
	    pos_T	*pos = NULL;
	    int		gc;
	    if (is_click)
	    {
		end_visual = curwin->w_cursor;
		while (gc = gchar_pos(&end_visual), VIM_ISWHITE(gc))
		    inc(&end_visual);
		if (oap != NULL)
		    oap->motion_type = MCHAR;
		if (oap != NULL
			&& VIsual_mode == 'v'
			&& !vim_iswordc(gchar_pos(&end_visual))
			&& EQUAL_POS(curwin->w_cursor, VIsual)
			&& (pos = findmatch(oap, NUL)) != NULL)
		{
		    curwin->w_cursor = *pos;
		    if (oap->motion_type == MLINE)
			VIsual_mode = 'V';
		    else if (*p_sel == 'e')
		    {
			if (LT_POS(curwin->w_cursor, VIsual))
			    ++VIsual.col;
			else
			    ++curwin->w_cursor.col;
		    }
		}
	    }
	    if (pos == NULL && (is_click || is_drag))
	    {
		if (LT_POS(curwin->w_cursor, orig_cursor))
		{
		    find_start_of_word(&curwin->w_cursor);
		    find_end_of_word(&VIsual);
		}
		else
		{
		    find_start_of_word(&VIsual);
		    if (*p_sel == 'e' && *ml_get_cursor() != NUL)
			curwin->w_cursor.col +=
					 (*mb_ptr2len)(ml_get_cursor());
		    find_end_of_word(&curwin->w_cursor);
		}
	    }
	    curwin->w_set_curswant = TRUE;
	}
	if (is_click)
	    redraw_curbuf_later(UPD_INVERTED);	
    }
    else if (VIsual_active && !old_active)
    {
	if (mod_mask & MOD_MASK_ALT)
	    VIsual_mode = Ctrl_V;
	else
	    VIsual_mode = 'v';
    }
    if ((!VIsual_active && old_active && mode_displayed)
	    || (VIsual_active && p_smd && msg_silent == 0
				 && (!old_active || VIsual_mode != old_mode)))
	redraw_cmdline = TRUE;
    return moved;
}