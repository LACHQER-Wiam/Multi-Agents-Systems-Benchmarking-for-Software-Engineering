parse_command_modifiers(
	exarg_T	    *eap,
	char	    **errormsg,
	cmdmod_T    *cmod,
	int	    skip_only)
{
    char_u  *orig_cmd = eap->cmd;
    char_u  *cmd_start = NULL;
    int	    use_plus_cmd = FALSE;
    int	    starts_with_colon = FALSE;
    int	    vim9script = in_vim9script();
    int	    has_visual_range = FALSE;
    CLEAR_POINTER(cmod);
    cmod->cmod_flags = sticky_cmdmod_flags;
    if (STRNCMP(eap->cmd, "'<,'>", 5) == 0)
    {
	eap->cmd += 5;
	cmd_start = eap->cmd;
	has_visual_range = TRUE;
    }
    for (;;)
    {
	char_u  *p;
	while (*eap->cmd == ' ' || *eap->cmd == '\t' || *eap->cmd == ':')
	{
	    if (*eap->cmd == ':')
		starts_with_colon = TRUE;
	    ++eap->cmd;
	}
	if (*eap->cmd == NUL && exmode_active
		   && (getline_equal(eap->getline, eap->cookie, getexmodeline)
		       || getline_equal(eap->getline, eap->cookie, getexline))
			&& curwin->w_cursor.lnum < curbuf->b_ml.ml_line_count)
	{
	    use_plus_cmd = TRUE;
	    if (!skip_only)
		ex_pressedreturn = TRUE;
	    break;  
	}
	if (comment_start(eap->cmd, starts_with_colon))
	{
	    if (eap->nextcmd == NULL)
	    {
		eap->nextcmd = vim_strchr(eap->cmd, '\n');
		if (eap->nextcmd != NULL)
		    ++eap->nextcmd;
	    }
	    if (vim9script && has_cmdmod(cmod, FALSE))
		*errormsg = _(e_command_modifier_without_command);
	    return FAIL;
	}
	if (*eap->cmd == NUL)
	{
	    if (!skip_only)
	    {
		ex_pressedreturn = TRUE;
		if (vim9script && has_cmdmod(cmod, FALSE))
		    *errormsg = _(e_command_modifier_without_command);
	    }
	    return FAIL;
	}
	p = skip_range(eap->cmd, TRUE, NULL);
	if (vim9script)
	{
	    char_u *s, *n;
	    for (s = eap->cmd; ASCII_ISALPHA(*s); ++s)
		;
	    n = skipwhite(s);
	    if (*n == '.' || *n == '=' || (*n != NUL && n[1] == '=')
		    || *s == '[')
		break;
	}
	switch (*p)
	{
	    case 'a':	if (!checkforcmd_noparen(&eap->cmd, "aboveleft", 3))
			    break;
			cmod->cmod_split |= WSP_ABOVE;
			continue;
	    case 'b':	if (checkforcmd_noparen(&eap->cmd, "belowright", 3))
			{
			    cmod->cmod_split |= WSP_BELOW;
			    continue;
			}
			if (checkforcmd_opt(&eap->cmd, "browse", 3, TRUE))
			{
#ifdef FEAT_BROWSE_CMD
			    cmod->cmod_flags |= CMOD_BROWSE;
#endif
			    continue;
			}
			if (!checkforcmd_noparen(&eap->cmd, "botright", 2))
			    break;
			cmod->cmod_split |= WSP_BOT;
			continue;
	    case 'c':	if (!checkforcmd_opt(&eap->cmd, "confirm", 4, TRUE))
			    break;
#if defined(FEAT_GUI_DIALOG) || defined(FEAT_CON_DIALOG)
			cmod->cmod_flags |= CMOD_CONFIRM;
#endif
			continue;
	    case 'k':	if (checkforcmd_noparen(&eap->cmd, "keepmarks", 3))
			{
			    cmod->cmod_flags |= CMOD_KEEPMARKS;
			    continue;
			}
			if (checkforcmd_noparen(&eap->cmd, "keepalt", 5))
			{
			    cmod->cmod_flags |= CMOD_KEEPALT;
			    continue;
			}
			if (checkforcmd_noparen(&eap->cmd, "keeppatterns", 5))
			{
			    cmod->cmod_flags |= CMOD_KEEPPATTERNS;
			    continue;
			}
			if (!checkforcmd_noparen(&eap->cmd, "keepjumps", 5))
			    break;
			cmod->cmod_flags |= CMOD_KEEPJUMPS;
			continue;
	    case 'f':	
			{
			    char_u  *reg_pat;
			    char_u  *nulp = NULL;
			    int	    c = 0;
			    if (!checkforcmd_noparen(&p, "filter", 4)
				    || *p == NUL
				    || (ends_excmd(*p)
#ifdef FEAT_EVAL
				     && (!vim9script || VIM_ISWHITE(p[1]))
#endif
				     ))
				break;
			    if (*p == '!')
			    {
				cmod->cmod_filter_force = TRUE;
				p = skipwhite(p + 1);
				if (*p == NUL || ends_excmd(*p))
				    break;
			    }
#ifdef FEAT_EVAL
			    if (vim9script && !VIM_ISWHITE(p[-1]))
				break;
#endif
			    if (skip_only)
				p = skip_vimgrep_pat(p, NULL, NULL);
			    else
				p = skip_vimgrep_pat_ext(p, &reg_pat, NULL,
								    &nulp, &c);
			    if (p == NULL || *p == NUL)
				break;
			    if (!skip_only)
			    {
				cmod->cmod_filter_regmatch.regprog =
						vim_regcomp(reg_pat, RE_MAGIC);
				if (cmod->cmod_filter_regmatch.regprog == NULL)
				    break;
				if (nulp != NULL)
				    *nulp = c;
			    }
			    eap->cmd = p;
			    continue;
			}
	    case 'h':	if (p != eap->cmd || !checkforcmd_noparen(&p, "hide", 3)
					       || *p == NUL || ends_excmd(*p))
			    break;
			eap->cmd = p;
			cmod->cmod_flags |= CMOD_HIDE;
			continue;
	    case 'l':	if (checkforcmd_noparen(&eap->cmd, "lockmarks", 3))
			{
			    cmod->cmod_flags |= CMOD_LOCKMARKS;
			    continue;
			}
			if (checkforcmd_noparen(&eap->cmd, "legacy", 3))
			{
			    if (ends_excmd2(p, eap->cmd))
			    {
				*errormsg =
				      _(e_legacy_must_be_followed_by_command);
				return FAIL;
			    }
			    cmod->cmod_flags |= CMOD_LEGACY;
			    continue;
			}
			if (!checkforcmd_noparen(&eap->cmd, "leftabove", 5))
			    break;
			cmod->cmod_split |= WSP_ABOVE;
			continue;
	    case 'n':	if (checkforcmd_noparen(&eap->cmd, "noautocmd", 3))
			{
			    cmod->cmod_flags |= CMOD_NOAUTOCMD;
			    continue;
			}
			if (!checkforcmd_noparen(&eap->cmd, "noswapfile", 3))
			    break;
			cmod->cmod_flags |= CMOD_NOSWAPFILE;
			continue;
	    case 'r':	if (!checkforcmd_noparen(&eap->cmd, "rightbelow", 6))
			    break;
			cmod->cmod_split |= WSP_BELOW;
			continue;
	    case 's':	if (checkforcmd_noparen(&eap->cmd, "sandbox", 3))
			{
			    cmod->cmod_flags |= CMOD_SANDBOX;
			    continue;
			}
			if (!checkforcmd_noparen(&eap->cmd, "silent", 3))
			    break;
			cmod->cmod_flags |= CMOD_SILENT;
			if (*eap->cmd == '!' && !VIM_ISWHITE(eap->cmd[-1]))
			{
			    eap->cmd = skipwhite(eap->cmd + 1);
			    cmod->cmod_flags |= CMOD_ERRSILENT;
			}
			continue;
	    case 't':	if (checkforcmd_noparen(&p, "tab", 3))
			{
			    if (!skip_only)
			    {
				long tabnr = get_address(eap, &eap->cmd,
						    ADDR_TABS, eap->skip,
						    skip_only, FALSE, 1);
				if (tabnr == MAXLNUM)
				    cmod->cmod_tab = tabpage_index(curtab) + 1;
				else
				{
				    if (tabnr < 0 || tabnr > LAST_TAB_NR)
				    {
					*errormsg = _(e_invalid_range);
					return FAIL;
				    }
				    cmod->cmod_tab = tabnr + 1;
				}
			    }
			    eap->cmd = p;
			    continue;
			}
			if (!checkforcmd_noparen(&eap->cmd, "topleft", 2))
			    break;
			cmod->cmod_split |= WSP_TOP;
			continue;
	    case 'u':	if (!checkforcmd_noparen(&eap->cmd, "unsilent", 3))
			    break;
			cmod->cmod_flags |= CMOD_UNSILENT;
			continue;
	    case 'v':	if (checkforcmd_noparen(&eap->cmd, "vertical", 4))
			{
			    cmod->cmod_split |= WSP_VERT;
			    continue;
			}
			if (checkforcmd_noparen(&eap->cmd, "vim9cmd", 4))
			{
			    if (ends_excmd2(p, eap->cmd))
			    {
				*errormsg =
				      _(e_vim9cmd_must_be_followed_by_command);
				return FAIL;
			    }
			    cmod->cmod_flags |= CMOD_VIM9CMD;
			    continue;
			}
			if (!checkforcmd_noparen(&p, "verbose", 4))
			    break;
			if (vim_isdigit(*eap->cmd))
			{
			    cmod->cmod_verbose = atoi((char *)eap->cmd) + 1;
			}
			else
			    cmod->cmod_verbose = 2;  
			eap->cmd = p;
			continue;
	}
	break;
    }
    if (has_visual_range)
    {
	if (eap->cmd > cmd_start)
	{
	    if (use_plus_cmd)
	    {
		size_t len = STRLEN(cmd_start);
		mch_memmove(orig_cmd, cmd_start, len);
		STRCPY(orig_cmd + len, " *+");
	    }
	    else
	    {
		mch_memmove(cmd_start - 5, cmd_start, eap->cmd - cmd_start);
		eap->cmd -= 5;
		mch_memmove(eap->cmd - 1, ":'<,'>", 6);
	    }
	}
	else
	    if (use_plus_cmd)
		eap->cmd = (char_u *)"'<,'>+";
	    else
		eap->cmd = orig_cmd;
    }
    else if (use_plus_cmd)
	eap->cmd = (char_u *)"+";
    return OK;
}