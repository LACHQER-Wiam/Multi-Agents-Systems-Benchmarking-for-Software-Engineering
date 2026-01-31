suggest_trie_walk(
    suginfo_T	*su,
    langp_T	*lp,
    char_u	*fword,
    int		soundfold)
{
    char_u	tword[MAXWLEN];	    
    trystate_T	stack[MAXWLEN];
    char_u	preword[MAXWLEN * 3]; 
    char_u	compflags[MAXWLEN];	
    trystate_T	*sp;
    int		newscore;
    int		score;
    char_u	*byts, *fbyts, *pbyts;
    idx_T	*idxs, *fidxs, *pidxs;
    int		depth;
    int		c, c2, c3;
    int		n = 0;
    int		flags;
    garray_T	*gap;
    idx_T	arridx;
    int		len;
    char_u	*p;
    fromto_T	*ftp;
    int		fl = 0, tl;
    int		repextra = 0;	    
    slang_T	*slang = lp->lp_slang;
    int		fword_ends;
    int		goodword_ends;
#ifdef DEBUG_TRIEWALK
    char_u	changename[MAXWLEN][80];
#endif
    int		breakcheckcount = 1000;
#ifdef FEAT_RELTIME
    proftime_T	time_limit;
#endif
    int		compound_ok;
    depth = 0;
    sp = &stack[0];
    CLEAR_POINTER(sp);
    sp->ts_curi = 1;
    if (soundfold)
    {
	byts = fbyts = slang->sl_sbyts;
	idxs = fidxs = slang->sl_sidxs;
	pbyts = NULL;
	pidxs = NULL;
	sp->ts_prefixdepth = PFD_NOPREFIX;
	sp->ts_state = STATE_START;
    }
    else
    {
	fbyts = slang->sl_fbyts;
	fidxs = slang->sl_fidxs;
	pbyts = slang->sl_pbyts;
	pidxs = slang->sl_pidxs;
	if (pbyts != NULL)
	{
	    byts = pbyts;
	    idxs = pidxs;
	    sp->ts_prefixdepth = PFD_PREFIXTREE;
	    sp->ts_state = STATE_NOPREFIX;	
	}
	else
	{
	    byts = fbyts;
	    idxs = fidxs;
	    sp->ts_prefixdepth = PFD_NOPREFIX;
	    sp->ts_state = STATE_START;
	}
    }
#ifdef FEAT_RELTIME
    if (spell_suggest_timeout > 0)
	profile_setlimit(spell_suggest_timeout, &time_limit);
#endif
    while (depth >= 0 && !got_int)
    {
	sp = &stack[depth];
	switch (sp->ts_state)
	{
	case STATE_START:
	case STATE_NOPREFIX:
	    arridx = sp->ts_arridx;	    
	    len = byts[arridx];		    
	    arridx += sp->ts_curi;	    
	    if (sp->ts_prefixdepth == PFD_PREFIXTREE)
	    {
		for (n = 0; n < len && byts[arridx + n] == 0; ++n)
		    ;
		sp->ts_curi += n;
		n = (int)sp->ts_state;
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_ENDNUL;
		sp->ts_save_badflags = su->su_badflags;
		if (depth < MAXWLEN - 1
			    && (byts[arridx] == 0 || n == (int)STATE_NOPREFIX))
		{
		    if (has_mbyte)
			n = nofold_len(fword, sp->ts_fidx, su->su_badptr);
		    else
			n = sp->ts_fidx;
		    flags = badword_captype(su->su_badptr, su->su_badptr + n);
		    su->su_badflags = badword_captype(su->su_badptr + n,
					       su->su_badptr + su->su_badlen);
#ifdef DEBUG_TRIEWALK
		    sprintf(changename[depth], "prefix");
#endif
		    go_deeper(stack, depth, 0);
		    ++depth;
		    sp = &stack[depth];
		    sp->ts_prefixdepth = depth - 1;
		    byts = fbyts;
		    idxs = fidxs;
		    sp->ts_arridx = 0;
		    tword[sp->ts_twordlen] = NUL;
		    make_case_word(tword + sp->ts_splitoff,
					  preword + sp->ts_prewordlen, flags);
		    sp->ts_prewordlen = (char_u)STRLEN(preword);
		    sp->ts_splitoff = sp->ts_twordlen;
		}
		break;
	    }
	    if (sp->ts_curi > len || byts[arridx] != 0)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_ENDNUL;
		sp->ts_save_badflags = su->su_badflags;
		break;
	    }
	    ++sp->ts_curi;		
	    flags = (int)idxs[arridx];
	    if (flags & WF_NOSUGGEST)
		break;
	    fword_ends = (fword[sp->ts_fidx] == NUL
			   || (soundfold
			       ? VIM_ISWHITE(fword[sp->ts_fidx])
			       : !spell_iswordp(fword + sp->ts_fidx, curwin)));
	    tword[sp->ts_twordlen] = NUL;
	    if (sp->ts_prefixdepth <= PFD_NOTSPECIAL
					&& (sp->ts_flags & TSF_PREFIXOK) == 0
					&& pbyts != NULL)
	    {
		n = stack[sp->ts_prefixdepth].ts_arridx;
		len = pbyts[n++];
		for (c = 0; c < len && pbyts[n + c] == 0; ++c)
		    ;
		if (c > 0)
		{
		    c = valid_word_prefix(c, n, flags,
				       tword + sp->ts_splitoff, slang, FALSE);
		    if (c == 0)
			break;
		    if (c & WF_RAREPFX)
			flags |= WF_RARE;
		    sp->ts_flags |= TSF_PREFIXOK;
		}
	    }
	    if (sp->ts_complen == sp->ts_compsplit && fword_ends
						     && (flags & WF_NEEDCOMP))
		goodword_ends = FALSE;
	    else
		goodword_ends = TRUE;
	    p = NULL;
	    compound_ok = TRUE;
	    if (sp->ts_complen > sp->ts_compsplit)
	    {
		if (slang->sl_nobreak)
		{
		    if (sp->ts_fidx - sp->ts_splitfidx
					  == sp->ts_twordlen - sp->ts_splitoff
			    && STRNCMP(fword + sp->ts_splitfidx,
					tword + sp->ts_splitoff,
					 sp->ts_fidx - sp->ts_splitfidx) == 0)
		    {
			preword[sp->ts_prewordlen] = NUL;
			newscore = score_wordcount_adj(slang, sp->ts_score,
						 preword + sp->ts_prewordlen,
						 sp->ts_prewordlen > 0);
			if (newscore <= su->su_maxscore)
			    add_suggestion(su, &su->su_ga, preword,
				    sp->ts_splitfidx - repextra,
				    newscore, 0, FALSE,
				    lp->lp_sallang, FALSE);
			break;
		    }
		}
		else
		{
		    if (((unsigned)flags >> 24) == 0
			    || sp->ts_twordlen - sp->ts_splitoff
						       < slang->sl_compminlen)
			break;
		    if (has_mbyte
			    && slang->sl_compminlen > 0
			    && mb_charlen(tword + sp->ts_splitoff)
						       < slang->sl_compminlen)
			break;
		    compflags[sp->ts_complen] = ((unsigned)flags >> 24);
		    compflags[sp->ts_complen + 1] = NUL;
		    vim_strncpy(preword + sp->ts_prewordlen,
			    tword + sp->ts_splitoff,
			    sp->ts_twordlen - sp->ts_splitoff);
		    if (match_checkcompoundpattern(preword,  sp->ts_prewordlen,
							  &slang->sl_comppat))
			compound_ok = FALSE;
		    if (compound_ok)
		    {
			p = preword;
			while (*skiptowhite(p) != NUL)
			    p = skipwhite(skiptowhite(p));
			if (fword_ends && !can_compound(slang, p,
						compflags + sp->ts_compsplit))
			    compound_ok = FALSE;
		    }
		    p = preword + sp->ts_prewordlen;
		    MB_PTR_BACK(preword, p);
		}
	    }
	    if (soundfold)
		STRCPY(preword + sp->ts_prewordlen, tword + sp->ts_splitoff);
	    else if (flags & WF_KEEPCAP)
		find_keepcap_word(slang, tword + sp->ts_splitoff,
						 preword + sp->ts_prewordlen);
	    else
	    {
		c = su->su_badflags;
		if ((c & WF_ALLCAP)
			&& su->su_badlen == (*mb_ptr2len)(su->su_badptr))
		    c = WF_ONECAP;
		c |= flags;
		if (p != NULL && spell_iswordp_nmw(p, curwin))
		    c &= ~WF_ONECAP;
		make_case_word(tword + sp->ts_splitoff,
					      preword + sp->ts_prewordlen, c);
	    }
	    if (!soundfold)
	    {
		if (flags & WF_BANNED)
		{
		    add_banned(su, preword + sp->ts_prewordlen);
		    break;
		}
		if ((sp->ts_complen == sp->ts_compsplit
			    && WAS_BANNED(su, preword + sp->ts_prewordlen))
						   || WAS_BANNED(su, preword))
		{
		    if (slang->sl_compprog == NULL)
			break;
		    goodword_ends = FALSE;
		}
	    }
	    newscore = 0;
	    if (!soundfold)	
	    {
		if ((flags & WF_REGION)
			    && (((unsigned)flags >> 16) & lp->lp_region) == 0)
		    newscore += SCORE_REGION;
		if (flags & WF_RARE)
		    newscore += SCORE_RARE;
		if (!spell_valid_case(su->su_badflags,
				  captype(preword + sp->ts_prewordlen, NULL)))
		    newscore += SCORE_ICASE;
	    }
	    if (fword_ends
		    && goodword_ends
		    && sp->ts_fidx >= sp->ts_fidxtry
		    && compound_ok)
	    {
#ifdef DEBUG_TRIEWALK
		if (soundfold && STRCMP(preword, "smwrd") == 0)
		{
		    int	    j;
		    smsg("------ %s -------", fword);
		    for (j = 0; j < depth; ++j)
			smsg("%s", changename[j]);
		}
#endif
		if (soundfold)
		{
		    add_sound_suggest(su, preword, sp->ts_score, lp);
		}
		else if (sp->ts_fidx > 0)
		{
		    p = fword + sp->ts_fidx;
		    MB_PTR_BACK(fword, p);
		    if (!spell_iswordp(p, curwin) && *preword != NUL)
		    {
			p = preword + STRLEN(preword);
			MB_PTR_BACK(preword, p);
			if (spell_iswordp(p, curwin))
			    newscore += SCORE_NONWORD;
		    }
		    score = score_wordcount_adj(slang,
						sp->ts_score + newscore,
						preword + sp->ts_prewordlen,
						sp->ts_prewordlen > 0);
		    if (score <= su->su_maxscore)
		    {
			add_suggestion(su, &su->su_ga, preword,
				    sp->ts_fidx - repextra,
				    score, 0, FALSE, lp->lp_sallang, FALSE);
			if (su->su_badflags & WF_MIXCAP)
			{
			    c = captype(preword, NULL);
			    if (c == 0 || c == WF_ALLCAP)
			    {
				make_case_word(tword + sp->ts_splitoff,
					      preword + sp->ts_prewordlen,
						      c == 0 ? WF_ALLCAP : 0);
				add_suggestion(su, &su->su_ga, preword,
					sp->ts_fidx - repextra,
					score + SCORE_ICASE, 0, FALSE,
					lp->lp_sallang, FALSE);
			    }
			}
		    }
		}
	    }
	    if ((sp->ts_fidx >= sp->ts_fidxtry || fword_ends)
		    && (!has_mbyte || sp->ts_tcharlen == 0))
	    {
		int	try_compound;
		int	try_split;
		try_split = (sp->ts_fidx - repextra < su->su_badlen)
								&& !soundfold;
		try_compound = FALSE;
		if (!soundfold
			&& !slang->sl_nocompoundsugs
			&& slang->sl_compprog != NULL
			&& ((unsigned)flags >> 24) != 0
			&& sp->ts_twordlen - sp->ts_splitoff
						       >= slang->sl_compminlen
			&& (!has_mbyte
			    || slang->sl_compminlen == 0
			    || mb_charlen(tword + sp->ts_splitoff)
						      >= slang->sl_compminlen)
			&& (slang->sl_compsylmax < MAXWLEN
			    || sp->ts_complen + 1 - sp->ts_compsplit
							  < slang->sl_compmax)
			&& (can_be_compound(sp, slang,
					 compflags, ((unsigned)flags >> 24))))
		{
		    try_compound = TRUE;
		    compflags[sp->ts_complen] = ((unsigned)flags >> 24);
		    compflags[sp->ts_complen + 1] = NUL;
		}
		if (slang->sl_nobreak && !slang->sl_nocompoundsugs)
		    try_compound = TRUE;
		else if (!fword_ends
			&& try_compound
			&& (sp->ts_flags & TSF_DIDSPLIT) == 0)
		{
		    try_compound = FALSE;
		    sp->ts_flags |= TSF_DIDSPLIT;
		    --sp->ts_curi;	    
		    compflags[sp->ts_complen] = NUL;
		}
		else
		    sp->ts_flags &= ~TSF_DIDSPLIT;
		if (try_split || try_compound)
		{
		    if (!try_compound && (!fword_ends || !goodword_ends))
		    {
			if (sp->ts_complen == sp->ts_compsplit
						     && (flags & WF_NEEDCOMP))
			    break;
			p = preword;
			while (*skiptowhite(p) != NUL)
			    p = skipwhite(skiptowhite(p));
			if (sp->ts_complen > sp->ts_compsplit
				&& !can_compound(slang, p,
						compflags + sp->ts_compsplit))
			    break;
			if (slang->sl_nosplitsugs)
			    newscore += SCORE_SPLIT_NO;
			else
			    newscore += SCORE_SPLIT;
			newscore = score_wordcount_adj(slang, newscore,
					   preword + sp->ts_prewordlen, TRUE);
		    }
		    if (TRY_DEEPER(su, stack, depth, newscore))
		    {
			go_deeper(stack, depth, newscore);
#ifdef DEBUG_TRIEWALK
			if (!try_compound && !fword_ends)
			    sprintf(changename[depth], "%.*s-%s: split",
				 sp->ts_twordlen, tword, fword + sp->ts_fidx);
			else
			    sprintf(changename[depth], "%.*s-%s: compound",
				 sp->ts_twordlen, tword, fword + sp->ts_fidx);
#endif
			sp->ts_save_badflags = su->su_badflags;
			PROF_STORE(sp->ts_state)
			sp->ts_state = STATE_SPLITUNDO;
			++depth;
			sp = &stack[depth];
			if (!try_compound && !fword_ends)
			    STRCAT(preword, " ");
			sp->ts_prewordlen = (char_u)STRLEN(preword);
			sp->ts_splitoff = sp->ts_twordlen;
			sp->ts_splitfidx = sp->ts_fidx;
			if (((!try_compound && !spell_iswordp_nmw(fword
							       + sp->ts_fidx,
							       curwin))
				    || fword_ends)
				&& fword[sp->ts_fidx] != NUL
				&& goodword_ends)
			{
			    int	    l;
			    l = mb_ptr2len(fword + sp->ts_fidx);
			    if (fword_ends)
			    {
				mch_memmove(preword + sp->ts_prewordlen,
						      fword + sp->ts_fidx, l);
				sp->ts_prewordlen += l;
				preword[sp->ts_prewordlen] = NUL;
			    }
			    else
				sp->ts_score -= SCORE_SPLIT - SCORE_SUBST;
			    sp->ts_fidx += l;
			}
			if (try_compound)
			    ++sp->ts_complen;
			else
			    sp->ts_compsplit = sp->ts_complen;
			sp->ts_prefixdepth = PFD_NOPREFIX;
			if (has_mbyte)
			    n = nofold_len(fword, sp->ts_fidx, su->su_badptr);
			else
			    n = sp->ts_fidx;
			su->su_badflags = badword_captype(su->su_badptr + n,
					       su->su_badptr + su->su_badlen);
			sp->ts_arridx = 0;
			if (pbyts != NULL)
			{
			    byts = pbyts;
			    idxs = pidxs;
			    sp->ts_prefixdepth = PFD_PREFIXTREE;
			    PROF_STORE(sp->ts_state)
			    sp->ts_state = STATE_NOPREFIX;
			}
		    }
		}
	    }
	    break;
	case STATE_SPLITUNDO:
	    su->su_badflags = sp->ts_save_badflags;
	    PROF_STORE(sp->ts_state)
	    sp->ts_state = STATE_START;
	    byts = fbyts;
	    idxs = fidxs;
	    break;
	case STATE_ENDNUL:
	    su->su_badflags = sp->ts_save_badflags;
	    if (fword[sp->ts_fidx] == NUL && sp->ts_tcharlen == 0)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_DEL;
		break;
	    }
	    PROF_STORE(sp->ts_state)
	    sp->ts_state = STATE_PLAIN;
	case STATE_PLAIN:
	    arridx = sp->ts_arridx;
	    if (sp->ts_curi > byts[arridx])
	    {
		PROF_STORE(sp->ts_state)
		if (sp->ts_fidx >= sp->ts_fidxtry)
		    sp->ts_state = STATE_DEL;
		else
		    sp->ts_state = STATE_FINAL;
	    }
	    else
	    {
		arridx += sp->ts_curi++;
		c = byts[arridx];
		if (c == fword[sp->ts_fidx]
			|| (sp->ts_tcharlen > 0 && sp->ts_isdiff != DIFF_NONE))
		    newscore = 0;
		else
		    newscore = SCORE_SUBST;
		if ((newscore == 0
			    || (sp->ts_fidx >= sp->ts_fidxtry
				&& ((sp->ts_flags & TSF_DIDDEL) == 0
				    || c != fword[sp->ts_delidx])))
			&& TRY_DEEPER(su, stack, depth, newscore))
		{
		    go_deeper(stack, depth, newscore);
#ifdef DEBUG_TRIEWALK
		    if (newscore > 0)
			sprintf(changename[depth], "%.*s-%s: subst %c to %c",
				sp->ts_twordlen, tword, fword + sp->ts_fidx,
				fword[sp->ts_fidx], c);
		    else
			sprintf(changename[depth], "%.*s-%s: accept %c",
				sp->ts_twordlen, tword, fword + sp->ts_fidx,
				fword[sp->ts_fidx]);
#endif
		    ++depth;
		    sp = &stack[depth];
		    if (fword[sp->ts_fidx] != NUL)
			++sp->ts_fidx;
		    tword[sp->ts_twordlen++] = c;
		    sp->ts_arridx = idxs[arridx];
		    if (newscore == SCORE_SUBST)
			sp->ts_isdiff = DIFF_YES;
		    if (has_mbyte)
		    {
			if (sp->ts_tcharlen == 0)
			{
			    sp->ts_tcharidx = 0;
			    sp->ts_tcharlen = MB_BYTE2LEN(c);
			    sp->ts_fcharstart = sp->ts_fidx - 1;
			    sp->ts_isdiff = (newscore != 0)
						       ? DIFF_YES : DIFF_NONE;
			}
			else if (sp->ts_isdiff == DIFF_INSERT)
			    --sp->ts_fidx;
			if (++sp->ts_tcharidx == sp->ts_tcharlen)
			{
			    if (sp->ts_isdiff == DIFF_YES)
			    {
				sp->ts_fidx = sp->ts_fcharstart
					    + mb_ptr2len(
						    fword + sp->ts_fcharstart);
				if (enc_utf8
					&& utf_iscomposing(
					    utf_ptr2char(tword
						+ sp->ts_twordlen
							   - sp->ts_tcharlen))
					&& utf_iscomposing(
					    utf_ptr2char(fword
							+ sp->ts_fcharstart)))
				    sp->ts_score -=
						  SCORE_SUBST - SCORE_SUBCOMP;
				else if (!soundfold
					&& slang->sl_has_map
					&& similar_chars(slang,
					    mb_ptr2char(tword
						+ sp->ts_twordlen
							   - sp->ts_tcharlen),
					    mb_ptr2char(fword
							+ sp->ts_fcharstart)))
				    sp->ts_score -=
						  SCORE_SUBST - SCORE_SIMILAR;
			    }
			    else if (sp->ts_isdiff == DIFF_INSERT
					 && sp->ts_twordlen > sp->ts_tcharlen)
			    {
				p = tword + sp->ts_twordlen - sp->ts_tcharlen;
				c = mb_ptr2char(p);
				if (enc_utf8 && utf_iscomposing(c))
				{
				    sp->ts_score -= SCORE_INS - SCORE_INSCOMP;
				}
				else
				{
				    MB_PTR_BACK(tword, p);
				    if (c == mb_ptr2char(p))
					sp->ts_score -= SCORE_INS
							       - SCORE_INSDUP;
				}
			    }
			    sp->ts_tcharlen = 0;
			}
		    }
		    else
		    {
			if (newscore != 0
				&& !soundfold
				&& slang->sl_has_map
				&& similar_chars(slang,
						   c, fword[sp->ts_fidx - 1]))
			    sp->ts_score -= SCORE_SUBST - SCORE_SIMILAR;
		    }
		}
	    }
	    break;
	case STATE_DEL:
	    if (has_mbyte && sp->ts_tcharlen > 0)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_FINAL;
		break;
	    }
	    PROF_STORE(sp->ts_state)
	    sp->ts_state = STATE_INS_PREP;
	    sp->ts_curi = 1;
	    if (soundfold && sp->ts_fidx == 0 && fword[sp->ts_fidx] == '*')
		newscore = 2 * SCORE_DEL / 3;
	    else
		newscore = SCORE_DEL;
	    if (fword[sp->ts_fidx] != NUL
				    && TRY_DEEPER(su, stack, depth, newscore))
	    {
		go_deeper(stack, depth, newscore);
#ifdef DEBUG_TRIEWALK
		sprintf(changename[depth], "%.*s-%s: delete %c",
			sp->ts_twordlen, tword, fword + sp->ts_fidx,
			fword[sp->ts_fidx]);
#endif
		++depth;
		stack[depth].ts_flags |= TSF_DIDDEL;
		stack[depth].ts_delidx = sp->ts_fidx;
		if (has_mbyte)
		{
		    c = mb_ptr2char(fword + sp->ts_fidx);
		    stack[depth].ts_fidx += mb_ptr2len(fword + sp->ts_fidx);
		    if (enc_utf8 && utf_iscomposing(c))
			stack[depth].ts_score -= SCORE_DEL - SCORE_DELCOMP;
		    else if (c == mb_ptr2char(fword + stack[depth].ts_fidx))
			stack[depth].ts_score -= SCORE_DEL - SCORE_DELDUP;
		}
		else
		{
		    ++stack[depth].ts_fidx;
		    if (fword[sp->ts_fidx] == fword[sp->ts_fidx + 1])
			stack[depth].ts_score -= SCORE_DEL - SCORE_DELDUP;
		}
		break;
	    }
	case STATE_INS_PREP:
	    if (sp->ts_flags & TSF_DIDDEL)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_SWAP;
		break;
	    }
	    n = sp->ts_arridx;
	    for (;;)
	    {
		if (sp->ts_curi > byts[n])
		{
		    PROF_STORE(sp->ts_state)
		    sp->ts_state = STATE_SWAP;
		    break;
		}
		if (byts[n + sp->ts_curi] != NUL)
		{
		    PROF_STORE(sp->ts_state)
		    sp->ts_state = STATE_INS;
		    break;
		}
		++sp->ts_curi;
	    }
	    break;
	case STATE_INS:
	    n = sp->ts_arridx;
	    if (sp->ts_curi > byts[n])
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_SWAP;
		break;
	    }
	    n += sp->ts_curi++;
	    c = byts[n];
	    if (soundfold && sp->ts_twordlen == 0 && c == '*')
		newscore = 2 * SCORE_INS / 3;
	    else
		newscore = SCORE_INS;
	    if (c != fword[sp->ts_fidx]
				    && TRY_DEEPER(su, stack, depth, newscore))
	    {
		go_deeper(stack, depth, newscore);
#ifdef DEBUG_TRIEWALK
		sprintf(changename[depth], "%.*s-%s: insert %c",
			sp->ts_twordlen, tword, fword + sp->ts_fidx,
			c);
#endif
		++depth;
		sp = &stack[depth];
		tword[sp->ts_twordlen++] = c;
		sp->ts_arridx = idxs[n];
		if (has_mbyte)
		{
		    fl = MB_BYTE2LEN(c);
		    if (fl > 1)
		    {
			sp->ts_tcharlen = fl;
			sp->ts_tcharidx = 1;
			sp->ts_isdiff = DIFF_INSERT;
		    }
		}
		else
		    fl = 1;
		if (fl == 1)
		{
		    if (sp->ts_twordlen >= 2
					   && tword[sp->ts_twordlen - 2] == c)
			sp->ts_score -= SCORE_INS - SCORE_INSDUP;
		}
	    }
	    break;
	case STATE_SWAP:
	    p = fword + sp->ts_fidx;
	    c = *p;
	    if (c == NUL)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_FINAL;
		break;
	    }
	    if (!soundfold && !spell_iswordp(p, curwin))
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
		break;
	    }
	    if (has_mbyte)
	    {
		n = MB_CPTR2LEN(p);
		c = mb_ptr2char(p);
		if (p[n] == NUL)
		    c2 = NUL;
		else if (!soundfold && !spell_iswordp(p + n, curwin))
		    c2 = c; 
		else
		    c2 = mb_ptr2char(p + n);
	    }
	    else
	    {
		if (p[1] == NUL)
		    c2 = NUL;
		else if (!soundfold && !spell_iswordp(p + 1, curwin))
		    c2 = c; 
		else
		    c2 = p[1];
	    }
	    if (c2 == NUL)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
		break;
	    }
	    if (c == c2)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_SWAP3;
		break;
	    }
	    if (c2 != NUL && TRY_DEEPER(su, stack, depth, SCORE_SWAP))
	    {
		go_deeper(stack, depth, SCORE_SWAP);
#ifdef DEBUG_TRIEWALK
		sprintf(changename[depth], "%.*s-%s: swap %c and %c",
			sp->ts_twordlen, tword, fword + sp->ts_fidx,
			c, c2);
#endif
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_UNSWAP;
		++depth;
		if (has_mbyte)
		{
		    fl = mb_char2len(c2);
		    mch_memmove(p, p + n, fl);
		    mb_char2bytes(c, p + fl);
		    stack[depth].ts_fidxtry = sp->ts_fidx + n + fl;
		}
		else
		{
		    p[0] = c2;
		    p[1] = c;
		    stack[depth].ts_fidxtry = sp->ts_fidx + 2;
		}
	    }
	    else
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
	    }
	    break;
	case STATE_UNSWAP:
	    p = fword + sp->ts_fidx;
	    if (has_mbyte)
	    {
		n = mb_ptr2len(p);
		c = mb_ptr2char(p + n);
		mch_memmove(p + mb_ptr2len(p + n), p, n);
		mb_char2bytes(c, p);
	    }
	    else
	    {
		c = *p;
		*p = p[1];
		p[1] = c;
	    }
	case STATE_SWAP3:
	    p = fword + sp->ts_fidx;
	    if (has_mbyte)
	    {
		n = MB_CPTR2LEN(p);
		c = mb_ptr2char(p);
		fl = MB_CPTR2LEN(p + n);
		c2 = mb_ptr2char(p + n);
		if (!soundfold && !spell_iswordp(p + n + fl, curwin))
		    c3 = c;	
		else
		    c3 = mb_ptr2char(p + n + fl);
	    }
	    else
	    {
		c = *p;
		c2 = p[1];
		if (!soundfold && !spell_iswordp(p + 2, curwin))
		    c3 = c;	
		else
		    c3 = p[2];
	    }
	    if (c == c3 || c3 == NUL)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
		break;
	    }
	    if (TRY_DEEPER(su, stack, depth, SCORE_SWAP3))
	    {
		go_deeper(stack, depth, SCORE_SWAP3);
#ifdef DEBUG_TRIEWALK
		sprintf(changename[depth], "%.*s-%s: swap3 %c and %c",
			sp->ts_twordlen, tword, fword + sp->ts_fidx,
			c, c3);
#endif
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_UNSWAP3;
		++depth;
		if (has_mbyte)
		{
		    tl = mb_char2len(c3);
		    mch_memmove(p, p + n + fl, tl);
		    mb_char2bytes(c2, p + tl);
		    mb_char2bytes(c, p + fl + tl);
		    stack[depth].ts_fidxtry = sp->ts_fidx + n + fl + tl;
		}
		else
		{
		    p[0] = p[2];
		    p[2] = c;
		    stack[depth].ts_fidxtry = sp->ts_fidx + 3;
		}
	    }
	    else
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
	    }
	    break;
	case STATE_UNSWAP3:
	    p = fword + sp->ts_fidx;
	    if (has_mbyte)
	    {
		n = mb_ptr2len(p);
		c2 = mb_ptr2char(p + n);
		fl = mb_ptr2len(p + n);
		c = mb_ptr2char(p + n + fl);
		tl = mb_ptr2len(p + n + fl);
		mch_memmove(p + fl + tl, p, n);
		mb_char2bytes(c, p);
		mb_char2bytes(c2, p + tl);
		p = p + tl;
	    }
	    else
	    {
		c = *p;
		*p = p[2];
		p[2] = c;
		++p;
	    }
	    if (!soundfold && !spell_iswordp(p, curwin))
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
		break;
	    }
	    if (TRY_DEEPER(su, stack, depth, SCORE_SWAP3))
	    {
		go_deeper(stack, depth, SCORE_SWAP3);
#ifdef DEBUG_TRIEWALK
		p = fword + sp->ts_fidx;
		sprintf(changename[depth], "%.*s-%s: rotate left %c%c%c",
			sp->ts_twordlen, tword, fword + sp->ts_fidx,
			p[0], p[1], p[2]);
#endif
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_UNROT3L;
		++depth;
		p = fword + sp->ts_fidx;
		if (has_mbyte)
		{
		    n = MB_CPTR2LEN(p);
		    c = mb_ptr2char(p);
		    fl = MB_CPTR2LEN(p + n);
		    fl += MB_CPTR2LEN(p + n + fl);
		    mch_memmove(p, p + n, fl);
		    mb_char2bytes(c, p + fl);
		    stack[depth].ts_fidxtry = sp->ts_fidx + n + fl;
		}
		else
		{
		    c = *p;
		    *p = p[1];
		    p[1] = p[2];
		    p[2] = c;
		    stack[depth].ts_fidxtry = sp->ts_fidx + 3;
		}
	    }
	    else
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
	    }
	    break;
	case STATE_UNROT3L:
	    p = fword + sp->ts_fidx;
	    if (has_mbyte)
	    {
		n = mb_ptr2len(p);
		n += mb_ptr2len(p + n);
		c = mb_ptr2char(p + n);
		tl = mb_ptr2len(p + n);
		mch_memmove(p + tl, p, n);
		mb_char2bytes(c, p);
	    }
	    else
	    {
		c = p[2];
		p[2] = p[1];
		p[1] = *p;
		*p = c;
	    }
	    if (TRY_DEEPER(su, stack, depth, SCORE_SWAP3))
	    {
		go_deeper(stack, depth, SCORE_SWAP3);
#ifdef DEBUG_TRIEWALK
		p = fword + sp->ts_fidx;
		sprintf(changename[depth], "%.*s-%s: rotate right %c%c%c",
			sp->ts_twordlen, tword, fword + sp->ts_fidx,
			p[0], p[1], p[2]);
#endif
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_UNROT3R;
		++depth;
		p = fword + sp->ts_fidx;
		if (has_mbyte)
		{
		    n = MB_CPTR2LEN(p);
		    n += MB_CPTR2LEN(p + n);
		    c = mb_ptr2char(p + n);
		    tl = MB_CPTR2LEN(p + n);
		    mch_memmove(p + tl, p, n);
		    mb_char2bytes(c, p);
		    stack[depth].ts_fidxtry = sp->ts_fidx + n + tl;
		}
		else
		{
		    c = p[2];
		    p[2] = p[1];
		    p[1] = *p;
		    *p = c;
		    stack[depth].ts_fidxtry = sp->ts_fidx + 3;
		}
	    }
	    else
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_REP_INI;
	    }
	    break;
	case STATE_UNROT3R:
	    p = fword + sp->ts_fidx;
	    if (has_mbyte)
	    {
		c = mb_ptr2char(p);
		tl = mb_ptr2len(p);
		n = mb_ptr2len(p + tl);
		n += mb_ptr2len(p + tl + n);
		mch_memmove(p, p + tl, n);
		mb_char2bytes(c, p + n);
	    }
	    else
	    {
		c = *p;
		*p = p[1];
		p[1] = p[2];
		p[2] = c;
	    }
	case STATE_REP_INI:
	    if ((lp->lp_replang == NULL && !soundfold)
		    || sp->ts_score + SCORE_REP >= su->su_maxscore
		    || sp->ts_fidx < sp->ts_fidxtry)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_FINAL;
		break;
	    }
	    if (soundfold)
		sp->ts_curi = slang->sl_repsal_first[fword[sp->ts_fidx]];
	    else
		sp->ts_curi = lp->lp_replang->sl_rep_first[fword[sp->ts_fidx]];
	    if (sp->ts_curi < 0)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_FINAL;
		break;
	    }
	    PROF_STORE(sp->ts_state)
	    sp->ts_state = STATE_REP;
	case STATE_REP:
	    p = fword + sp->ts_fidx;
	    if (soundfold)
		gap = &slang->sl_repsal;
	    else
		gap = &lp->lp_replang->sl_rep;
	    while (sp->ts_curi < gap->ga_len)
	    {
		ftp = (fromto_T *)gap->ga_data + sp->ts_curi++;
		if (*ftp->ft_from != *p)
		{
		    sp->ts_curi = gap->ga_len;
		    break;
		}
		if (STRNCMP(ftp->ft_from, p, STRLEN(ftp->ft_from)) == 0
			&& TRY_DEEPER(su, stack, depth, SCORE_REP))
		{
		    go_deeper(stack, depth, SCORE_REP);
#ifdef DEBUG_TRIEWALK
		    sprintf(changename[depth], "%.*s-%s: replace %s with %s",
			    sp->ts_twordlen, tword, fword + sp->ts_fidx,
			    ftp->ft_from, ftp->ft_to);
#endif
		    PROF_STORE(sp->ts_state)
		    sp->ts_state = STATE_REP_UNDO;
		    ++depth;
		    fl = (int)STRLEN(ftp->ft_from);
		    tl = (int)STRLEN(ftp->ft_to);
		    if (fl != tl)
		    {
			STRMOVE(p + tl, p + fl);
			repextra += tl - fl;
		    }
		    mch_memmove(p, ftp->ft_to, tl);
		    stack[depth].ts_fidxtry = sp->ts_fidx + tl;
		    stack[depth].ts_tcharlen = 0;
		    break;
		}
	    }
	    if (sp->ts_curi >= gap->ga_len && sp->ts_state == STATE_REP)
	    {
		PROF_STORE(sp->ts_state)
		sp->ts_state = STATE_FINAL;
	    }
	    break;
	case STATE_REP_UNDO:
	    if (soundfold)
		gap = &slang->sl_repsal;
	    else
		gap = &lp->lp_replang->sl_rep;
	    ftp = (fromto_T *)gap->ga_data + sp->ts_curi - 1;
	    fl = (int)STRLEN(ftp->ft_from);
	    tl = (int)STRLEN(ftp->ft_to);
	    p = fword + sp->ts_fidx;
	    if (fl != tl)
	    {
		STRMOVE(p + fl, p + tl);
		repextra -= tl - fl;
	    }
	    mch_memmove(p, ftp->ft_from, fl);
	    PROF_STORE(sp->ts_state)
	    sp->ts_state = STATE_REP;
	    break;
	default:
	    --depth;
	    if (depth >= 0 && stack[depth].ts_prefixdepth == PFD_PREFIXTREE)
	    {
		byts = pbyts;
		idxs = pidxs;
	    }
	    if (--breakcheckcount == 0)
	    {
		ui_breakcheck();
		breakcheckcount = 1000;
#ifdef FEAT_RELTIME
		if (spell_suggest_timeout > 0
					  && profile_passed_limit(&time_limit))
		    got_int = TRUE;
#endif
	    }
	}
    }
}