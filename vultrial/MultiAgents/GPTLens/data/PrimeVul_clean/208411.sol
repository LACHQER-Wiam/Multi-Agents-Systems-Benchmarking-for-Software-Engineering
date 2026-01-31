check_termcode(
    int		max_offset,
    char_u	*buf,
    int		bufsize,
    int		*buflen)
{
    char_u	*tp;
    char_u	*p;
    int		slen = 0;	
    int		modslen;
    int		len;
    int		retval = 0;
    int		offset;
    char_u	key_name[2];
    int		modifiers;
    char_u	*modifiers_start = NULL;
    int		key;
    int		new_slen;   
    char_u	string[MAX_KEY_CODE_LEN + 1];
    int		i, j;
    int		idx = 0;
    int		cpo_koffset;
    cpo_koffset = (vim_strchr(p_cpo, CPO_KOFFSET) != NULL);
    if (need_gather)
	gather_termleader();
    for (offset = 0; offset < max_offset; ++offset)
    {
	if (buf == NULL)
	{
	    if (offset >= typebuf.tb_len)
		break;
	    tp = typebuf.tb_buf + typebuf.tb_off + offset;
	    len = typebuf.tb_len - offset;	
	}
	else
	{
	    if (offset >= *buflen)
		break;
	    tp = buf + offset;
	    len = *buflen - offset;
	}
	if (*tp == K_SPECIAL)
	{
	    offset += 2;	
	    continue;
	}
	i = *tp;
	for (p = termleader; *p && *p != i; ++p)
	    ;
	if (*p == NUL)
	    continue;
	if (*tp == ESC && !p_ek && (State & MODE_INSERT))
	    continue;
	key_name[0] = NUL;	
	key_name[1] = NUL;	
	modifiers = 0;		
#ifdef FEAT_GUI
	if (gui.in_use)
	{
	    if (*tp == CSI)	    
	    {
		if (len < 3)
		    return -1;	    
		slen = 3;
		key_name[0] = tp[1];
		key_name[1] = tp[2];
	    }
	}
	else
#endif 
	{
	    int  mouse_index_found = -1;
	    for (idx = 0; idx < tc_len; ++idx)
	    {
		slen = termcodes[idx].len;
		modifiers_start = NULL;
		if (cpo_koffset && offset && len < slen)
		    continue;
		if (STRNCMP(termcodes[idx].code, tp,
				     (size_t)(slen > len ? len : slen)) == 0)
		{
		    int	    looks_like_mouse_start = FALSE;
		    if (len < slen)		
			return -1;		
		    if (termcodes[idx].name[0] == 'K'
				       && VIM_ISDIGIT(termcodes[idx].name[1]))
		    {
			for (j = idx + 1; j < tc_len; ++j)
			    if (termcodes[j].len == slen &&
				    STRNCMP(termcodes[idx].code,
					    termcodes[j].code, slen) == 0)
			    {
				idx = j;
				break;
			    }
		    }
		    if (slen == 2 && len > 2
			    && termcodes[idx].code[0] == ESC
			    && termcodes[idx].code[1] == '[')
		    {
			if (!isdigit(tp[2]))
			{
			    looks_like_mouse_start = TRUE;
			}
			else if (termcodes[idx].name[0] == KS_DEC_MOUSE)
			{
			    char_u  *nr = tp + 2;
			    int	    count = 0;
			    for (;;)
			    {
				++count;
				(void)getdigits(&nr);
				if (nr >= tp + len)
				    return -1;	
				if (*nr != ';')
				    break;
				++nr;
				if (nr >= tp + len)
				    return -1;	
			    }
			    if (count < 4)
				continue;	
			}
		    }
		    if (looks_like_mouse_start)
		    {
			if (mouse_index_found < 0)
			    mouse_index_found = idx;
		    }
		    else
		    {
			key_name[0] = termcodes[idx].name[0];
			key_name[1] = termcodes[idx].name[1];
			break;
		    }
		}
		if (termcodes[idx].modlen > 0 && mouse_index_found < 0)
		{
		    int at_code;
		    modslen = termcodes[idx].modlen;
		    if (cpo_koffset && offset && len < modslen)
			continue;
		    at_code = termcodes[idx].code[modslen] == '@';
		    if (STRNCMP(termcodes[idx].code, tp,
				(size_t)(modslen > len ? len : modslen)) == 0)
		    {
			int	    n;
			if (len <= modslen)	
			    return -1;		
			if (tp[modslen] == termcodes[idx].code[slen - 1])
			    slen = modslen + 1;
			else if (tp[modslen] != ';' && modslen == slen - 3)
			    continue;
			else if (at_code && tp[modslen] != '1')
			    continue;
			else
			{
			    for (j = slen - 2; j < len && (isdigit(tp[j])
				       || tp[j] == '-' || tp[j] == ';'); ++j)
				;
			    ++j;
			    if (len < j)	
				return -1;	
			    if (tp[j - 1] != termcodes[idx].code[slen - 1])
				continue;	
			    modifiers_start = tp + slen - 2;
			    n = atoi((char *)modifiers_start);
			    modifiers |= decode_modifiers(n);
			    slen = j;
			}
			key_name[0] = termcodes[idx].name[0];
			key_name[1] = termcodes[idx].name[1];
			break;
		    }
		}
	    }
	    if (idx == tc_len && mouse_index_found >= 0)
	    {
		key_name[0] = termcodes[mouse_index_found].name[0];
		key_name[1] = termcodes[mouse_index_found].name[1];
	    }
	}
#ifdef FEAT_TERMRESPONSE
	if (key_name[0] == NUL
# ifdef FEAT_MOUSE_DEC
	    || key_name[0] == KS_DEC_MOUSE
# endif
# ifdef FEAT_MOUSE_PTERM
	    || key_name[0] == KS_PTERM_MOUSE
# endif
	   )
	{
	    char_u *argp = tp[0] == ESC ? tp + 2 : tp + 1;
	    if (((tp[0] == ESC && len >= 3 && tp[1] == '[')
			    || (tp[0] == CSI && len >= 2))
		    && (VIM_ISDIGIT(*argp) || *argp == '>' || *argp == '?'))
	    {
		int resp = handle_csi(tp, len, argp, offset, buf,
					     bufsize, buflen, key_name, &slen);
		if (resp != 0)
		{
# ifdef DEBUG_TERMRESPONSE
		    if (resp == -1)
			LOG_TR(("Not enough characters for CSI sequence"));
# endif
		    return resp;
		}
	    }
	    else if ((*T_RBG != NUL || *T_RFG != NUL)
			&& ((tp[0] == ESC && len >= 2 && tp[1] == ']')
			    || tp[0] == OSC))
	    {
		if (handle_osc(tp, argp, len, key_name, &slen) == FAIL)
		    return -1;
	    }
	    else if ((check_for_codes || rcs_status.tr_progress == STATUS_SENT)
		    && ((tp[0] == ESC && len >= 2 && tp[1] == 'P')
			|| tp[0] == DCS))
	    {
		if (handle_dcs(tp, argp, len, key_name, &slen) == FAIL)
		    return -1;
	    }
	}
#endif
	if (key_name[0] == NUL)
	    continue;	    
#ifdef FEAT_GUI
	if (gui.in_use
		&& key_name[0] == (int)KS_EXTRA
		&& (key_name[1] == (int)KE_X1MOUSE
		    || key_name[1] == (int)KE_X2MOUSE
		    || key_name[1] == (int)KE_MOUSEMOVE_XY
		    || key_name[1] == (int)KE_MOUSELEFT
		    || key_name[1] == (int)KE_MOUSERIGHT
		    || key_name[1] == (int)KE_MOUSEDOWN
		    || key_name[1] == (int)KE_MOUSEUP))
	{
	    char_u	bytes[6];
	    int		num_bytes = get_bytes_from_buf(tp + slen, bytes, 4);
	    if (num_bytes == -1)	
		return -1;
	    mouse_col = 128 * (bytes[0] - ' ' - 1) + bytes[1] - ' ' - 1;
	    mouse_row = 128 * (bytes[2] - ' ' - 1) + bytes[3] - ' ' - 1;
	    slen += num_bytes;
	    if (key_name[1] == (int)KE_MOUSEMOVE_XY)
		key_name[1] = (int)KE_MOUSEMOVE;
	}
	else
#endif
	if (key_name[0] == KS_MOUSE
#ifdef FEAT_MOUSE_GPM
		|| key_name[0] == KS_GPM_MOUSE
#endif
#ifdef FEAT_MOUSE_JSB
		|| key_name[0] == KS_JSBTERM_MOUSE
#endif
#ifdef FEAT_MOUSE_NET
		|| key_name[0] == KS_NETTERM_MOUSE
#endif
#ifdef FEAT_MOUSE_DEC
		|| key_name[0] == KS_DEC_MOUSE
#endif
#ifdef FEAT_MOUSE_PTERM
		|| key_name[0] == KS_PTERM_MOUSE
#endif
#ifdef FEAT_MOUSE_URXVT
		|| key_name[0] == KS_URXVT_MOUSE
#endif
		|| key_name[0] == KS_SGR_MOUSE
		|| key_name[0] == KS_SGR_MOUSE_RELEASE)
	{
	    if (check_termcode_mouse(tp, &slen, key_name, modifiers_start, idx,
							     &modifiers) == -1)
		return -1;
	}
#ifdef FEAT_GUI
# ifdef FEAT_MENU
	else if (key_name[0] == (int)KS_MENU)
	{
	    long_u	val;
	    int		num_bytes = get_long_from_buf(tp + slen, &val);
	    if (num_bytes == -1)
		return -1;
	    current_menu = (vimmenu_T *)val;
	    slen += num_bytes;
	    if (check_menu_pointer(root_menu, current_menu) == FAIL)
	    {
		key_name[0] = KS_EXTRA;
		key_name[1] = (int)KE_IGNORE;
	    }
	}
# endif
# ifdef FEAT_GUI_TABLINE
	else if (key_name[0] == (int)KS_TABLINE)
	{
	    char_u	bytes[6];
	    int		num_bytes = get_bytes_from_buf(tp + slen, bytes, 1);
	    if (num_bytes == -1)
		return -1;
	    current_tab = (int)bytes[0];
	    if (current_tab == 255)	
		current_tab = -1;
	    slen += num_bytes;
	}
	else if (key_name[0] == (int)KS_TABMENU)
	{
	    char_u	bytes[6];
	    int		num_bytes = get_bytes_from_buf(tp + slen, bytes, 2);
	    if (num_bytes == -1)
		return -1;
	    current_tab = (int)bytes[0];
	    current_tabmenu = (int)bytes[1];
	    slen += num_bytes;
	}
# endif
# ifndef USE_ON_FLY_SCROLL
	else if (key_name[0] == (int)KS_VER_SCROLLBAR)
	{
	    long_u	val;
	    char_u	bytes[6];
	    int		num_bytes;
	    j = 0;
	    for (i = 0; tp[j] == CSI && tp[j + 1] == KS_VER_SCROLLBAR
						     && tp[j + 2] != NUL; ++i)
	    {
		j += 3;
		num_bytes = get_bytes_from_buf(tp + j, bytes, 1);
		if (num_bytes == -1)
		    break;
		if (i == 0)
		    current_scrollbar = (int)bytes[0];
		else if (current_scrollbar != (int)bytes[0])
		    break;
		j += num_bytes;
		num_bytes = get_long_from_buf(tp + j, &val);
		if (num_bytes == -1)
		    break;
		scrollbar_value = val;
		j += num_bytes;
		slen = j;
	    }
	    if (i == 0)		
		return -1;
	}
	else if (key_name[0] == (int)KS_HOR_SCROLLBAR)
	{
	    long_u	val;
	    int		num_bytes;
	    j = 0;
	    for (i = 0; tp[j] == CSI && tp[j + 1] == KS_HOR_SCROLLBAR
						     && tp[j + 2] != NUL; ++i)
	    {
		j += 3;
		num_bytes = get_long_from_buf(tp + j, &val);
		if (num_bytes == -1)
		    break;
		scrollbar_value = val;
		j += num_bytes;
		slen = j;
	    }
	    if (i == 0)		
		return -1;
	}
# endif 
#endif 
#if (defined(UNIX) || defined(VMS))
	if (key_name[0] == KS_EXTRA
# ifdef FEAT_GUI
		&& !gui.in_use
# endif
	    )
	{
	    if (key_name[1] == KE_FOCUSGAINED)
	    {
		if (!focus_state)
		{
		    ui_focus_change(TRUE);
		    did_cursorhold = TRUE;
		    focus_state = TRUE;
		}
		key_name[1] = (int)KE_IGNORE;
	    }
	    else if (key_name[1] == KE_FOCUSLOST)
	    {
		if (focus_state)
		{
		    ui_focus_change(FALSE);
		    did_cursorhold = TRUE;
		    focus_state = FALSE;
		}
		key_name[1] = (int)KE_IGNORE;
	    }
	}
#endif
	key = handle_x_keys(TERMCAP2KEY(key_name[0], key_name[1]));
	new_slen = modifiers2keycode(modifiers, &key, string);
	key_name[0] = KEY2TERMCAP0(key);
	key_name[1] = KEY2TERMCAP1(key);
	if (key_name[0] == KS_KEY)
	{
	    if (has_mbyte)
		new_slen += (*mb_char2bytes)(key_name[1], string + new_slen);
	    else
		string[new_slen++] = key_name[1];
	}
	else if (new_slen == 0 && key_name[0] == KS_EXTRA
						  && key_name[1] == KE_IGNORE)
	{
	    retval = KEYLEN_REMOVED;
	}
	else
	{
	    string[new_slen++] = K_SPECIAL;
	    string[new_slen++] = key_name[0];
	    string[new_slen++] = key_name[1];
	}
	if (put_string_in_typebuf(offset, slen, string, new_slen,
						 buf, bufsize, buflen) == FAIL)
	    return -1;
	return retval == 0 ? (len + new_slen - slen + offset) : retval;
    }
#ifdef FEAT_TERMRESPONSE
    LOG_TR(("normal character"));
#endif
    return 0;			    
}