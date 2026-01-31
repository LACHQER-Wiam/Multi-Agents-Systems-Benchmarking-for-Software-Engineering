spell_suggest(int count)
{
    char_u	*line;
    pos_T	prev_cursor = curwin->w_cursor;
    char_u	wcopy[MAXWLEN + 2];
    char_u	*p;
    int		i;
    int		c;
    suginfo_T	sug;
    suggest_T	*stp;
    int		mouse_used;
    int		need_cap;
    int		limit;
    int		selected = count;
    int		badlen = 0;
    int		msg_scroll_save = msg_scroll;
    int		wo_spell_save = curwin->w_p_spell;
    if (!curwin->w_p_spell)
    {
	did_set_spelllang(curwin);
	curwin->w_p_spell = TRUE;
    }
    if (*curwin->w_s->b_p_spl == NUL)
    {
	emsg(_(e_spell_checking_is_not_possible));
	return;
    }
    if (VIsual_active)
    {
	if (curwin->w_cursor.lnum != VIsual.lnum)
	{
	    vim_beep(BO_SPELL);
	    return;
	}
	badlen = (int)curwin->w_cursor.col - (int)VIsual.col;
	if (badlen < 0)
	    badlen = -badlen;
	else
	    curwin->w_cursor.col = VIsual.col;
	++badlen;
	end_visual_mode();
    }
    else if (spell_move_to(curwin, FORWARD, TRUE, TRUE, NULL) == 0
	    || curwin->w_cursor.col > prev_cursor.col)
    {
	curwin->w_cursor = prev_cursor;
	line = ml_get_curline();
	p = line + curwin->w_cursor.col;
	while (p > line && spell_iswordp_nmw(p, curwin))
	    MB_PTR_BACK(line, p);
	while (*p != NUL && !spell_iswordp_nmw(p, curwin))
	    MB_PTR_ADV(p);
	if (!spell_iswordp_nmw(p, curwin))		
	{
	    beep_flush();
	    return;
	}
	curwin->w_cursor.col = (colnr_T)(p - line);
    }
    need_cap = check_need_cap(curwin->w_cursor.lnum, curwin->w_cursor.col);
    line = vim_strsave(ml_get_curline());
    if (line == NULL)
	goto skip;
    if (sps_limit > (int)Rows - 2)
	limit = (int)Rows - 2;
    else
	limit = sps_limit;
    spell_find_suggest(line + curwin->w_cursor.col, badlen, &sug, limit,
							TRUE, need_cap, TRUE);
    if (sug.su_ga.ga_len == 0)
	msg(_("Sorry, no suggestions"));
    else if (count > 0)
    {
	if (count > sug.su_ga.ga_len)
	    smsg(_("Sorry, only %ld suggestions"), (long)sug.su_ga.ga_len);
    }
    else
    {
#ifdef FEAT_RIGHTLEFT
	cmdmsg_rl = curwin->w_p_rl;
	if (cmdmsg_rl)
	    msg_col = Columns - 1;
#endif
	msg_start();
	msg_row = Rows - 1;	
	lines_left = Rows;	
	vim_snprintf((char *)IObuff, IOSIZE, _("Change \"%.*s\" to:"),
						sug.su_badlen, sug.su_badptr);
#ifdef FEAT_RIGHTLEFT
	if (cmdmsg_rl && STRNCMP(IObuff, "Change", 6) == 0)
	{
	    vim_snprintf((char *)IObuff, IOSIZE, ":ot \"%.*s\" egnahC",
						sug.su_badlen, sug.su_badptr);
	}
#endif
	msg_puts((char *)IObuff);
	msg_clr_eos();
	msg_putchar('\n');
	msg_scroll = TRUE;
	for (i = 0; i < sug.su_ga.ga_len; ++i)
	{
	    stp = &SUG(sug.su_ga, i);
	    vim_strncpy(wcopy, stp->st_word, MAXWLEN);
	    if (sug.su_badlen > stp->st_orglen)
		vim_strncpy(wcopy + stp->st_wordlen,
					       sug.su_badptr + stp->st_orglen,
					      sug.su_badlen - stp->st_orglen);
	    vim_snprintf((char *)IObuff, IOSIZE, "%2d", i + 1);
#ifdef FEAT_RIGHTLEFT
	    if (cmdmsg_rl)
		rl_mirror(IObuff);
#endif
	    msg_puts((char *)IObuff);
	    vim_snprintf((char *)IObuff, IOSIZE, " \"%s\"", wcopy);
	    msg_puts((char *)IObuff);
	    if (sug.su_badlen < stp->st_orglen)
	    {
		vim_snprintf((char *)IObuff, IOSIZE, _(" < \"%.*s\""),
					       stp->st_orglen, sug.su_badptr);
		msg_puts((char *)IObuff);
	    }
	    if (p_verbose > 0)
	    {
		if (sps_flags & (SPS_DOUBLE | SPS_BEST))
		    vim_snprintf((char *)IObuff, IOSIZE, " (%s%d - %d)",
			stp->st_salscore ? "s " : "",
			stp->st_score, stp->st_altscore);
		else
		    vim_snprintf((char *)IObuff, IOSIZE, " (%d)",
			    stp->st_score);
#ifdef FEAT_RIGHTLEFT
		if (cmdmsg_rl)
		    rl_mirror(IObuff + 1);
#endif
		msg_advance(30);
		msg_puts((char *)IObuff);
	    }
	    msg_putchar('\n');
	}
#ifdef FEAT_RIGHTLEFT
	cmdmsg_rl = FALSE;
	msg_col = 0;
#endif
	selected = prompt_for_number(&mouse_used);
	if (mouse_used)
	    selected -= lines_left;
	lines_left = Rows;		
	msg_scroll = msg_scroll_save;
    }
    if (selected > 0 && selected <= sug.su_ga.ga_len && u_save_cursor() == OK)
    {
	VIM_CLEAR(repl_from);
	VIM_CLEAR(repl_to);
	stp = &SUG(sug.su_ga, selected - 1);
	if (sug.su_badlen > stp->st_orglen)
	{
	    repl_from = vim_strnsave(sug.su_badptr, sug.su_badlen);
	    vim_snprintf((char *)IObuff, IOSIZE, "%s%.*s", stp->st_word,
		    sug.su_badlen - stp->st_orglen,
					      sug.su_badptr + stp->st_orglen);
	    repl_to = vim_strsave(IObuff);
	}
	else
	{
	    repl_from = vim_strnsave(sug.su_badptr, stp->st_orglen);
	    repl_to = vim_strsave(stp->st_word);
	}
	p = alloc(STRLEN(line) - stp->st_orglen + stp->st_wordlen + 1);
	if (p != NULL)
	{
	    c = (int)(sug.su_badptr - line);
	    mch_memmove(p, line, c);
	    STRCPY(p + c, stp->st_word);
	    STRCAT(p, sug.su_badptr + stp->st_orglen);
	    ResetRedobuff();
	    AppendToRedobuff((char_u *)"ciw");
	    AppendToRedobuffLit(p + c,
			    stp->st_wordlen + sug.su_badlen - stp->st_orglen);
	    AppendCharToRedobuff(ESC);
	    ml_replace(curwin->w_cursor.lnum, p, FALSE);
	    curwin->w_cursor.col = c;
	    changed_bytes(curwin->w_cursor.lnum, c);
	}
    }
    else
	curwin->w_cursor = prev_cursor;
    spell_find_cleanup(&sug);
skip:
    vim_free(line);
    curwin->w_p_spell = wo_spell_save;
}