getcmdline_int(
    int		firstc,
    long	count UNUSED,	
    int		indent,		
    int		clear_ccline)	
{
    static int	depth = 0;	    
    int		c;
    int		i;
    int		j;
    int		gotesc = FALSE;		
    int		do_abbr;		
    char_u	*lookfor = NULL;	
    int		hiscnt;			
    int		histype;		
#ifdef FEAT_SEARCH_EXTRA
    incsearch_state_T	is_state;
#endif
    int		did_wild_list = FALSE;	
    int		wim_index = 0;		
    int		res;
    int		save_msg_scroll = msg_scroll;
    int		save_State = State;	
    int		some_key_typed = FALSE;	
    int		ignore_drag_release = TRUE;
#ifdef FEAT_EVAL
    int		break_ctrl_c = FALSE;
#endif
    expand_T	xpc;
    long	*b_im_ptr = NULL;
    cmdline_info_T save_ccline;
    int		did_save_ccline = FALSE;
    int		cmdline_type;
    int		wild_type;
    ++depth;
    if (ccline.cmdbuff != NULL)
    {
	save_cmdline(&save_ccline);
	did_save_ccline = TRUE;
    }
    if (clear_ccline)
	CLEAR_FIELD(ccline);
#ifdef FEAT_EVAL
    if (firstc == -1)
    {
	firstc = NUL;
	break_ctrl_c = TRUE;
    }
#endif
#ifdef FEAT_RIGHTLEFT
    if (firstc == ':' || firstc == '=' || firstc == '>')
	cmd_hkmap = 0;
#endif
#ifdef FEAT_SEARCH_EXTRA
    init_incsearch_state(&is_state);
#endif
    if (init_ccline(firstc, indent) != OK)
	goto theend;	
    if (depth == 50)
    {
	emsg(_(e_command_too_recursive));
	goto theend;
    }
    ExpandInit(&xpc);
    ccline.xpc = &xpc;
#ifdef FEAT_RIGHTLEFT
    if (curwin->w_p_rl && *curwin->w_p_rlc == 's'
					  && (firstc == '/' || firstc == '?'))
	cmdmsg_rl = TRUE;
    else
	cmdmsg_rl = FALSE;
#endif
    redir_off = TRUE;		
    if (!cmd_silent)
    {
	i = msg_scrolled;
	msg_scrolled = 0;		
	gotocmdline(TRUE);
	msg_scrolled += i;
	redrawcmdprompt();		
	set_cmdspos();
    }
    xpc.xp_context = EXPAND_NOTHING;
    xpc.xp_backslash = XP_BS_NONE;
#ifndef BACKSLASH_IN_FILENAME
    xpc.xp_shell = FALSE;
#endif
#if defined(FEAT_EVAL)
    if (ccline.input_fn)
    {
	xpc.xp_context = ccline.xp_context;
	xpc.xp_pattern = ccline.cmdbuff;
	xpc.xp_arg = ccline.xp_arg;
    }
#endif
    msg_scroll = FALSE;
    State = MODE_CMDLINE;
    if (firstc == '/' || firstc == '?' || firstc == '@')
    {
	if (curbuf->b_p_imsearch == B_IMODE_USE_INSERT)
	    b_im_ptr = &curbuf->b_p_iminsert;
	else
	    b_im_ptr = &curbuf->b_p_imsearch;
	if (*b_im_ptr == B_IMODE_LMAP)
	    State |= MODE_LANGMAP;
#ifdef HAVE_INPUT_METHOD
	im_set_active(*b_im_ptr == B_IMODE_IM);
#endif
    }
#ifdef HAVE_INPUT_METHOD
    else if (p_imcmdline)
	im_set_active(TRUE);
#endif
    setmouse();
#ifdef CURSOR_SHAPE
    ui_cursor_shape();		
#endif
    settmode(TMODE_RAW);
    cmdline_type = firstc == NUL ? '-' : firstc;
    trigger_cmd_autocmd(cmdline_type, EVENT_CMDLINEENTER);
#ifdef FEAT_EVAL
    if (!debug_mode)
	may_trigger_modechanged();
#endif
    init_history();
    hiscnt = get_hislen();	
    histype = hist_char2type(firstc);
#ifdef FEAT_DIGRAPHS
    do_digraph(-1);		
#endif
    if (did_emsg)
	redrawcmd();
#ifdef FEAT_STL_OPT
    if (!cmd_silent && msg_scrolled == 0)
    {
	int	found_one = FALSE;
	win_T	*wp;
	FOR_ALL_WINDOWS(wp)
	    if (*p_stl != NUL || *wp->w_p_stl != NUL)
	    {
		wp->w_redr_status = TRUE;
		found_one = TRUE;
	    }
	if (*p_tal != NUL)
	{
	    redraw_tabline = TRUE;
	    found_one = TRUE;
	}
	if (found_one)
	    redraw_statuslines();
    }
#endif
    did_emsg = FALSE;
    got_int = FALSE;
    for (;;)
    {
	int trigger_cmdlinechanged = TRUE;
	int end_wildmenu;
	redir_off = TRUE;	
#ifdef USE_ON_FLY_SCROLL
	dont_scroll = FALSE;	
#endif
	quit_more = FALSE;	
	did_emsg = FALSE;	
	may_trigger_safestate(xpc.xp_numfiles <= 0);
	do
	{
	    cursorcmd();		
	    c = safe_vgetc();
	} while (c == K_IGNORE || c == K_NOP);
	if (c == K_COMMAND || c == K_SCRIPT_COMMAND)
	{
	    int	    clen = ccline.cmdlen;
	    if (do_cmdkey_command(c, DOCMD_NOWAIT) == OK)
	    {
		if (clen == ccline.cmdlen)
		    trigger_cmdlinechanged = FALSE;
		goto cmdline_changed;
	    }
	}
	if (KeyTyped)
	{
	    some_key_typed = TRUE;
#ifdef FEAT_RIGHTLEFT
	    if (cmd_hkmap)
		c = hkmap(c);
	    if (cmdmsg_rl && !KeyStuffed)
	    {
		switch (c)
		{
		    case K_RIGHT:   c = K_LEFT; break;
		    case K_S_RIGHT: c = K_S_LEFT; break;
		    case K_C_RIGHT: c = K_C_LEFT; break;
		    case K_LEFT:    c = K_RIGHT; break;
		    case K_S_LEFT:  c = K_S_RIGHT; break;
		    case K_C_LEFT:  c = K_C_RIGHT; break;
		}
	    }
#endif
	}
	if ((c == Ctrl_C
#ifdef UNIX
		|| c == intr_char
#endif
				)
#if defined(FEAT_EVAL) || defined(FEAT_CRYPT)
		&& firstc != '@'
#endif
#ifdef FEAT_EVAL
		&& (!break_ctrl_c || exmode_active)
#endif
		&& !global_busy)
	    got_int = FALSE;
	if (lookfor != NULL
		&& c != K_S_DOWN && c != K_S_UP
		&& c != K_DOWN && c != K_UP
		&& c != K_PAGEDOWN && c != K_PAGEUP
		&& c != K_KPAGEDOWN && c != K_KPAGEUP
		&& c != K_LEFT && c != K_RIGHT
		&& (xpc.xp_numfiles > 0 || (c != Ctrl_P && c != Ctrl_N)))
	    VIM_CLEAR(lookfor);
	if (c != p_wc && c == K_S_TAB && xpc.xp_numfiles > 0)
	    c = Ctrl_P;
	if (p_wmnu)
	    c = wildmenu_translate_key(&ccline, c, &xpc, did_wild_list);
	if (cmdline_pum_active())
	{
	    if (c == Ctrl_E || c == Ctrl_Y)
	    {
		wild_type = (c == Ctrl_E) ? WILD_CANCEL : WILD_APPLY;
		if (nextwild(&xpc, wild_type, WILD_NO_BEEP,
							firstc != '@') == FAIL)
		    break;
		c = Ctrl_E;
	    }
	}
	end_wildmenu = (!(c == p_wc && KeyTyped) && c != p_wcm
		&& c != Ctrl_N && c != Ctrl_P && c != Ctrl_A && c != Ctrl_L);
	end_wildmenu = end_wildmenu && (!cmdline_pum_active() ||
			    (c != K_PAGEDOWN && c != K_PAGEUP
			     && c != K_KPAGEDOWN && c != K_KPAGEUP));
	if (end_wildmenu)
	{
	    if (cmdline_pum_active())
		cmdline_pum_remove();
	    if (xpc.xp_numfiles != -1)
		(void)ExpandOne(&xpc, NULL, NULL, 0, WILD_FREE);
	    did_wild_list = FALSE;
	    if (!p_wmnu || (c != K_UP && c != K_DOWN))
		xpc.xp_context = EXPAND_NOTHING;
	    wim_index = 0;
	    wildmenu_cleanup(&ccline);
	}
	if (p_wmnu)
	    c = wildmenu_process_key(&ccline, c, &xpc);
	if (c == Ctrl_BSL)
	{
	    res = cmdline_handle_backslash_key(c, &gotesc);
	    if (res == CMDLINE_CHANGED)
		goto cmdline_changed;
	    else if (res == CMDLINE_NOT_CHANGED)
		goto cmdline_not_changed;
	    else if (res == GOTO_NORMAL_MODE)
		goto returncmd;		
	    c = Ctrl_BSL;		
	}
#ifdef FEAT_CMDWIN
	if (c == cedit_key || c == K_CMDWIN)
	{
	    if ((c == K_CMDWIN || ex_normal_busy == 0) && got_int == FALSE)
	    {
		c = open_cmdwin();
		some_key_typed = TRUE;
	    }
	}
# ifdef FEAT_DIGRAPHS
	else
# endif
#endif
#ifdef FEAT_DIGRAPHS
	    c = do_digraph(c);
#endif
	if (c == '\n' || c == '\r' || c == K_KENTER || (c == ESC
			&& (!KeyTyped || vim_strchr(p_cpo, CPO_ESC) != NULL)))
	{
	    if (exmode_active
		    && c != ESC
		    && ccline.cmdpos == ccline.cmdlen
		    && ccline.cmdpos > 0
		    && ccline.cmdbuff[ccline.cmdpos - 1] == '\\')
	    {
		if (c == K_KENTER)
		    c = '\n';
	    }
	    else
	    {
		gotesc = FALSE;	
		if (ccheck_abbr(c + ABBR_OFF))
		    goto cmdline_changed;
		if (!cmd_silent)
		{
		    windgoto(msg_row, 0);
		    out_flush();
		}
		break;
	    }
	}
	if ((c == p_wc && !gotesc && KeyTyped) || c == p_wcm)
	{
	    res = cmdline_wildchar_complete(c, firstc != '@', &did_wild_list,
		    &wim_index, &xpc, &gotesc);
	    if (res == CMDLINE_CHANGED)
		goto cmdline_changed;
	}
	gotesc = FALSE;
	if (c == K_S_TAB && KeyTyped)
	{
	    if (nextwild(&xpc, WILD_EXPAND_KEEP, 0, firstc != '@') == OK)
	    {
		if (xpc.xp_numfiles > 1
		    && ((!did_wild_list && (wim_flags[wim_index] & WIM_LIST))
			    || p_wmnu))
		{
		    showmatches(&xpc, p_wmnu
			    && ((wim_flags[wim_index] & WIM_LIST) == 0));
		}
		if (nextwild(&xpc, WILD_PREV, 0, firstc != '@') == OK
			&& nextwild(&xpc, WILD_PREV, 0, firstc != '@') == OK)
		    goto cmdline_changed;
	    }
	}
	if (c == NUL || c == K_ZERO)	    
	    c = NL;
	do_abbr = TRUE;		
	switch (c)
	{
	case K_BS:
	case Ctrl_H:
	case K_DEL:
	case K_KDEL:
	case Ctrl_W:
	    res = cmdline_erase_chars(c, indent
#ifdef FEAT_SEARCH_EXTRA
		    , &is_state
#endif
		    );
	    if (res == CMDLINE_NOT_CHANGED)
		goto cmdline_not_changed;
	    else if (res == GOTO_NORMAL_MODE)
		goto returncmd;		
	    goto cmdline_changed;
	case K_INS:
	case K_KINS:
		ccline.overstrike = !ccline.overstrike;
#ifdef CURSOR_SHAPE
		ui_cursor_shape();	
#endif
		goto cmdline_not_changed;
	case Ctrl_HAT:
		cmdline_toggle_langmap(b_im_ptr);
		goto cmdline_not_changed;
	case Ctrl_U:
		j = ccline.cmdpos;
		ccline.cmdlen -= j;
		i = ccline.cmdpos = 0;
		while (i < ccline.cmdlen)
		    ccline.cmdbuff[i++] = ccline.cmdbuff[j++];
		ccline.cmdbuff[ccline.cmdlen] = NUL;
#ifdef FEAT_SEARCH_EXTRA
		if (ccline.cmdlen == 0)
		    is_state.search_start = is_state.save_cursor;
#endif
		redrawcmd();
		goto cmdline_changed;
#ifdef FEAT_CLIPBOARD
	case Ctrl_Y:
		if (clip_star.state != SELECT_CLEARED)
		{
		    if (clip_star.state == SELECT_DONE)
			clip_copy_modeless_selection(TRUE);
		    goto cmdline_not_changed;
		}
		break;
#endif
	case ESC:	
	case Ctrl_C:
		if (exmode_active
			       && (ex_normal_busy == 0 || typebuf.tb_len > 0))
		    goto cmdline_not_changed;
		gotesc = TRUE;		
		goto returncmd;		
	case Ctrl_R:			
		res = cmdline_insert_reg(&gotesc);
		if (res == CMDLINE_NOT_CHANGED)
		    goto cmdline_not_changed;
		else if (res == GOTO_NORMAL_MODE)
		    goto returncmd;
		goto cmdline_changed;
	case Ctrl_D:
		if (showmatches(&xpc, FALSE) == EXPAND_NOTHING)
		    break;	
		redrawcmd();
		continue;	
	case K_RIGHT:
	case K_S_RIGHT:
	case K_C_RIGHT:
		do
		{
		    if (ccline.cmdpos >= ccline.cmdlen)
			break;
		    i = cmdline_charsize(ccline.cmdpos);
		    if (KeyTyped && ccline.cmdspos + i >= Columns * Rows)
			break;
		    ccline.cmdspos += i;
		    if (has_mbyte)
			ccline.cmdpos += (*mb_ptr2len)(ccline.cmdbuff
							     + ccline.cmdpos);
		    else
			++ccline.cmdpos;
		}
		while ((c == K_S_RIGHT || c == K_C_RIGHT
			       || (mod_mask & (MOD_MASK_SHIFT|MOD_MASK_CTRL)))
			&& ccline.cmdbuff[ccline.cmdpos] != ' ');
		if (has_mbyte)
		    set_cmdspos_cursor();
		goto cmdline_not_changed;
	case K_LEFT:
	case K_S_LEFT:
	case K_C_LEFT:
		if (ccline.cmdpos == 0)
		    goto cmdline_not_changed;
		do
		{
		    --ccline.cmdpos;
		    if (has_mbyte)	
			ccline.cmdpos -= (*mb_head_off)(ccline.cmdbuff,
					      ccline.cmdbuff + ccline.cmdpos);
		    ccline.cmdspos -= cmdline_charsize(ccline.cmdpos);
		}
		while (ccline.cmdpos > 0
			&& (c == K_S_LEFT || c == K_C_LEFT
			       || (mod_mask & (MOD_MASK_SHIFT|MOD_MASK_CTRL)))
			&& ccline.cmdbuff[ccline.cmdpos - 1] != ' ');
		if (has_mbyte)
		    set_cmdspos_cursor();
		goto cmdline_not_changed;
	case K_IGNORE:
		goto cmdline_not_changed;
#ifdef FEAT_GUI_MSWIN
	case K_F4:
	    if (mod_mask == MOD_MASK_ALT)
	    {
		redrawcmd();	    
		goto cmdline_not_changed;
	    }
	    break;
#endif
	case K_MIDDLEDRAG:
	case K_MIDDLERELEASE:
		goto cmdline_not_changed;	
	case K_MIDDLEMOUSE:
# ifdef FEAT_GUI
		if (!gui.in_use)
# endif
		    if (!mouse_has(MOUSE_COMMAND))
			goto cmdline_not_changed;   
# ifdef FEAT_CLIPBOARD
		if (clip_star.available)
		    cmdline_paste('*', TRUE, TRUE);
		else
# endif
		    cmdline_paste(0, TRUE, TRUE);
		redrawcmd();
		goto cmdline_changed;
# ifdef FEAT_DND
	case K_DROP:
		cmdline_paste('~', TRUE, FALSE);
		redrawcmd();
		goto cmdline_changed;
# endif
	case K_LEFTDRAG:
	case K_LEFTRELEASE:
	case K_RIGHTDRAG:
	case K_RIGHTRELEASE:
		if (ignore_drag_release)
		    goto cmdline_not_changed;
	case K_LEFTMOUSE:
	case K_RIGHTMOUSE:
		cmdline_left_right_mouse(c, &ignore_drag_release);
		goto cmdline_not_changed;
	case K_MOUSEDOWN:
	case K_MOUSEUP:
	case K_MOUSELEFT:
	case K_MOUSERIGHT:
	case K_X1MOUSE:
	case K_X1DRAG:
	case K_X1RELEASE:
	case K_X2MOUSE:
	case K_X2DRAG:
	case K_X2RELEASE:
	case K_MOUSEMOVE:
		goto cmdline_not_changed;
#ifdef FEAT_GUI
	case K_LEFTMOUSE_NM:	
	case K_LEFTRELEASE_NM:
		goto cmdline_not_changed;
	case K_VER_SCROLLBAR:
		if (msg_scrolled == 0)
		{
		    gui_do_scroll();
		    redrawcmd();
		}
		goto cmdline_not_changed;
	case K_HOR_SCROLLBAR:
		if (msg_scrolled == 0)
		{
		    gui_do_horiz_scroll(scrollbar_value, FALSE);
		    redrawcmd();
		}
		goto cmdline_not_changed;
#endif
#ifdef FEAT_GUI_TABLINE
	case K_TABLINE:
	case K_TABMENU:
		if (gui_use_tabline())
		    gui_mch_set_curtab(tabpage_index(curtab));
		goto cmdline_not_changed;
#endif
	case K_SELECT:	    
		goto cmdline_not_changed;
	case Ctrl_B:	    
	case K_HOME:
	case K_KHOME:
	case K_S_HOME:
	case K_C_HOME:
		ccline.cmdpos = 0;
		set_cmdspos();
		goto cmdline_not_changed;
	case Ctrl_E:	    
	case K_END:
	case K_KEND:
	case K_S_END:
	case K_C_END:
		ccline.cmdpos = ccline.cmdlen;
		set_cmdspos_cursor();
		goto cmdline_not_changed;
	case Ctrl_A:	    
		if (cmdline_pum_active())
		    cmdline_pum_cleanup(&ccline);
		if (nextwild(&xpc, WILD_ALL, 0, firstc != '@') == FAIL)
		    break;
		xpc.xp_context = EXPAND_NOTHING;
		did_wild_list = FALSE;
		goto cmdline_changed;
	case Ctrl_L:
#ifdef FEAT_SEARCH_EXTRA
		if (may_add_char_to_search(firstc, &c, &is_state) == OK)
		    goto cmdline_not_changed;
#endif
		if (nextwild(&xpc, WILD_LONGEST, 0, firstc != '@') == FAIL)
		    break;
		goto cmdline_changed;
	case Ctrl_N:	    
	case Ctrl_P:	    
		if (xpc.xp_numfiles > 0)
		{
		    wild_type = (c == Ctrl_P) ? WILD_PREV : WILD_NEXT;
		    if (nextwild(&xpc, wild_type, 0, firstc != '@') == FAIL)
			break;
		    goto cmdline_not_changed;
		}
	case K_UP:
	case K_DOWN:
	case K_S_UP:
	case K_S_DOWN:
	case K_PAGEUP:
	case K_KPAGEUP:
	case K_PAGEDOWN:
	case K_KPAGEDOWN:
		if (cmdline_pum_active()
			&& (c == K_PAGEUP || c == K_PAGEDOWN ||
			    c == K_KPAGEUP || c == K_KPAGEDOWN))
		{
		    wild_type = WILD_PAGEUP;
		    if (c == K_PAGEDOWN || c == K_KPAGEDOWN)
			wild_type = WILD_PAGEDOWN;
		    if (nextwild(&xpc, wild_type, 0, firstc != '@') == FAIL)
			break;
		    goto cmdline_not_changed;
		}
		else
		{
		    res = cmdline_browse_history(c, firstc, &lookfor, histype,
			    &hiscnt, &xpc);
		    if (res == CMDLINE_CHANGED)
			goto cmdline_changed;
		    else if (res == GOTO_NORMAL_MODE)
			goto returncmd;
		}
		goto cmdline_not_changed;
#ifdef FEAT_SEARCH_EXTRA
	case Ctrl_G:	    
	case Ctrl_T:	    
		if (may_adjust_incsearch_highlighting(
					  firstc, count, &is_state, c) == FAIL)
		    goto cmdline_not_changed;
		break;
#endif
	case Ctrl_V:
	case Ctrl_Q:
		{
		    ignore_drag_release = TRUE;
		    putcmdline('^', TRUE);
		    c = get_literal(mod_mask & MOD_MASK_SHIFT);
		    do_abbr = FALSE;	    
		    extra_char = NUL;
		    if (enc_utf8 && utf_iscomposing(c) && !cmd_silent)
		    {
			draw_cmdline(ccline.cmdpos,
						ccline.cmdlen - ccline.cmdpos);
			msg_putchar(' ');
			cursorcmd();
		    }
		}
		break;
#ifdef FEAT_DIGRAPHS
	case Ctrl_K:
		ignore_drag_release = TRUE;
		putcmdline('?', TRUE);
# ifdef USE_ON_FLY_SCROLL
		dont_scroll = TRUE;	    
# endif
		c = get_digraph(TRUE);
		extra_char = NUL;
		if (c != NUL)
		    break;
		redrawcmd();
		goto cmdline_not_changed;
#endif 
#ifdef FEAT_RIGHTLEFT
	case Ctrl__:	    
		if (!p_ari)
		    break;
		cmd_hkmap = !cmd_hkmap;
		goto cmdline_not_changed;
#endif
	case K_PS:
		bracketed_paste(PASTE_CMDLINE, FALSE, NULL);
		goto cmdline_changed;
	default:
#ifdef UNIX
		if (c == intr_char)
		{
		    gotesc = TRUE;	
		    goto returncmd;	
		}
#endif
		if (!IS_SPECIAL(c))
		    mod_mask = 0x0;
		break;
	}
	if (do_abbr && (IS_SPECIAL(c) || !vim_iswordc(c))
		&& (ccheck_abbr(
				(has_mbyte && c >= 0x100) ? (c + ABBR_OFF) : c)
		    || c == Ctrl_RSB))
	    goto cmdline_changed;
	if (IS_SPECIAL(c) || mod_mask != 0)
	    put_on_cmdline(get_special_key_name(c, mod_mask), -1, TRUE);
	else
	{
	    if (has_mbyte)
	    {
		j = (*mb_char2bytes)(c, IObuff);
		IObuff[j] = NUL;	
		put_on_cmdline(IObuff, j, TRUE);
	    }
	    else
	    {
		IObuff[0] = c;
		put_on_cmdline(IObuff, 1, TRUE);
	    }
	}
	goto cmdline_changed;
cmdline_not_changed:
#ifdef FEAT_SEARCH_EXTRA
	if (!is_state.incsearch_postponed)
	    continue;
#endif
cmdline_changed:
#ifdef FEAT_SEARCH_EXTRA
	if (is_state.winid != curwin->w_id)
	    init_incsearch_state(&is_state);
#endif
	if (trigger_cmdlinechanged)
	    trigger_cmd_autocmd(cmdline_type, EVENT_CMDLINECHANGED);
#ifdef FEAT_SEARCH_EXTRA
	if (xpc.xp_context == EXPAND_NOTHING && (KeyTyped || vpeekc() == NUL))
	    may_do_incsearch_highlighting(firstc, count, &is_state);
#endif
#ifdef FEAT_RIGHTLEFT
	if (cmdmsg_rl
# ifdef FEAT_ARABIC
		|| (p_arshape && !p_tbidi
				       && cmdline_has_arabic(0, ccline.cmdlen))
# endif
		)
	    if (vpeekc() == NUL)
		redrawcmd();
#endif
    }
returncmd:
#ifdef FEAT_RIGHTLEFT
    cmdmsg_rl = FALSE;
#endif
    ExpandCleanup(&xpc);
    ccline.xpc = NULL;
#ifdef FEAT_SEARCH_EXTRA
    finish_incsearch_highlighting(gotesc, &is_state, FALSE);
#endif
    if (ccline.cmdbuff != NULL)
    {
	if (ccline.cmdlen && firstc != NUL
		&& (some_key_typed || histype == HIST_SEARCH))
	{
	    add_to_history(histype, ccline.cmdbuff, TRUE,
				       histype == HIST_SEARCH ? firstc : NUL);
	    if (firstc == ':')
	    {
		vim_free(new_last_cmdline);
		new_last_cmdline = vim_strsave(ccline.cmdbuff);
	    }
	}
	if (gotesc)
	    abandon_cmdline();
    }
    msg_check();
    msg_scroll = save_msg_scroll;
    redir_off = FALSE;
    if (some_key_typed)
	need_wait_return = FALSE;
    trigger_cmd_autocmd(cmdline_type, EVENT_CMDLINELEAVE);
    State = save_State;
#ifdef FEAT_EVAL
    if (!debug_mode)
	may_trigger_modechanged();
#endif
#ifdef HAVE_INPUT_METHOD
    if (b_im_ptr != NULL && *b_im_ptr != B_IMODE_LMAP)
	im_save_status(b_im_ptr);
    im_set_active(FALSE);
#endif
    setmouse();
#ifdef CURSOR_SHAPE
    ui_cursor_shape();		
#endif
    sb_text_end_cmdline();
theend:
    {
	char_u *p = ccline.cmdbuff;
	--depth;
	if (did_save_ccline)
	    restore_cmdline(&save_ccline);
	else
	    ccline.cmdbuff = NULL;
	return p;
    }
}