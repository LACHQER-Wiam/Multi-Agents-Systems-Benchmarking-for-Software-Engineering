regmatch(
    char_u	*scan,		    
    proftime_T	*tm UNUSED,	    
    int		*timed_out UNUSED)  
{
  char_u	*next;		
  int		op;
  int		c;
  regitem_T	*rp;
  int		no;
  int		status;		
#ifdef FEAT_RELTIME
  int		tm_count = 0;
#endif
  regstack.ga_len = 0;
  backpos.ga_len = 0;
  for (;;)
  {
    fast_breakcheck();
#ifdef DEBUG
    if (scan != NULL && regnarrate)
    {
	mch_errmsg((char *)regprop(scan));
	mch_errmsg("(\n");
    }
#endif
    for (;;)
    {
	if (got_int || scan == NULL)
	{
	    status = RA_FAIL;
	    break;
	}
#ifdef FEAT_RELTIME
	if (tm != NULL && ++tm_count == 100)
	{
	    tm_count = 0;
	    if (profile_passed_limit(tm))
	    {
		if (timed_out != NULL)
		    *timed_out = TRUE;
		status = RA_FAIL;
		break;
	    }
	}
#endif
	status = RA_CONT;
#ifdef DEBUG
	if (regnarrate)
	{
	    mch_errmsg((char *)regprop(scan));
	    mch_errmsg("...\n");
# ifdef FEAT_SYN_HL
	    if (re_extmatch_in != NULL)
	    {
		int i;
		mch_errmsg(_("External submatches:\n"));
		for (i = 0; i < NSUBEXP; i++)
		{
		    mch_errmsg("    \"");
		    if (re_extmatch_in->matches[i] != NULL)
			mch_errmsg((char *)re_extmatch_in->matches[i]);
		    mch_errmsg("\"\n");
		}
	    }
# endif
	}
#endif
	next = regnext(scan);
	op = OP(scan);
	if (!rex.reg_line_lbr && WITH_NL(op) && REG_MULTI
			     && *rex.input == NUL && rex.lnum <= rex.reg_maxline)
	{
	    reg_nextline();
	}
	else if (rex.reg_line_lbr && WITH_NL(op) && *rex.input == '\n')
	{
	    ADVANCE_REGINPUT();
	}
	else
	{
	  if (WITH_NL(op))
	      op -= ADD_NL;
	  if (has_mbyte)
	      c = (*mb_ptr2char)(rex.input);
	  else
	      c = *rex.input;
	  switch (op)
	  {
	  case BOL:
	    if (rex.input != rex.line)
		status = RA_NOMATCH;
	    break;
	  case EOL:
	    if (c != NUL)
		status = RA_NOMATCH;
	    break;
	  case RE_BOF:
	    if (rex.lnum != 0 || rex.input != rex.line
				       || (REG_MULTI && rex.reg_firstlnum > 1))
		status = RA_NOMATCH;
	    break;
	  case RE_EOF:
	    if (rex.lnum != rex.reg_maxline || c != NUL)
		status = RA_NOMATCH;
	    break;
	  case CURSOR:
	    if (rex.reg_win == NULL
		    || (rex.lnum + rex.reg_firstlnum
						 != rex.reg_win->w_cursor.lnum)
		    || ((colnr_T)(rex.input - rex.line)
						 != rex.reg_win->w_cursor.col))
		status = RA_NOMATCH;
	    break;
	  case RE_MARK:
	    {
		int	mark = OPERAND(scan)[0];
		int	cmp = OPERAND(scan)[1];
		pos_T	*pos;
		size_t	col = REG_MULTI ? rex.input - rex.line : 0;
		pos = getmark_buf(rex.reg_buf, mark, FALSE);
		if (REG_MULTI)
		{
		    rex.line = reg_getline(rex.lnum);
		    rex.input = rex.line + col;
		}
		if (pos == NULL		     
			|| pos->lnum <= 0)   
		{
		    status = RA_NOMATCH;
		}
		else
		{
		    colnr_T pos_col = pos->lnum == rex.lnum + rex.reg_firstlnum
							  && pos->col == MAXCOL
				      ? (colnr_T)STRLEN(reg_getline(
						pos->lnum - rex.reg_firstlnum))
				      : pos->col;
		    if ((pos->lnum == rex.lnum + rex.reg_firstlnum
				? (pos_col == (colnr_T)(rex.input - rex.line)
				    ? (cmp == '<' || cmp == '>')
				    : (pos_col < (colnr_T)(rex.input - rex.line)
					? cmp != '>'
					: cmp != '<'))
				: (pos->lnum < rex.lnum + rex.reg_firstlnum
				    ? cmp != '>'
				    : cmp != '<')))
		    status = RA_NOMATCH;
		}
	    }
	    break;
	  case RE_VISUAL:
	    if (!reg_match_visual())
		status = RA_NOMATCH;
	    break;
	  case RE_LNUM:
	    if (!REG_MULTI || !re_num_cmp((long_u)(rex.lnum + rex.reg_firstlnum),
									scan))
		status = RA_NOMATCH;
	    break;
	  case RE_COL:
	    if (!re_num_cmp((long_u)(rex.input - rex.line) + 1, scan))
		status = RA_NOMATCH;
	    break;
	  case RE_VCOL:
	    if (!re_num_cmp((long_u)win_linetabsize(
			    rex.reg_win == NULL ? curwin : rex.reg_win,
			    rex.line, (colnr_T)(rex.input - rex.line)) + 1, scan))
		status = RA_NOMATCH;
	    break;
	  case BOW:	
	    if (c == NUL)	
		status = RA_NOMATCH;
	    else if (has_mbyte)
	    {
		int this_class;
		this_class = mb_get_class_buf(rex.input, rex.reg_buf);
		if (this_class <= 1)
		    status = RA_NOMATCH;  
		else if (reg_prev_class() == this_class)
		    status = RA_NOMATCH;  
	    }
	    else
	    {
		if (!vim_iswordc_buf(c, rex.reg_buf) || (rex.input > rex.line
				&& vim_iswordc_buf(rex.input[-1], rex.reg_buf)))
		    status = RA_NOMATCH;
	    }
	    break;
	  case EOW:	
	    if (rex.input == rex.line)    
		status = RA_NOMATCH;
	    else if (has_mbyte)
	    {
		int this_class, prev_class;
		this_class = mb_get_class_buf(rex.input, rex.reg_buf);
		prev_class = reg_prev_class();
		if (this_class == prev_class
			|| prev_class == 0 || prev_class == 1)
		    status = RA_NOMATCH;
	    }
	    else
	    {
		if (!vim_iswordc_buf(rex.input[-1], rex.reg_buf)
			|| (rex.input[0] != NUL
					   && vim_iswordc_buf(c, rex.reg_buf)))
		    status = RA_NOMATCH;
	    }
	    break; 
	  case ANY:
	    if (c == NUL)
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case IDENT:
	    if (!vim_isIDc(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case SIDENT:
	    if (VIM_ISDIGIT(*rex.input) || !vim_isIDc(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case KWORD:
	    if (!vim_iswordp_buf(rex.input, rex.reg_buf))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case SKWORD:
	    if (VIM_ISDIGIT(*rex.input)
				    || !vim_iswordp_buf(rex.input, rex.reg_buf))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case FNAME:
	    if (!vim_isfilec(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case SFNAME:
	    if (VIM_ISDIGIT(*rex.input) || !vim_isfilec(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case PRINT:
	    if (!vim_isprintc(PTR2CHAR(rex.input)))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case SPRINT:
	    if (VIM_ISDIGIT(*rex.input) || !vim_isprintc(PTR2CHAR(rex.input)))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case WHITE:
	    if (!VIM_ISWHITE(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NWHITE:
	    if (c == NUL || VIM_ISWHITE(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case DIGIT:
	    if (!ri_digit(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NDIGIT:
	    if (c == NUL || ri_digit(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case HEX:
	    if (!ri_hex(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NHEX:
	    if (c == NUL || ri_hex(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case OCTAL:
	    if (!ri_octal(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NOCTAL:
	    if (c == NUL || ri_octal(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case WORD:
	    if (!ri_word(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NWORD:
	    if (c == NUL || ri_word(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case HEAD:
	    if (!ri_head(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NHEAD:
	    if (c == NUL || ri_head(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case ALPHA:
	    if (!ri_alpha(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NALPHA:
	    if (c == NUL || ri_alpha(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case LOWER:
	    if (!ri_lower(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NLOWER:
	    if (c == NUL || ri_lower(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case UPPER:
	    if (!ri_upper(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case NUPPER:
	    if (c == NUL || ri_upper(c))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case EXACTLY:
	    {
		int	len;
		char_u	*opnd;
		opnd = OPERAND(scan);
		if (*opnd != *rex.input
			&& (!rex.reg_ic
			    || (!enc_utf8
			      && MB_TOLOWER(*opnd) != MB_TOLOWER(*rex.input))))
		    status = RA_NOMATCH;
		else if (*opnd == NUL)
		{
		}
		else
		{
		    if (opnd[1] == NUL && !(enc_utf8 && rex.reg_ic))
		    {
			len = 1;	
		    }
		    else
		    {
			len = (int)STRLEN(opnd);
			if (cstrncmp(opnd, rex.input, &len) != 0)
			    status = RA_NOMATCH;
		    }
		    if (status != RA_NOMATCH
			    && enc_utf8
			    && UTF_COMPOSINGLIKE(rex.input, rex.input + len)
			    && !rex.reg_icombine
			    && OP(next) != RE_COMPOSING)
		    {
			status = RA_NOMATCH;
		    }
		    if (status != RA_NOMATCH)
			rex.input += len;
		}
	    }
	    break;
	  case ANYOF:
	  case ANYBUT:
	    if (c == NUL)
		status = RA_NOMATCH;
	    else if ((cstrchr(OPERAND(scan), c) == NULL) == (op == ANYOF))
		status = RA_NOMATCH;
	    else
		ADVANCE_REGINPUT();
	    break;
	  case MULTIBYTECODE:
	    if (has_mbyte)
	    {
		int	i, len;
		char_u	*opnd;
		int	opndc = 0, inpc;
		opnd = OPERAND(scan);
		if ((len = (*mb_ptr2len)(opnd)) < 2)
		{
		    status = RA_NOMATCH;
		    break;
		}
		if (enc_utf8)
		    opndc = utf_ptr2char(opnd);
		if (enc_utf8 && utf_iscomposing(opndc))
		{
		    status = RA_NOMATCH;
		    for (i = 0; rex.input[i] != NUL;
						i += utf_ptr2len(rex.input + i))
		    {
			inpc = utf_ptr2char(rex.input + i);
			if (!utf_iscomposing(inpc))
			{
			    if (i > 0)
				break;
			}
			else if (opndc == inpc)
			{
			    len = i + utfc_ptr2len(rex.input + i);
			    status = RA_MATCH;
			    break;
			}
		    }
		}
		else
		    for (i = 0; i < len; ++i)
			if (opnd[i] != rex.input[i])
			{
			    status = RA_NOMATCH;
			    break;
			}
		rex.input += len;
	    }
	    else
		status = RA_NOMATCH;
	    break;
	  case RE_COMPOSING:
	    if (enc_utf8)
	    {
		while (utf_iscomposing(utf_ptr2char(rex.input)))
		    MB_CPTR_ADV(rex.input);
	    }
	    break;
	  case NOTHING:
	    break;
	  case BACK:
	    {
		int		i;
		backpos_T	*bp;
		bp = (backpos_T *)backpos.ga_data;
		for (i = 0; i < backpos.ga_len; ++i)
		    if (bp[i].bp_scan == scan)
			break;
		if (i == backpos.ga_len)
		{
		    if (ga_grow(&backpos, 1) == FAIL)
			status = RA_FAIL;
		    else
		    {
			bp = (backpos_T *)backpos.ga_data;
			bp[i].bp_scan = scan;
			++backpos.ga_len;
		    }
		}
		else if (reg_save_equal(&bp[i].bp_pos))
		    status = RA_NOMATCH;
		if (status != RA_FAIL && status != RA_NOMATCH)
		    reg_save(&bp[i].bp_pos, &backpos);
	    }
	    break;
	  case MOPEN + 0:   
	  case MOPEN + 1:   
	  case MOPEN + 2:
	  case MOPEN + 3:
	  case MOPEN + 4:
	  case MOPEN + 5:
	  case MOPEN + 6:
	  case MOPEN + 7:
	  case MOPEN + 8:
	  case MOPEN + 9:
	    {
		no = op - MOPEN;
		cleanup_subexpr();
		rp = regstack_push(RS_MOPEN, scan);
		if (rp == NULL)
		    status = RA_FAIL;
		else
		{
		    rp->rs_no = no;
		    save_se(&rp->rs_un.sesave, &rex.reg_startpos[no],
							  &rex.reg_startp[no]);
		}
	    }
	    break;
	  case NOPEN:	    
	  case NCLOSE:	    
		if (regstack_push(RS_NOPEN, scan) == NULL)
		    status = RA_FAIL;
		break;
#ifdef FEAT_SYN_HL
	  case ZOPEN + 1:
	  case ZOPEN + 2:
	  case ZOPEN + 3:
	  case ZOPEN + 4:
	  case ZOPEN + 5:
	  case ZOPEN + 6:
	  case ZOPEN + 7:
	  case ZOPEN + 8:
	  case ZOPEN + 9:
	    {
		no = op - ZOPEN;
		cleanup_zsubexpr();
		rp = regstack_push(RS_ZOPEN, scan);
		if (rp == NULL)
		    status = RA_FAIL;
		else
		{
		    rp->rs_no = no;
		    save_se(&rp->rs_un.sesave, &reg_startzpos[no],
							     &reg_startzp[no]);
		}
	    }
	    break;
#endif
	  case MCLOSE + 0:  
	  case MCLOSE + 1:  
	  case MCLOSE + 2:
	  case MCLOSE + 3:
	  case MCLOSE + 4:
	  case MCLOSE + 5:
	  case MCLOSE + 6:
	  case MCLOSE + 7:
	  case MCLOSE + 8:
	  case MCLOSE + 9:
	    {
		no = op - MCLOSE;
		cleanup_subexpr();
		rp = regstack_push(RS_MCLOSE, scan);
		if (rp == NULL)
		    status = RA_FAIL;
		else
		{
		    rp->rs_no = no;
		    save_se(&rp->rs_un.sesave, &rex.reg_endpos[no],
							    &rex.reg_endp[no]);
		}
	    }
	    break;
#ifdef FEAT_SYN_HL
	  case ZCLOSE + 1:  
	  case ZCLOSE + 2:
	  case ZCLOSE + 3:
	  case ZCLOSE + 4:
	  case ZCLOSE + 5:
	  case ZCLOSE + 6:
	  case ZCLOSE + 7:
	  case ZCLOSE + 8:
	  case ZCLOSE + 9:
	    {
		no = op - ZCLOSE;
		cleanup_zsubexpr();
		rp = regstack_push(RS_ZCLOSE, scan);
		if (rp == NULL)
		    status = RA_FAIL;
		else
		{
		    rp->rs_no = no;
		    save_se(&rp->rs_un.sesave, &reg_endzpos[no],
							      &reg_endzp[no]);
		}
	    }
	    break;
#endif
	  case BACKREF + 1:
	  case BACKREF + 2:
	  case BACKREF + 3:
	  case BACKREF + 4:
	  case BACKREF + 5:
	  case BACKREF + 6:
	  case BACKREF + 7:
	  case BACKREF + 8:
	  case BACKREF + 9:
	    {
		int		len;
		no = op - BACKREF;
		cleanup_subexpr();
		if (!REG_MULTI)		
		{
		    if (rex.reg_startp[no] == NULL || rex.reg_endp[no] == NULL)
		    {
			len = 0;
		    }
		    else
		    {
			len = (int)(rex.reg_endp[no] - rex.reg_startp[no]);
			if (cstrncmp(rex.reg_startp[no], rex.input, &len) != 0)
			    status = RA_NOMATCH;
		    }
		}
		else				
		{
		    if (rex.reg_startpos[no].lnum < 0
						|| rex.reg_endpos[no].lnum < 0)
		    {
			len = 0;
		    }
		    else
		    {
			if (rex.reg_startpos[no].lnum == rex.lnum
				&& rex.reg_endpos[no].lnum == rex.lnum)
			{
			    len = rex.reg_endpos[no].col
						    - rex.reg_startpos[no].col;
			    if (cstrncmp(rex.line + rex.reg_startpos[no].col,
							  rex.input, &len) != 0)
				status = RA_NOMATCH;
			}
			else
			{
			    int r = match_with_backref(
					    rex.reg_startpos[no].lnum,
					    rex.reg_startpos[no].col,
					    rex.reg_endpos[no].lnum,
					    rex.reg_endpos[no].col,
					    &len);
			    if (r != RA_MATCH)
				status = r;
			}
		    }
		}
		rex.input += len;
	    }
	    break;
#ifdef FEAT_SYN_HL
	  case ZREF + 1:
	  case ZREF + 2:
	  case ZREF + 3:
	  case ZREF + 4:
	  case ZREF + 5:
	  case ZREF + 6:
	  case ZREF + 7:
	  case ZREF + 8:
	  case ZREF + 9:
	    {
		int	len;
		cleanup_zsubexpr();
		no = op - ZREF;
		if (re_extmatch_in != NULL
			&& re_extmatch_in->matches[no] != NULL)
		{
		    len = (int)STRLEN(re_extmatch_in->matches[no]);
		    if (cstrncmp(re_extmatch_in->matches[no],
							  rex.input, &len) != 0)
			status = RA_NOMATCH;
		    else
			rex.input += len;
		}
		else
		{
		}
	    }
	    break;
#endif
	  case BRANCH:
	    {
		if (OP(next) != BRANCH) 
		    next = OPERAND(scan);	
		else
		{
		    rp = regstack_push(RS_BRANCH, scan);
		    if (rp == NULL)
			status = RA_FAIL;
		    else
			status = RA_BREAK;	
		}
	    }
	    break;
	  case BRACE_LIMITS:
	    {
		if (OP(next) == BRACE_SIMPLE)
		{
		    bl_minval = OPERAND_MIN(scan);
		    bl_maxval = OPERAND_MAX(scan);
		}
		else if (OP(next) >= BRACE_COMPLEX
			&& OP(next) < BRACE_COMPLEX + 10)
		{
		    no = OP(next) - BRACE_COMPLEX;
		    brace_min[no] = OPERAND_MIN(scan);
		    brace_max[no] = OPERAND_MAX(scan);
		    brace_count[no] = 0;
		}
		else
		{
		    internal_error("BRACE_LIMITS");
		    status = RA_FAIL;
		}
	    }
	    break;
	  case BRACE_COMPLEX + 0:
	  case BRACE_COMPLEX + 1:
	  case BRACE_COMPLEX + 2:
	  case BRACE_COMPLEX + 3:
	  case BRACE_COMPLEX + 4:
	  case BRACE_COMPLEX + 5:
	  case BRACE_COMPLEX + 6:
	  case BRACE_COMPLEX + 7:
	  case BRACE_COMPLEX + 8:
	  case BRACE_COMPLEX + 9:
	    {
		no = op - BRACE_COMPLEX;
		++brace_count[no];
		if (brace_count[no] <= (brace_min[no] <= brace_max[no]
					     ? brace_min[no] : brace_max[no]))
		{
		    rp = regstack_push(RS_BRCPLX_MORE, scan);
		    if (rp == NULL)
			status = RA_FAIL;
		    else
		    {
			rp->rs_no = no;
			reg_save(&rp->rs_un.regsave, &backpos);
			next = OPERAND(scan);
		    }
		    break;
		}
		if (brace_min[no] <= brace_max[no])
		{
		    if (brace_count[no] <= brace_max[no])
		    {
			rp = regstack_push(RS_BRCPLX_LONG, scan);
			if (rp == NULL)
			    status = RA_FAIL;
			else
			{
			    rp->rs_no = no;
			    reg_save(&rp->rs_un.regsave, &backpos);
			    next = OPERAND(scan);
			}
		    }
		}
		else
		{
		    if (brace_count[no] <= brace_min[no])
		    {
			rp = regstack_push(RS_BRCPLX_SHORT, scan);
			if (rp == NULL)
			    status = RA_FAIL;
			else
			{
			    reg_save(&rp->rs_un.regsave, &backpos);
			}
		    }
		}
	    }
	    break;
	  case BRACE_SIMPLE:
	  case STAR:
	  case PLUS:
	    {
		regstar_T	rst;
		if (OP(next) == EXACTLY)
		{
		    rst.nextb = *OPERAND(next);
		    if (rex.reg_ic)
		    {
			if (MB_ISUPPER(rst.nextb))
			    rst.nextb_ic = MB_TOLOWER(rst.nextb);
			else
			    rst.nextb_ic = MB_TOUPPER(rst.nextb);
		    }
		    else
			rst.nextb_ic = rst.nextb;
		}
		else
		{
		    rst.nextb = NUL;
		    rst.nextb_ic = NUL;
		}
		if (op != BRACE_SIMPLE)
		{
		    rst.minval = (op == STAR) ? 0 : 1;
		    rst.maxval = MAX_LIMIT;
		}
		else
		{
		    rst.minval = bl_minval;
		    rst.maxval = bl_maxval;
		}
		rst.count = regrepeat(OPERAND(scan), rst.maxval);
		if (got_int)
		{
		    status = RA_FAIL;
		    break;
		}
		if (rst.minval <= rst.maxval
			  ? rst.count >= rst.minval : rst.count >= rst.maxval)
		{
		    if ((long)((unsigned)regstack.ga_len >> 10) >= p_mmp)
		    {
			emsg(_(e_pattern_uses_more_memory_than_maxmempattern));
			status = RA_FAIL;
		    }
		    else if (ga_grow(&regstack, sizeof(regstar_T)) == FAIL)
			status = RA_FAIL;
		    else
		    {
			regstack.ga_len += sizeof(regstar_T);
			rp = regstack_push(rst.minval <= rst.maxval
					? RS_STAR_LONG : RS_STAR_SHORT, scan);
			if (rp == NULL)
			    status = RA_FAIL;
			else
			{
			    *(((regstar_T *)rp) - 1) = rst;
			    status = RA_BREAK;	    
			}
		    }
		}
		else
		    status = RA_NOMATCH;
	    }
	    break;
	  case NOMATCH:
	  case MATCH:
	  case SUBPAT:
	    rp = regstack_push(RS_NOMATCH, scan);
	    if (rp == NULL)
		status = RA_FAIL;
	    else
	    {
		rp->rs_no = op;
		reg_save(&rp->rs_un.regsave, &backpos);
		next = OPERAND(scan);
	    }
	    break;
	  case BEHIND:
	  case NOBEHIND:
	    if ((long)((unsigned)regstack.ga_len >> 10) >= p_mmp)
	    {
		emsg(_(e_pattern_uses_more_memory_than_maxmempattern));
		status = RA_FAIL;
	    }
	    else if (ga_grow(&regstack, sizeof(regbehind_T)) == FAIL)
		status = RA_FAIL;
	    else
	    {
		regstack.ga_len += sizeof(regbehind_T);
		rp = regstack_push(RS_BEHIND1, scan);
		if (rp == NULL)
		    status = RA_FAIL;
		else
		{
		    save_subexpr(((regbehind_T *)rp) - 1);
		    rp->rs_no = op;
		    reg_save(&rp->rs_un.regsave, &backpos);
		}
	    }
	    break;
	  case BHPOS:
	    if (REG_MULTI)
	    {
		if (behind_pos.rs_u.pos.col != (colnr_T)(rex.input - rex.line)
			|| behind_pos.rs_u.pos.lnum != rex.lnum)
		    status = RA_NOMATCH;
	    }
	    else if (behind_pos.rs_u.ptr != rex.input)
		status = RA_NOMATCH;
	    break;
	  case NEWL:
	    if ((c != NUL || !REG_MULTI || rex.lnum > rex.reg_maxline
			     || rex.reg_line_lbr)
					   && (c != '\n' || !rex.reg_line_lbr))
		status = RA_NOMATCH;
	    else if (rex.reg_line_lbr)
		ADVANCE_REGINPUT();
	    else
		reg_nextline();
	    break;
	  case END:
	    status = RA_MATCH;	
	    break;
	  default:
	    iemsg(_(e_corrupted_regexp_program));
#ifdef DEBUG
	    printf("Illegal op code %d\n", op);
#endif
	    status = RA_FAIL;
	    break;
	  }
	}
	if (status != RA_CONT)
	    break;
	scan = next;
    } 
    while (regstack.ga_len > 0 && status != RA_FAIL)
    {
	rp = (regitem_T *)((char *)regstack.ga_data + regstack.ga_len) - 1;
	switch (rp->rs_state)
	{
	  case RS_NOPEN:
	    regstack_pop(&scan);
	    break;
	  case RS_MOPEN:
	    if (status == RA_NOMATCH)
		restore_se(&rp->rs_un.sesave, &rex.reg_startpos[rp->rs_no],
						  &rex.reg_startp[rp->rs_no]);
	    regstack_pop(&scan);
	    break;
#ifdef FEAT_SYN_HL
	  case RS_ZOPEN:
	    if (status == RA_NOMATCH)
		restore_se(&rp->rs_un.sesave, &reg_startzpos[rp->rs_no],
						 &reg_startzp[rp->rs_no]);
	    regstack_pop(&scan);
	    break;
#endif
	  case RS_MCLOSE:
	    if (status == RA_NOMATCH)
		restore_se(&rp->rs_un.sesave, &rex.reg_endpos[rp->rs_no],
						    &rex.reg_endp[rp->rs_no]);
	    regstack_pop(&scan);
	    break;
#ifdef FEAT_SYN_HL
	  case RS_ZCLOSE:
	    if (status == RA_NOMATCH)
		restore_se(&rp->rs_un.sesave, &reg_endzpos[rp->rs_no],
						   &reg_endzp[rp->rs_no]);
	    regstack_pop(&scan);
	    break;
#endif
	  case RS_BRANCH:
	    if (status == RA_MATCH)
		regstack_pop(&scan);
	    else
	    {
		if (status != RA_BREAK)
		{
		    reg_restore(&rp->rs_un.regsave, &backpos);
		    scan = rp->rs_scan;
		}
		if (scan == NULL || OP(scan) != BRANCH)
		{
		    status = RA_NOMATCH;
		    regstack_pop(&scan);
		}
		else
		{
		    rp->rs_scan = regnext(scan);
		    reg_save(&rp->rs_un.regsave, &backpos);
		    scan = OPERAND(scan);
		}
	    }
	    break;
	  case RS_BRCPLX_MORE:
	    if (status == RA_NOMATCH)
	    {
		reg_restore(&rp->rs_un.regsave, &backpos);
		--brace_count[rp->rs_no];	
	    }
	    regstack_pop(&scan);
	    break;
	  case RS_BRCPLX_LONG:
	    if (status == RA_NOMATCH)
	    {
		reg_restore(&rp->rs_un.regsave, &backpos);
		--brace_count[rp->rs_no];
		status = RA_CONT;
	    }
	    regstack_pop(&scan);
	    if (status == RA_CONT)
		scan = regnext(scan);
	    break;
	  case RS_BRCPLX_SHORT:
	    if (status == RA_NOMATCH)
		reg_restore(&rp->rs_un.regsave, &backpos);
	    regstack_pop(&scan);
	    if (status == RA_NOMATCH)
	    {
		scan = OPERAND(scan);
		status = RA_CONT;
	    }
	    break;
	  case RS_NOMATCH:
	    if (status == (rp->rs_no == NOMATCH ? RA_MATCH : RA_NOMATCH))
		status = RA_NOMATCH;
	    else
	    {
		status = RA_CONT;
		if (rp->rs_no != SUBPAT)	
		    reg_restore(&rp->rs_un.regsave, &backpos);
	    }
	    regstack_pop(&scan);
	    if (status == RA_CONT)
		scan = regnext(scan);
	    break;
	  case RS_BEHIND1:
	    if (status == RA_NOMATCH)
	    {
		regstack_pop(&scan);
		regstack.ga_len -= sizeof(regbehind_T);
	    }
	    else
	    {
		reg_save(&(((regbehind_T *)rp) - 1)->save_after, &backpos);
		(((regbehind_T *)rp) - 1)->save_behind = behind_pos;
		behind_pos = rp->rs_un.regsave;
		rp->rs_state = RS_BEHIND2;
		reg_restore(&rp->rs_un.regsave, &backpos);
		scan = OPERAND(rp->rs_scan) + 4;
	    }
	    break;
	  case RS_BEHIND2:
	    if (status == RA_MATCH && reg_save_equal(&behind_pos))
	    {
		behind_pos = (((regbehind_T *)rp) - 1)->save_behind;
		if (rp->rs_no == BEHIND)
		    reg_restore(&(((regbehind_T *)rp) - 1)->save_after,
								    &backpos);
		else
		{
		    status = RA_NOMATCH;
		    restore_subexpr(((regbehind_T *)rp) - 1);
		}
		regstack_pop(&scan);
		regstack.ga_len -= sizeof(regbehind_T);
	    }
	    else
	    {
		long limit;
		no = OK;
		limit = OPERAND_MIN(rp->rs_scan);
		if (REG_MULTI)
		{
		    if (limit > 0
			    && ((rp->rs_un.regsave.rs_u.pos.lnum
						    < behind_pos.rs_u.pos.lnum
				    ? (colnr_T)STRLEN(rex.line)
				    : behind_pos.rs_u.pos.col)
				- rp->rs_un.regsave.rs_u.pos.col >= limit))
			no = FAIL;
		    else if (rp->rs_un.regsave.rs_u.pos.col == 0)
		    {
			if (rp->rs_un.regsave.rs_u.pos.lnum
					< behind_pos.rs_u.pos.lnum
				|| reg_getline(
					--rp->rs_un.regsave.rs_u.pos.lnum)
								  == NULL)
			    no = FAIL;
			else
			{
			    reg_restore(&rp->rs_un.regsave, &backpos);
			    rp->rs_un.regsave.rs_u.pos.col =
						 (colnr_T)STRLEN(rex.line);
			}
		    }
		    else
		    {
			if (has_mbyte)
			{
			    char_u *line =
				  reg_getline(rp->rs_un.regsave.rs_u.pos.lnum);
			    rp->rs_un.regsave.rs_u.pos.col -=
				(*mb_head_off)(line, line
				    + rp->rs_un.regsave.rs_u.pos.col - 1) + 1;
			}
			else
			    --rp->rs_un.regsave.rs_u.pos.col;
		    }
		}
		else
		{
		    if (rp->rs_un.regsave.rs_u.ptr == rex.line)
			no = FAIL;
		    else
		    {
			MB_PTR_BACK(rex.line, rp->rs_un.regsave.rs_u.ptr);
			if (limit > 0 && (long)(behind_pos.rs_u.ptr
				     - rp->rs_un.regsave.rs_u.ptr) > limit)
			    no = FAIL;
		    }
		}
		if (no == OK)
		{
		    reg_restore(&rp->rs_un.regsave, &backpos);
		    scan = OPERAND(rp->rs_scan) + 4;
		    if (status == RA_MATCH)
		    {
			status = RA_NOMATCH;
			restore_subexpr(((regbehind_T *)rp) - 1);
		    }
		}
		else
		{
		    behind_pos = (((regbehind_T *)rp) - 1)->save_behind;
		    if (rp->rs_no == NOBEHIND)
		    {
			reg_restore(&(((regbehind_T *)rp) - 1)->save_after,
								    &backpos);
			status = RA_MATCH;
		    }
		    else
		    {
			if (status == RA_MATCH)
			{
			    status = RA_NOMATCH;
			    restore_subexpr(((regbehind_T *)rp) - 1);
			}
		    }
		    regstack_pop(&scan);
		    regstack.ga_len -= sizeof(regbehind_T);
		}
	    }
	    break;
	  case RS_STAR_LONG:
	  case RS_STAR_SHORT:
	    {
		regstar_T	    *rst = ((regstar_T *)rp) - 1;
		if (status == RA_MATCH)
		{
		    regstack_pop(&scan);
		    regstack.ga_len -= sizeof(regstar_T);
		    break;
		}
		if (status != RA_BREAK)
		    reg_restore(&rp->rs_un.regsave, &backpos);
		for (;;)
		{
		    if (status != RA_BREAK)
		    {
			if (rp->rs_state == RS_STAR_LONG)
			{
			    if (--rst->count < rst->minval)
				break;
			    if (rex.input == rex.line)
			    {
				if (rex.lnum == 0)
				{
				    status = RA_NOMATCH;
				    break;
				}
				--rex.lnum;
				rex.line = reg_getline(rex.lnum);
				if (rex.line == NULL)
				    break;
				rex.input = rex.line + STRLEN(rex.line);
				fast_breakcheck();
			    }
			    else
				MB_PTR_BACK(rex.line, rex.input);
			}
			else
			{
			    if (rst->count == rst->minval
				  || regrepeat(OPERAND(rp->rs_scan), 1L) == 0)
				break;
			    ++rst->count;
			}
			if (got_int)
			    break;
		    }
		    else
			status = RA_NOMATCH;
		    if (rst->nextb == NUL || *rex.input == rst->nextb
					     || *rex.input == rst->nextb_ic)
		    {
			reg_save(&rp->rs_un.regsave, &backpos);
			scan = regnext(rp->rs_scan);
			status = RA_CONT;
			break;
		    }
		}
		if (status != RA_CONT)
		{
		    regstack_pop(&scan);
		    regstack.ga_len -= sizeof(regstar_T);
		    status = RA_NOMATCH;
		}
	    }
	    break;
	}
	if (status == RA_CONT || rp == (regitem_T *)
			     ((char *)regstack.ga_data + regstack.ga_len) - 1)
	    break;
    }
    if (status == RA_CONT)
	continue;
    if (regstack.ga_len == 0 || status == RA_FAIL)
    {
	if (scan == NULL)
	{
	    iemsg(_(e_corrupted_regexp_program));
#ifdef DEBUG
	    printf("Premature EOL\n");
#endif
	}
	return (status == RA_MATCH);
    }
  } 
}