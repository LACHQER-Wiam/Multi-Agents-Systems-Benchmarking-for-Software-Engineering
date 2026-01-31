STATIC SSize_t
S_study_chunk(pTHX_ RExC_state_t *pRExC_state, regnode **scanp,
                        SSize_t *minlenp, SSize_t *deltap,
			regnode *last,
			scan_data_t *data,
			I32 stopparen,
                        U32 recursed_depth,
			regnode_ssc *and_withp,
			U32 flags, U32 depth, bool was_mutate_ok)
{
    dVAR;
    SSize_t min = 0;
    I32 pars = 0, code;
    regnode *scan = *scanp, *next;
    SSize_t delta = 0;
    int is_inf = (flags & SCF_DO_SUBSTR) && (data->flags & SF_IS_INF);
    int is_inf_internal = 0;		
    I32 is_par = OP(scan) == OPEN ? ARG(scan) : 0;
    scan_data_t data_fake;
    SV *re_trie_maxbuff = NULL;
    regnode *first_non_open = scan;
    SSize_t stopmin = SSize_t_MAX;
    scan_frame *frame = NULL;
    GET_RE_DEBUG_FLAGS_DECL;
    PERL_ARGS_ASSERT_STUDY_CHUNK;
    RExC_study_started= 1;
    Zero(&data_fake, 1, scan_data_t);
    if ( depth == 0 ) {
        while (first_non_open && OP(first_non_open) == OPEN)
            first_non_open=regnext(first_non_open);
    }
  fake_study_recurse:
    DEBUG_r(
        RExC_study_chunk_recursed_count++;
    );
    DEBUG_OPTIMISE_MORE_r(
    {
        Perl_re_indentf( aTHX_  "study_chunk stopparen=%ld recursed_count=%lu depth=%lu recursed_depth=%lu scan=%p last=%p",
            depth, (long)stopparen,
            (unsigned long)RExC_study_chunk_recursed_count,
            (unsigned long)depth, (unsigned long)recursed_depth,
            scan,
            last);
        if (recursed_depth) {
            U32 i;
            U32 j;
            for ( j = 0 ; j < recursed_depth ; j++ ) {
                for ( i = 0 ; i < (U32)RExC_total_parens ; i++ ) {
                    if (
                        PAREN_TEST(RExC_study_chunk_recursed +
                                   ( j * RExC_study_chunk_recursed_bytes), i )
                        && (
                            !j ||
                            !PAREN_TEST(RExC_study_chunk_recursed +
                                   (( j - 1 ) * RExC_study_chunk_recursed_bytes), i)
                        )
                    ) {
                        Perl_re_printf( aTHX_ " %d",(int)i);
                        break;
                    }
                }
                if ( j + 1 < recursed_depth ) {
                    Perl_re_printf( aTHX_  ",");
                }
            }
        }
        Perl_re_printf( aTHX_ "\n");
    }
    );
    while ( scan && OP(scan) != END && scan < last ){
        UV min_subtract = 0;    
	bool unfolded_multi_char = FALSE;
        bool mutate_ok = was_mutate_ok && !(frame && frame->in_gosub);
        DEBUG_STUDYDATA("Peep", data, depth, is_inf);
        DEBUG_PEEP("Peep", scan, depth, flags);
        if (mutate_ok)
            JOIN_EXACT(scan,&min_subtract, &unfolded_multi_char, 0);
        rck_elide_nothing(scan);
        if ( OP(scan) == DEFINEP ) {
            SSize_t minlen = 0;
            SSize_t deltanext = 0;
            SSize_t fake_last_close = 0;
            I32 f = SCF_IN_DEFINE;
            StructCopy(&zero_scan_data, &data_fake, scan_data_t);
            scan = regnext(scan);
            assert( OP(scan) == IFTHEN );
            DEBUG_PEEP("expect IFTHEN", scan, depth, flags);
            data_fake.last_closep= &fake_last_close;
            minlen = *minlenp;
            next = regnext(scan);
            scan = NEXTOPER(NEXTOPER(scan));
            DEBUG_PEEP("scan", scan, depth, flags);
            DEBUG_PEEP("next", next, depth, flags);
            (void)study_chunk(pRExC_state, &scan, &minlen,
                              &deltanext, next, &data_fake, stopparen,
                              recursed_depth, NULL, f, depth+1, mutate_ok);
            scan = next;
        } else
        if (
            OP(scan) == BRANCH  ||
            OP(scan) == BRANCHJ ||
            OP(scan) == IFTHEN
        ) {
	    next = regnext(scan);
	    code = OP(scan);
	    if (OP(next) == code || code == IFTHEN) {
		SSize_t max1 = 0, min1 = SSize_t_MAX, num = 0;
		regnode_ssc accum;
		regnode * const startbranch=scan;
                if (flags & SCF_DO_SUBSTR) {
                    scan_commit(pRExC_state, data, minlenp, is_inf);
                }
                if (flags & SCF_DO_STCLASS)
		    ssc_init_zero(pRExC_state, &accum);
		while (OP(scan) == code) {
		    SSize_t deltanext, minnext, fake;
		    I32 f = 0;
		    regnode_ssc this_class;
                    DEBUG_PEEP("Branch", scan, depth, flags);
		    num++;
                    StructCopy(&zero_scan_data, &data_fake, scan_data_t);
		    if (data) {
			data_fake.whilem_c = data->whilem_c;
			data_fake.last_closep = data->last_closep;
		    }
		    else
			data_fake.last_closep = &fake;
		    data_fake.pos_delta = delta;
		    next = regnext(scan);
                    scan = NEXTOPER(scan); 
                    if (code != BRANCH)    
			scan = NEXTOPER(scan);
		    if (flags & SCF_DO_STCLASS) {
			ssc_init(pRExC_state, &this_class);
			data_fake.start_class = &this_class;
			f = SCF_DO_STCLASS_AND;
		    }
		    if (flags & SCF_WHILEM_VISITED_POS)
			f |= SCF_WHILEM_VISITED_POS;
		    minnext = study_chunk(pRExC_state, &scan, minlenp,
                                      &deltanext, next, &data_fake, stopparen,
                                      recursed_depth, NULL, f, depth+1,
                                      mutate_ok);
		    if (min1 > minnext)
			min1 = minnext;
		    if (deltanext == SSize_t_MAX) {
			is_inf = is_inf_internal = 1;
			max1 = SSize_t_MAX;
		    } else if (max1 < minnext + deltanext)
			max1 = minnext + deltanext;
		    scan = next;
		    if (data_fake.flags & (SF_HAS_PAR|SF_IN_PAR))
			pars++;
	            if (data_fake.flags & SCF_SEEN_ACCEPT) {
	                if ( stopmin > minnext)
	                    stopmin = min + min1;
	                flags &= ~SCF_DO_SUBSTR;
	                if (data)
	                    data->flags |= SCF_SEEN_ACCEPT;
	            }
		    if (data) {
			if (data_fake.flags & SF_HAS_EVAL)
			    data->flags |= SF_HAS_EVAL;
			data->whilem_c = data_fake.whilem_c;
		    }
		    if (flags & SCF_DO_STCLASS)
			ssc_or(pRExC_state, &accum, (regnode_charclass*)&this_class);
		}
		if (code == IFTHEN && num < 2) 
		    min1 = 0;
		if (flags & SCF_DO_SUBSTR) {
		    data->pos_min += min1;
		    if (data->pos_delta >= SSize_t_MAX - (max1 - min1))
		        data->pos_delta = SSize_t_MAX;
		    else
		        data->pos_delta += max1 - min1;
		    if (max1 != min1 || is_inf)
			data->cur_is_floating = 1;
		}
		min += min1;
		if (delta == SSize_t_MAX
		 || SSize_t_MAX - delta - (max1 - min1) < 0)
		    delta = SSize_t_MAX;
		else
		    delta += max1 - min1;
		if (flags & SCF_DO_STCLASS_OR) {
		    ssc_or(pRExC_state, data->start_class, (regnode_charclass*) &accum);
		    if (min1) {
			ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
			flags &= ~SCF_DO_STCLASS;
		    }
		}
		else if (flags & SCF_DO_STCLASS_AND) {
		    if (min1) {
			ssc_and(pRExC_state, data->start_class, (regnode_charclass *) &accum);
			flags &= ~SCF_DO_STCLASS;
		    }
		    else {
			INIT_AND_WITHP;
			StructCopy(data->start_class, and_withp, regnode_ssc);
			flags &= ~SCF_DO_STCLASS_AND;
			StructCopy(&accum, data->start_class, regnode_ssc);
			flags |= SCF_DO_STCLASS_OR;
		    }
		}
                if (PERL_ENABLE_TRIE_OPTIMISATION
                    && OP(startbranch) == BRANCH
                    && mutate_ok
                ) {
		    int made=0;
		    if (!re_trie_maxbuff) {
			re_trie_maxbuff = get_sv(RE_TRIE_MAXBUF_NAME, 1);
			if (!SvIOK(re_trie_maxbuff))
			    sv_setiv(re_trie_maxbuff, RE_TRIE_MAXBUF_INIT);
		    }
                    if ( SvIV(re_trie_maxbuff)>=0  ) {
                        regnode *cur;
                        regnode *first = (regnode *)NULL;
                        regnode *last = (regnode *)NULL;
                        regnode *tail = scan;
                        U8 trietype = 0;
                        U32 count=0;
                        while ( OP( tail ) == TAIL ) {
                            tail = regnext( tail );
                        }
                        DEBUG_TRIE_COMPILE_r({
                            regprop(RExC_rx, RExC_mysv, tail, NULL, pRExC_state);
                            Perl_re_indentf( aTHX_  "%s %" UVuf ":%s\n",
                              depth+1,
                              "Looking for TRIE'able sequences. Tail node is ",
                              (UV) REGNODE_OFFSET(tail),
                              SvPV_nolen_const( RExC_mysv )
                            );
                        });
#define TRIE_TYPE(X) ( ( NOTHING == (X) )                                   \
                       ? NOTHING                                            \
                       : ( EXACT == (X) || EXACT_ONLY8 == (X) )             \
                         ? EXACT                                            \
                         : (     EXACTFU == (X)                             \
                              || EXACTFU_ONLY8 == (X)                       \
                              || EXACTFUP == (X) )                          \
                           ? EXACTFU                                        \
                           : ( EXACTFAA == (X) )                            \
                             ? EXACTFAA                                     \
                             : ( EXACTL == (X) )                            \
                               ? EXACTL                                     \
                               : ( EXACTFLU8 == (X) )                       \
                                 ? EXACTFLU8                                \
                                 : 0 )
                        for ( cur = startbranch ; cur != scan ; cur = regnext( cur ) ) {
                            regnode * const noper = NEXTOPER( cur );
                            U8 noper_type = OP( noper );
                            U8 noper_trietype = TRIE_TYPE( noper_type );
#if defined(DEBUGGING) || defined(NOJUMPTRIE)
                            regnode * const noper_next = regnext( noper );
                            U8 noper_next_type = (noper_next && noper_next < tail) ? OP(noper_next) : 0;
                            U8 noper_next_trietype = (noper_next && noper_next < tail) ? TRIE_TYPE( noper_next_type ) :0;
#endif
                            DEBUG_TRIE_COMPILE_r({
                                regprop(RExC_rx, RExC_mysv, cur, NULL, pRExC_state);
                                Perl_re_indentf( aTHX_  "- %d:%s (%d)",
                                   depth+1,
                                   REG_NODE_NUM(cur), SvPV_nolen_const( RExC_mysv ), REG_NODE_NUM(cur) );
                                regprop(RExC_rx, RExC_mysv, noper, NULL, pRExC_state);
                                Perl_re_printf( aTHX_  " -> %d:%s",
                                    REG_NODE_NUM(noper), SvPV_nolen_const(RExC_mysv));
                                if ( noper_next ) {
                                  regprop(RExC_rx, RExC_mysv, noper_next, NULL, pRExC_state);
                                  Perl_re_printf( aTHX_ "\t=> %d:%s\t",
                                    REG_NODE_NUM(noper_next), SvPV_nolen_const(RExC_mysv));
                                }
                                Perl_re_printf( aTHX_  "(First==%d,Last==%d,Cur==%d,tt==%s,ntt==%s,nntt==%s)\n",
                                   REG_NODE_NUM(first), REG_NODE_NUM(last), REG_NODE_NUM(cur),
				   PL_reg_name[trietype], PL_reg_name[noper_trietype], PL_reg_name[noper_next_trietype]
				);
                            });
                            if ( noper_trietype
                                  &&
                                  (
                                        ( noper_trietype == NOTHING )
                                        || ( trietype == NOTHING )
                                        || ( trietype == noper_trietype )
                                  )
#ifdef NOJUMPTRIE
                                  && noper_next >= tail
#endif
                                  && count < U16_MAX)
                            {
                                if ( !first ) {
                                    first = cur;
				    if ( noper_trietype == NOTHING ) {
#if !defined(DEBUGGING) && !defined(NOJUMPTRIE)
					regnode * const noper_next = regnext( noper );
                                        U8 noper_next_type = (noper_next && noper_next < tail) ? OP(noper_next) : 0;
					U8 noper_next_trietype = noper_next_type ? TRIE_TYPE( noper_next_type ) :0;
#endif
                                        if ( noper_next_trietype ) {
					    trietype = noper_next_trietype;
                                        } else if (noper_next_type)  {
                                            first = NULL;
                                        }
                                    } else {
                                        trietype = noper_trietype;
                                    }
                                } else {
                                    if ( trietype == NOTHING )
                                        trietype = noper_trietype;
                                    last = cur;
                                }
				if (first)
				    count++;
                            } 
                            else {
                                if ( last ) {
                                    if ( trietype && trietype != NOTHING )
                                        make_trie( pRExC_state,
                                                startbranch, first, cur, tail,
                                                count, trietype, depth+1 );
                                    last = NULL; 
                                }
                                if ( noper_trietype
#ifdef NOJUMPTRIE
                                     && noper_next >= tail
#endif
                                ){
                                    count = 1;
                                    first = cur;
                                    trietype = noper_trietype;
                                } else if (first) {
                                    count = 0;
                                    first = NULL;
                                    trietype = 0;
                                }
                            } 
                        } 
                        DEBUG_TRIE_COMPILE_r({
                            regprop(RExC_rx, RExC_mysv, cur, NULL, pRExC_state);
                            Perl_re_indentf( aTHX_  "- %s (%d) <SCAN FINISHED> ",
                              depth+1, SvPV_nolen_const( RExC_mysv ), REG_NODE_NUM(cur));
                            Perl_re_printf( aTHX_  "(First==%d, Last==%d, Cur==%d, tt==%s)\n",
                               REG_NODE_NUM(first), REG_NODE_NUM(last), REG_NODE_NUM(cur),
                               PL_reg_name[trietype]
                            );
                        });
                        if ( last && trietype ) {
                            if ( trietype != NOTHING ) {
                                made= make_trie( pRExC_state, startbranch,
                                                 first, scan, tail, count,
                                                 trietype, depth+1 );
#ifdef TRIE_STUDY_OPT
                                if ( ((made == MADE_EXACT_TRIE &&
                                     startbranch == first)
                                     || ( first_non_open == first )) &&
                                     depth==0 ) {
                                    flags |= SCF_TRIE_RESTUDY;
                                    if ( startbranch == first
                                         && scan >= tail )
                                    {
                                        RExC_seen &=~REG_TOP_LEVEL_BRANCHES_SEEN;
                                    }
                                }
#endif
                            } else {
                                if ( startbranch == first ) {
                                    regnode *opt;
                                    DEBUG_TRIE_COMPILE_r({
                                        regprop(RExC_rx, RExC_mysv, cur, NULL, pRExC_state);
                                        Perl_re_indentf( aTHX_  "- %s (%d) <NOTHING BRANCH SEQUENCE>\n",
                                          depth+1,
                                          SvPV_nolen_const( RExC_mysv ), REG_NODE_NUM(cur));
                                    });
                                    OP(startbranch)= NOTHING;
                                    NEXT_OFF(startbranch)= tail - startbranch;
                                    for ( opt= startbranch + 1; opt < tail ; opt++ )
                                        OP(opt)= OPTIMIZED;
                                }
                            }
                        } 
                    } 
                } 
	    }
	    else if ( code == BRANCHJ ) {  
		scan = NEXTOPER(NEXTOPER(scan));
	    } else			
		scan = NEXTOPER(scan);
	    continue;
        } else if (OP(scan) == SUSPEND || OP(scan) == GOSUB) {
            I32 paren = 0;
            regnode *start = NULL;
            regnode *end = NULL;
            U32 my_recursed_depth= recursed_depth;
            if (OP(scan) != SUSPEND) { 
                paren = ARG(scan);
                RExC_recurse[ARG2L(scan)] = scan;
                start = REGNODE_p(RExC_open_parens[paren]);
                end   = REGNODE_p(RExC_close_parens[paren]);
                if (
                    ( flags & SCF_IN_DEFINE )
                    ||
                    (
                        (is_inf_internal || is_inf || (data && data->flags & SF_IS_INF))
                        &&
                        ( (flags & (SCF_DO_STCLASS | SCF_DO_SUBSTR)) == 0 )
                    )
                ) {
                    scan= regnext(scan);
                    continue;
                }
                if (
                    !recursed_depth
                    ||
                    !PAREN_TEST(RExC_study_chunk_recursed + ((recursed_depth-1) * RExC_study_chunk_recursed_bytes), paren)
                ) {
                    if (!recursed_depth) {
                        Zero(RExC_study_chunk_recursed, RExC_study_chunk_recursed_bytes, U8);
                    } else {
                        Copy(RExC_study_chunk_recursed + ((recursed_depth-1) * RExC_study_chunk_recursed_bytes),
                             RExC_study_chunk_recursed + (recursed_depth * RExC_study_chunk_recursed_bytes),
                             RExC_study_chunk_recursed_bytes, U8);
                    }
                    DEBUG_STUDYDATA("gosub-set", data, depth, is_inf);
                    PAREN_SET(RExC_study_chunk_recursed + (recursed_depth * RExC_study_chunk_recursed_bytes), paren);
                    my_recursed_depth= recursed_depth + 1;
                } else {
                    DEBUG_STUDYDATA("gosub-inf", data, depth, is_inf);
                    if (flags & SCF_DO_SUBSTR) {
                        scan_commit(pRExC_state, data, minlenp, is_inf);
                        data->cur_is_floating = 1;
                    }
                    is_inf = is_inf_internal = 1;
                    if (flags & SCF_DO_STCLASS_OR) 
                        ssc_anything(data->start_class);
                    flags &= ~SCF_DO_STCLASS;
                    start= NULL; 
	        }
            } else {
	        paren = stopparen;
                start = scan + 2;
	        end = regnext(scan);
	    }
            if (start) {
                scan_frame *newframe;
                assert(end);
                if (!RExC_frame_last) {
                    Newxz(newframe, 1, scan_frame);
                    SAVEDESTRUCTOR_X(S_unwind_scan_frames, newframe);
                    RExC_frame_head= newframe;
                    RExC_frame_count++;
                } else if (!RExC_frame_last->next_frame) {
                    Newxz(newframe, 1, scan_frame);
                    RExC_frame_last->next_frame= newframe;
                    newframe->prev_frame= RExC_frame_last;
                    RExC_frame_count++;
                } else {
                    newframe= RExC_frame_last->next_frame;
                }
                RExC_frame_last= newframe;
                newframe->next_regnode = regnext(scan);
                newframe->last_regnode = last;
                newframe->stopparen = stopparen;
                newframe->prev_recursed_depth = recursed_depth;
                newframe->this_prev_frame= frame;
                newframe->in_gosub = (
                    (frame && frame->in_gosub) || OP(scan) == GOSUB
                );
                DEBUG_STUDYDATA("frame-new", data, depth, is_inf);
                DEBUG_PEEP("fnew", scan, depth, flags);
	        frame = newframe;
	        scan =  start;
	        stopparen = paren;
	        last = end;
                depth = depth + 1;
                recursed_depth= my_recursed_depth;
	        continue;
	    }
	}
	else if (   OP(scan) == EXACT
                 || OP(scan) == EXACT_ONLY8
                 || OP(scan) == EXACTL)
        {
	    SSize_t l = STR_LEN(scan);
	    UV uc;
            assert(l);
	    if (UTF) {
		const U8 * const s = (U8*)STRING(scan);
		uc = utf8_to_uvchr_buf(s, s + l, NULL);
		l = utf8_length(s, s + l);
	    } else {
		uc = *((U8*)STRING(scan));
	    }
	    min += l;
	    if (flags & SCF_DO_SUBSTR) { 
		if (data->last_end == -1) { 
		    data->last_start_min = data->pos_min;
 		    data->last_start_max = is_inf
 			? SSize_t_MAX : data->pos_min + data->pos_delta;
		}
		sv_catpvn(data->last_found, STRING(scan), STR_LEN(scan));
		if (UTF)
		    SvUTF8_on(data->last_found);
		{
		    SV * const sv = data->last_found;
		    MAGIC * const mg = SvUTF8(sv) && SvMAGICAL(sv) ?
			mg_find(sv, PERL_MAGIC_utf8) : NULL;
		    if (mg && mg->mg_len >= 0)
			mg->mg_len += utf8_length((U8*)STRING(scan),
                                              (U8*)STRING(scan)+STR_LEN(scan));
		}
		data->last_end = data->pos_min + l;
		data->pos_min += l; 
		data->flags &= ~SF_BEFORE_EOL;
	    }
	    if (flags & SCF_DO_STCLASS_AND) {
                ssc_cp_and(data->start_class, uc);
                ANYOF_FLAGS(data->start_class) &= ~SSC_MATCHES_EMPTY_STRING;
                ssc_clear_locale(data->start_class);
	    }
	    else if (flags & SCF_DO_STCLASS_OR) {
                ssc_add_cp(data->start_class, uc);
		ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
                ANYOF_FLAGS(data->start_class) &= ~SSC_MATCHES_EMPTY_STRING;
	    }
	    flags &= ~SCF_DO_STCLASS;
	}
        else if (PL_regkind[OP(scan)] == EXACT) {
	    SSize_t l = STR_LEN(scan);
            const U8 * s = (U8*)STRING(scan);
	    if (flags & SCF_DO_SUBSTR) {
		assert(data);
                scan_commit(pRExC_state, data, minlenp, is_inf);
	    }
	    if (UTF) {
		l = utf8_length(s, s + l);
	    }
	    if (unfolded_multi_char) {
                RExC_seen |= REG_UNFOLDED_MULTI_SEEN;
	    }
	    min += l - min_subtract;
            assert (min >= 0);
            delta += min_subtract;
	    if (flags & SCF_DO_SUBSTR) {
		data->pos_min += l - min_subtract;
		if (data->pos_min < 0) {
                    data->pos_min = 0;
                }
                data->pos_delta += min_subtract;
		if (min_subtract) {
		    data->cur_is_floating = 1; 
		}
	    }
            if (flags & SCF_DO_STCLASS) {
                SV* EXACTF_invlist = _make_exactf_invlist(pRExC_state, scan);
                assert(EXACTF_invlist);
                if (flags & SCF_DO_STCLASS_AND) {
                    if (OP(scan) != EXACTFL)
                        ssc_clear_locale(data->start_class);
                    ANYOF_FLAGS(data->start_class) &= ~SSC_MATCHES_EMPTY_STRING;
                    ANYOF_POSIXL_ZERO(data->start_class);
                    ssc_intersection(data->start_class, EXACTF_invlist, FALSE);
                }
                else {  
                    ssc_union(data->start_class, EXACTF_invlist, FALSE);
                    ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
                    ANYOF_FLAGS(data->start_class) &= ~SSC_MATCHES_EMPTY_STRING;
                }
                flags &= ~SCF_DO_STCLASS;
                SvREFCNT_dec(EXACTF_invlist);
            }
	}
	else if (REGNODE_VARIES(OP(scan))) {
	    SSize_t mincount, maxcount, minnext, deltanext, pos_before = 0;
	    I32 fl = 0, f = flags;
	    regnode * const oscan = scan;
	    regnode_ssc this_class;
	    regnode_ssc *oclass = NULL;
	    I32 next_is_eval = 0;
	    switch (PL_regkind[OP(scan)]) {
	    case WHILEM:		
		scan = NEXTOPER(scan);
		goto finish;
	    case PLUS:
		if (flags & (SCF_DO_SUBSTR | SCF_DO_STCLASS)) {
		    next = NEXTOPER(scan);
		    if (   OP(next) == EXACT
                        || OP(next) == EXACT_ONLY8
                        || OP(next) == EXACTL
                        || (flags & SCF_DO_STCLASS))
                    {
			mincount = 1;
			maxcount = REG_INFTY;
			next = regnext(scan);
			scan = NEXTOPER(scan);
			goto do_curly;
		    }
		}
		if (flags & SCF_DO_SUBSTR)
		    data->pos_min++;
		min++;
	    case STAR:
                next = NEXTOPER(scan);
                if (OP(next) == EXACTFU_S_EDGE && mutate_ok) {
                    OP(next) = EXACTFU;
                }
                if (     STR_LEN(next) == 1
                    &&   isALPHA_A(* STRING(next))
                    && (         OP(next) == EXACTFAA
                        || (     OP(next) == EXACTFU
                            && ! HAS_NONLATIN1_SIMPLE_FOLD_CLOSURE(* STRING(next))))
                    &&   mutate_ok
                ) {
                    U8 mask = ~ ('A' ^ 'a');
                    assert(isALPHA_A(* STRING(next)));
                    OP(next) = ANYOFM;
                    ARG_SET(next, *STRING(next) & mask);
                    FLAGS(next) = mask;
                }
		if (flags & SCF_DO_STCLASS) {
		    mincount = 0;
		    maxcount = REG_INFTY;
		    next = regnext(scan);
		    scan = NEXTOPER(scan);
		    goto do_curly;
		}
		if (flags & SCF_DO_SUBSTR) {
                    scan_commit(pRExC_state, data, minlenp, is_inf);
		    data->cur_is_floating = 1; 
		}
                is_inf = is_inf_internal = 1;
                scan = regnext(scan);
		goto optimize_curly_tail;
	    case CURLY:
	        if (stopparen>0 && (OP(scan)==CURLYN || OP(scan)==CURLYM)
	            && (scan->flags == stopparen))
		{
		    mincount = 1;
		    maxcount = 1;
		} else {
		    mincount = ARG1(scan);
		    maxcount = ARG2(scan);
		}
		next = regnext(scan);
		if (OP(scan) == CURLYX) {
		    I32 lp = (data ? *(data->last_closep) : 0);
		    scan->flags = ((lp <= (I32)U8_MAX) ? (U8)lp : U8_MAX);
		}
		scan = NEXTOPER(scan) + EXTRA_STEP_2ARGS;
		next_is_eval = (OP(scan) == EVAL);
	      do_curly:
		if (flags & SCF_DO_SUBSTR) {
                    if (mincount == 0)
                        scan_commit(pRExC_state, data, minlenp, is_inf);
		    pos_before = data->pos_min;
		}
		if (data) {
		    fl = data->flags;
		    data->flags &= ~(SF_HAS_PAR|SF_IN_PAR|SF_HAS_EVAL);
		    if (is_inf)
			data->flags |= SF_IS_INF;
		}
		if (flags & SCF_DO_STCLASS) {
		    ssc_init(pRExC_state, &this_class);
		    oclass = data->start_class;
		    data->start_class = &this_class;
		    f |= SCF_DO_STCLASS_AND;
		    f &= ~SCF_DO_STCLASS_OR;
		}
               if ((mincount > 1) || (maxcount > 1 && maxcount != REG_INFTY))
		    f &= ~SCF_WHILEM_VISITED_POS;
		minnext = study_chunk(pRExC_state, &scan, minlenp, &deltanext,
                                  last, data, stopparen, recursed_depth, NULL,
                                  (mincount == 0
                                   ? (f & ~SCF_DO_SUBSTR)
                                   : f)
                                  , depth+1, mutate_ok);
		if (flags & SCF_DO_STCLASS)
		    data->start_class = oclass;
		if (mincount == 0 || minnext == 0) {
		    if (flags & SCF_DO_STCLASS_OR) {
			ssc_or(pRExC_state, data->start_class, (regnode_charclass *) &this_class);
		    }
		    else if (flags & SCF_DO_STCLASS_AND) {
			INIT_AND_WITHP;
			StructCopy(data->start_class, and_withp, regnode_ssc);
			flags &= ~SCF_DO_STCLASS_AND;
			StructCopy(&this_class, data->start_class, regnode_ssc);
			flags |= SCF_DO_STCLASS_OR;
                        ANYOF_FLAGS(data->start_class)
                                                |= SSC_MATCHES_EMPTY_STRING;
		    }
		} else {		
		    if (flags & SCF_DO_STCLASS_OR) {
			ssc_or(pRExC_state, data->start_class, (regnode_charclass *) &this_class);
			ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
		    }
		    else if (flags & SCF_DO_STCLASS_AND)
			ssc_and(pRExC_state, data->start_class, (regnode_charclass *) &this_class);
		    flags &= ~SCF_DO_STCLASS;
		}
		if (!scan) 		
		    scan = next;
		if (((flags & (SCF_TRIE_DOING_RESTUDY|SCF_DO_SUBSTR))==SCF_DO_SUBSTR)
		    && (next_is_eval || !(mincount == 0 && maxcount == 1))
		    && (minnext == 0) && (deltanext == 0)
		    && data && !(data->flags & (SF_HAS_PAR|SF_IN_PAR))
                    && maxcount <= REG_INFTY/3) 
		{
		    _WARN_HELPER(RExC_precomp_end, packWARN(WARN_REGEXP),
                        Perl_ck_warner(aTHX_ packWARN(WARN_REGEXP),
                            "Quantifier unexpected on zero-length expression "
                            "in regex m/%" UTF8f "/",
			     UTF8fARG(UTF, RExC_precomp_end - RExC_precomp,
				  RExC_precomp)));
                }
                if ( ( minnext > 0 && mincount >= SSize_t_MAX / minnext )
                    || min >= SSize_t_MAX - minnext * mincount )
                {
                    FAIL("Regexp out of space");
                }
		min += minnext * mincount;
		is_inf_internal |= deltanext == SSize_t_MAX
                         || (maxcount == REG_INFTY && minnext + deltanext > 0);
		is_inf |= is_inf_internal;
                if (is_inf) {
		    delta = SSize_t_MAX;
                } else {
		    delta += (minnext + deltanext) * maxcount
                             - minnext * mincount;
                }
		if (  OP(oscan) == CURLYX && data
		      && data->flags & SF_IN_PAR
		      && !(data->flags & SF_HAS_EVAL)
		      && !deltanext && minnext == 1
                      && mutate_ok
                ) {
		    regnode *nxt = NEXTOPER(oscan) + EXTRA_STEP_2ARGS;
		    regnode * const nxt1 = nxt;
#ifdef DEBUGGING
		    regnode *nxt2;
#endif
		    nxt = regnext(nxt);
		    if (!REGNODE_SIMPLE(OP(nxt))
			&& !(PL_regkind[OP(nxt)] == EXACT
			     && STR_LEN(nxt) == 1))
			goto nogo;
#ifdef DEBUGGING
		    nxt2 = nxt;
#endif
		    nxt = regnext(nxt);
		    if (OP(nxt) != CLOSE)
			goto nogo;
		    if (RExC_open_parens) {
                        RExC_open_parens[ARG(nxt1)] = REGNODE_OFFSET(oscan);
                        RExC_close_parens[ARG(nxt1)] = REGNODE_OFFSET(nxt) + 2;
		    }
		    oscan->flags = (U8)ARG(nxt);
		    OP(oscan) = CURLYN;
		    OP(nxt1) = NOTHING;	
#ifdef DEBUGGING
		    OP(nxt1 + 1) = OPTIMIZED; 
		    NEXT_OFF(nxt1+ 1) = 0; 
		    NEXT_OFF(nxt2) = 0;	
		    OP(nxt) = OPTIMIZED;	
		    OP(nxt + 1) = OPTIMIZED; 
		    NEXT_OFF(nxt+ 1) = 0; 
#endif
		}
	      nogo:
		if (  OP(oscan) == CURLYX && data
		      && !(data->flags & SF_HAS_PAR)
		      && !(data->flags & SF_HAS_EVAL)
		      && !deltanext	
		      && minnext != 0	
                      && ! (RExC_seen & REG_UNFOLDED_MULTI_SEEN)
                      && mutate_ok
		) {
		    regnode *nxt = NEXTOPER(oscan) + EXTRA_STEP_2ARGS; 
		    regnode *nxt2;
		    OP(oscan) = CURLYM;
		    while ( (nxt2 = regnext(nxt)) 
			    && (OP(nxt2) != WHILEM))
			nxt = nxt2;
		    OP(nxt2)  = SUCCEED; 
		    if ((data->flags & SF_IN_PAR) && OP(nxt) == CLOSE) {
			regnode *nxt1 = NEXTOPER(oscan) + EXTRA_STEP_2ARGS; 
			oscan->flags = (U8)ARG(nxt);
			if (RExC_open_parens) {
                            RExC_open_parens[ARG(nxt1)] = REGNODE_OFFSET(oscan);
                            RExC_close_parens[ARG(nxt1)] = REGNODE_OFFSET(nxt2)
                                                         + 1;
			}
			OP(nxt1) = OPTIMIZED;	
			OP(nxt) = OPTIMIZED;	
#ifdef DEBUGGING
			OP(nxt1 + 1) = OPTIMIZED; 
			OP(nxt + 1) = OPTIMIZED; 
			NEXT_OFF(nxt1 + 1) = 0; 
			NEXT_OFF(nxt + 1) = 0; 
#endif
#if 0
			while ( nxt1 && (OP(nxt1) != WHILEM)) {
			    regnode *nnxt = regnext(nxt1);
			    if (nnxt == nxt) {
				if (reg_off_by_arg[OP(nxt1)])
				    ARG_SET(nxt1, nxt2 - nxt1);
				else if (nxt2 - nxt1 < U16_MAX)
				    NEXT_OFF(nxt1) = nxt2 - nxt1;
				else
				    OP(nxt) = NOTHING;	
			    }
			    nxt1 = nnxt;
			}
#endif
			study_chunk(pRExC_state, &nxt1, minlenp, &deltanext, nxt,
                                    NULL, stopparen, recursed_depth, NULL, 0,
                                    depth+1, mutate_ok);
		    }
		    else
			oscan->flags = 0;
		}
		else if ((OP(oscan) == CURLYX)
			 && (flags & SCF_WHILEM_VISITED_POS)
			 && (maxcount == REG_INFTY)
			 && data) {
		    regnode *nxt = oscan + NEXT_OFF(oscan);
		    if (OP(PREVOPER(nxt)) == NOTHING) 
			nxt += ARG(nxt);
                    nxt = PREVOPER(nxt);
                    if (nxt->flags & 0xf) {
                    } else if (++data->whilem_c < 16) {
                        assert(data->whilem_c <= RExC_whilem_seen);
                        nxt->flags = (U8)(data->whilem_c
                            | (RExC_whilem_seen << 4)); 
                    }
		}
		if (data && fl & (SF_HAS_PAR|SF_IN_PAR))
		    pars++;
		if (flags & SCF_DO_SUBSTR) {
		    SV *last_str = NULL;
                    STRLEN last_chrs = 0;
		    int counted = mincount != 0;
                    if (data->last_end > 0 && mincount != 0) { 
			SSize_t b = pos_before >= data->last_start_min
			    ? pos_before : data->last_start_min;
			STRLEN l;
			const char * const s = SvPV_const(data->last_found, l);
			SSize_t old = b - data->last_start_min;
                        assert(old >= 0);
			if (UTF)
			    old = utf8_hop_forward((U8*)s, old,
                                               (U8 *) SvEND(data->last_found))
                                - (U8*)s;
			l -= old;
			last_str = newSVpvn_utf8(s  + old, l, UTF);
                        last_chrs = UTF ? utf8_length((U8*)(s + old),
                                            (U8*)(s + old + l)) : l;
			if (deltanext == 0 && pos_before == b) {
			    if (mincount > 1) {
				SvGROW(last_str, (mincount * l) + 1);
				repeatcpy(SvPVX(last_str) + l,
					  SvPVX_const(last_str), l,
                                          mincount - 1);
				SvCUR_set(last_str, SvCUR(last_str) * mincount);
				SvCUR_set(data->last_found,
					  SvCUR(data->last_found) - l);
				sv_catsv(data->last_found, last_str);
				{
				    SV * sv = data->last_found;
				    MAGIC *mg =
					SvUTF8(sv) && SvMAGICAL(sv) ?
					mg_find(sv, PERL_MAGIC_utf8) : NULL;
				    if (mg && mg->mg_len >= 0)
					mg->mg_len += last_chrs * (mincount-1);
				}
                                last_chrs *= mincount;
				data->last_end += l * (mincount - 1);
			    }
			} else {
			    data->last_start_min += minnext * (mincount - 1);
			    data->last_start_max =
                              is_inf
                               ? SSize_t_MAX
			       : data->last_start_max +
                                 (maxcount - 1) * (minnext + data->pos_delta);
			}
		    }
		    data->pos_min += minnext * (mincount - counted);
#if 0
Perl_re_printf( aTHX_  "counted=%" UVuf " deltanext=%" UVuf
                              " SSize_t_MAX=%" UVuf " minnext=%" UVuf
                              " maxcount=%" UVuf " mincount=%" UVuf "\n",
    (UV)counted, (UV)deltanext, (UV)SSize_t_MAX, (UV)minnext, (UV)maxcount,
    (UV)mincount);
if (deltanext != SSize_t_MAX)
Perl_re_printf( aTHX_  "LHS=%" UVuf " RHS=%" UVuf "\n",
    (UV)(-counted * deltanext + (minnext + deltanext) * maxcount
          - minnext * mincount), (UV)(SSize_t_MAX - data->pos_delta));
#endif
		    if (deltanext == SSize_t_MAX
                        || -counted * deltanext + (minnext + deltanext) * maxcount - minnext * mincount >= SSize_t_MAX - data->pos_delta)
		        data->pos_delta = SSize_t_MAX;
		    else
		        data->pos_delta += - counted * deltanext +
			(minnext + deltanext) * maxcount - minnext * mincount;
		    if (mincount != maxcount) {
                        scan_commit(pRExC_state, data, minlenp, is_inf);
			if (mincount && last_str) {
			    SV * const sv = data->last_found;
			    MAGIC * const mg = SvUTF8(sv) && SvMAGICAL(sv) ?
				mg_find(sv, PERL_MAGIC_utf8) : NULL;
			    if (mg)
				mg->mg_len = -1;
			    sv_setsv(sv, last_str);
			    data->last_end = data->pos_min;
			    data->last_start_min = data->pos_min - last_chrs;
			    data->last_start_max = is_inf
				? SSize_t_MAX
				: data->pos_min + data->pos_delta - last_chrs;
			}
			data->cur_is_floating = 1; 
		    }
		    SvREFCNT_dec(last_str);
		}
		if (data && (fl & SF_HAS_EVAL))
		    data->flags |= SF_HAS_EVAL;
	      optimize_curly_tail:
		rck_elide_nothing(oscan);
		continue;
	    default:
#ifdef DEBUGGING
                Perl_croak(aTHX_ "panic: unexpected varying REx opcode %d",
                                                                    OP(scan));
#endif
            case REF:
            case CLUMP:
		if (flags & SCF_DO_SUBSTR) {
                    scan_commit(pRExC_state, data, minlenp, is_inf);
		    data->cur_is_floating = 1; 
		}
		is_inf = is_inf_internal = 1;
		if (flags & SCF_DO_STCLASS_OR) {
                    if (OP(scan) == CLUMP) {
                        ssc_match_all_cp(data->start_class);
                    }
                    else {
                        ssc_anything(data->start_class);
                    }
                }
		flags &= ~SCF_DO_STCLASS;
		break;
	    }
	}
	else if (OP(scan) == LNBREAK) {
	    if (flags & SCF_DO_STCLASS) {
    	        if (flags & SCF_DO_STCLASS_AND) {
                    ssc_intersection(data->start_class,
                                    PL_XPosix_ptrs[_CC_VERTSPACE], FALSE);
                    ssc_clear_locale(data->start_class);
                    ANYOF_FLAGS(data->start_class)
                                                &= ~SSC_MATCHES_EMPTY_STRING;
                }
                else if (flags & SCF_DO_STCLASS_OR) {
                    ssc_union(data->start_class,
                              PL_XPosix_ptrs[_CC_VERTSPACE],
                              FALSE);
		    ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
                    ANYOF_FLAGS(data->start_class)
                                                &= ~SSC_MATCHES_EMPTY_STRING;
                }
		flags &= ~SCF_DO_STCLASS;
            }
	    min++;
            if (delta != SSize_t_MAX)
                delta++;    
            if (flags & SCF_DO_SUBSTR) {
                scan_commit(pRExC_state, data, minlenp, is_inf);
    	        data->pos_min += 1;
                if (data->pos_delta != SSize_t_MAX) {
                    data->pos_delta += 1;
                }
		data->cur_is_floating = 1; 
    	    }
	}
	else if (REGNODE_SIMPLE(OP(scan))) {
	    if (flags & SCF_DO_SUBSTR) {
                scan_commit(pRExC_state, data, minlenp, is_inf);
		data->pos_min++;
	    }
	    min++;
	    if (flags & SCF_DO_STCLASS) {
                bool invert = 0;
                SV* my_invlist = NULL;
                U8 namedclass;
                ANYOF_FLAGS(data->start_class) &= ~SSC_MATCHES_EMPTY_STRING;
		switch (OP(scan)) {
		default:
#ifdef DEBUGGING
                   Perl_croak(aTHX_ "panic: unexpected simple REx opcode %d",
                                                                     OP(scan));
#endif
		case SANY:
		    if (flags & SCF_DO_STCLASS_OR) 
			ssc_match_all_cp(data->start_class);
		    break;
		case REG_ANY:
                    {
                        SV* REG_ANY_invlist = _new_invlist(2);
                        REG_ANY_invlist = add_cp_to_invlist(REG_ANY_invlist,
                                                            '\n');
                        if (flags & SCF_DO_STCLASS_OR) {
                            ssc_union(data->start_class,
                                      REG_ANY_invlist,
                                      TRUE 
                                      );
                        }
                        else if (flags & SCF_DO_STCLASS_AND) {
                            ssc_intersection(data->start_class,
                                             REG_ANY_invlist,
                                             TRUE  
                                             );
                            ssc_clear_locale(data->start_class);
                        }
                        SvREFCNT_dec_NN(REG_ANY_invlist);
		    }
		    break;
                case ANYOFD:
                case ANYOFL:
                case ANYOFPOSIXL:
                case ANYOFH:
                case ANYOF:
		    if (flags & SCF_DO_STCLASS_AND)
			ssc_and(pRExC_state, data->start_class,
                                (regnode_charclass *) scan);
		    else
			ssc_or(pRExC_state, data->start_class,
                                                          (regnode_charclass *) scan);
		    break;
                case NANYOFM:
                case ANYOFM:
                  {
                    SV* cp_list = get_ANYOFM_contents(scan);
                    if (flags & SCF_DO_STCLASS_OR) {
                        ssc_union(data->start_class, cp_list, invert);
                    }
                    else if (flags & SCF_DO_STCLASS_AND) {
                        ssc_intersection(data->start_class, cp_list, invert);
                    }
                    SvREFCNT_dec_NN(cp_list);
                    break;
                  }
		case NPOSIXL:
                    invert = 1;
		case POSIXL:
                    namedclass = classnum_to_namedclass(FLAGS(scan)) + invert;
                    if (flags & SCF_DO_STCLASS_AND) {
                        bool was_there = cBOOL(
                                          ANYOF_POSIXL_TEST(data->start_class,
                                                                 namedclass));
                        ANYOF_POSIXL_ZERO(data->start_class);
                        if (was_there) {    
                            ANYOF_POSIXL_SET(data->start_class, namedclass);
                        }
                        data->start_class->invlist
                                                = sv_2mortal(_new_invlist(0));
                    }
                    else {
                        int complement = namedclass + ((invert) ? -1 : 1);
                        assert(flags & SCF_DO_STCLASS_OR);
                        if (ANYOF_POSIXL_TEST(data->start_class, complement)) {
                            ssc_match_all_cp(data->start_class);
                            ANYOF_POSIXL_CLEAR(data->start_class, namedclass);
                            ANYOF_POSIXL_CLEAR(data->start_class, complement);
                        }
                        else {  
                            ANYOF_POSIXL_SET(data->start_class, namedclass);
                        }
                    }
                    break;
                case NPOSIXA:   
                    invert = 1;
		case POSIXA:
                    my_invlist = invlist_clone(PL_Posix_ptrs[FLAGS(scan)], NULL);
                    goto join_posix_and_ascii;
		case NPOSIXD:
		case NPOSIXU:
                    invert = 1;
		case POSIXD:
		case POSIXU:
                    my_invlist = invlist_clone(PL_XPosix_ptrs[FLAGS(scan)], NULL);
                    if (OP(scan) == NPOSIXD) {
                        _invlist_subtract(my_invlist, PL_UpperLatin1,
                                          &my_invlist);
                    }
                  join_posix_and_ascii:
                    if (flags & SCF_DO_STCLASS_AND) {
                        ssc_intersection(data->start_class, my_invlist, invert);
                        ssc_clear_locale(data->start_class);
                    }
                    else {
                        assert(flags & SCF_DO_STCLASS_OR);
                        ssc_union(data->start_class, my_invlist, invert);
                    }
                    SvREFCNT_dec(my_invlist);
		}
		if (flags & SCF_DO_STCLASS_OR)
		    ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
		flags &= ~SCF_DO_STCLASS;
	    }
	}
	else if (PL_regkind[OP(scan)] == EOL && flags & SCF_DO_SUBSTR) {
	    data->flags |= (OP(scan) == MEOL
			    ? SF_BEFORE_MEOL
			    : SF_BEFORE_SEOL);
            scan_commit(pRExC_state, data, minlenp, is_inf);
	}
	else if (  PL_regkind[OP(scan)] == BRANCHJ
		   && (scan->flags || data || (flags & SCF_DO_STCLASS))
		   && (OP(scan) == IFMATCH || OP(scan) == UNLESSM))
        {
            if ( !PERL_ENABLE_POSITIVE_ASSERTION_STUDY
                || OP(scan) == UNLESSM )
            {
                SSize_t deltanext, minnext, fake = 0;
                regnode *nscan;
                regnode_ssc intrnl;
                int f = 0;
                StructCopy(&zero_scan_data, &data_fake, scan_data_t);
                if (data) {
                    data_fake.whilem_c = data->whilem_c;
                    data_fake.last_closep = data->last_closep;
		}
                else
                    data_fake.last_closep = &fake;
		data_fake.pos_delta = delta;
                if ( flags & SCF_DO_STCLASS && !scan->flags
                     && OP(scan) == IFMATCH ) { 
                    ssc_init(pRExC_state, &intrnl);
                    data_fake.start_class = &intrnl;
                    f |= SCF_DO_STCLASS_AND;
		}
                if (flags & SCF_WHILEM_VISITED_POS)
                    f |= SCF_WHILEM_VISITED_POS;
                next = regnext(scan);
                nscan = NEXTOPER(NEXTOPER(scan));
                minnext = study_chunk(pRExC_state, &nscan, minlenp, &deltanext,
                                      last, &data_fake, stopparen,
                                      recursed_depth, NULL, f, depth+1,
                                      mutate_ok);
                if (scan->flags) {
                    if (   deltanext < 0
                        || deltanext > (I32) U8_MAX
                        || minnext > (I32)U8_MAX
                        || minnext + deltanext > (I32)U8_MAX)
                    {
			FAIL2("Lookbehind longer than %" UVuf " not implemented",
                              (UV)U8_MAX);
                    }
                    if (deltanext) {
                        scan->next_off = deltanext;
                        ckWARNexperimental(RExC_parse,
                            WARN_EXPERIMENTAL__VLB,
                            "Variable length lookbehind is experimental");
                    }
                    scan->flags = (U8)minnext + deltanext;
                }
                if (data) {
                    if (data_fake.flags & (SF_HAS_PAR|SF_IN_PAR))
                        pars++;
                    if (data_fake.flags & SF_HAS_EVAL)
                        data->flags |= SF_HAS_EVAL;
                    data->whilem_c = data_fake.whilem_c;
                }
                if (f & SCF_DO_STCLASS_AND) {
		    if (flags & SCF_DO_STCLASS_OR) {
			ssc_init(pRExC_state, data->start_class);
		    }  else {
			ssc_and(pRExC_state, data->start_class, (regnode_charclass *) &intrnl);
                        ANYOF_FLAGS(data->start_class)
                                                   |= SSC_MATCHES_EMPTY_STRING;
		    }
                }
	    }
#if PERL_ENABLE_POSITIVE_ASSERTION_STUDY
            else {
                SSize_t deltanext, fake = 0;
                regnode *nscan;
                regnode_ssc intrnl;
                int f = 0;
                SSize_t *minnextp;
                Newx( minnextp, 1, SSize_t );
                SAVEFREEPV(minnextp);
                if (data) {
                    StructCopy(data, &data_fake, scan_data_t);
                    if ((flags & SCF_DO_SUBSTR) && data->last_found) {
                        f |= SCF_DO_SUBSTR;
                        if (scan->flags)
                            scan_commit(pRExC_state, &data_fake, minlenp, is_inf);
                        data_fake.last_found=newSVsv(data->last_found);
                    }
                }
                else
                    data_fake.last_closep = &fake;
                data_fake.flags = 0;
                data_fake.substrs[0].flags = 0;
                data_fake.substrs[1].flags = 0;
		data_fake.pos_delta = delta;
                if (is_inf)
	            data_fake.flags |= SF_IS_INF;
                if ( flags & SCF_DO_STCLASS && !scan->flags
                     && OP(scan) == IFMATCH ) { 
                    ssc_init(pRExC_state, &intrnl);
                    data_fake.start_class = &intrnl;
                    f |= SCF_DO_STCLASS_AND;
                }
                if (flags & SCF_WHILEM_VISITED_POS)
                    f |= SCF_WHILEM_VISITED_POS;
                next = regnext(scan);
                nscan = NEXTOPER(NEXTOPER(scan));
                *minnextp = study_chunk(pRExC_state, &nscan, minnextp,
                                        &deltanext, last, &data_fake,
                                        stopparen, recursed_depth, NULL,
                                        f, depth+1, mutate_ok);
                if (scan->flags) {
                    assert(0);  
                    if (   deltanext < 0
                        || deltanext > (I32) U8_MAX
                        || *minnextp > (I32)U8_MAX
                        || *minnextp + deltanext > (I32)U8_MAX)
                    {
			FAIL2("Lookbehind longer than %" UVuf " not implemented",
                              (UV)U8_MAX);
                    }
                    if (deltanext) {
                        scan->next_off = deltanext;
                    }
                    scan->flags = (U8)*minnextp + deltanext;
                }
                *minnextp += min;
                if (f & SCF_DO_STCLASS_AND) {
                    ssc_and(pRExC_state, data->start_class, (regnode_charclass *) &intrnl);
                    ANYOF_FLAGS(data->start_class) |= SSC_MATCHES_EMPTY_STRING;
                }
                if (data) {
                    if (data_fake.flags & (SF_HAS_PAR|SF_IN_PAR))
                        pars++;
                    if (data_fake.flags & SF_HAS_EVAL)
                        data->flags |= SF_HAS_EVAL;
                    data->whilem_c = data_fake.whilem_c;
                    if ((flags & SCF_DO_SUBSTR) && data_fake.last_found) {
                        int i;
                        if (RExC_rx->minlen<*minnextp)
                            RExC_rx->minlen=*minnextp;
                        scan_commit(pRExC_state, &data_fake, minnextp, is_inf);
                        SvREFCNT_dec_NN(data_fake.last_found);
                        for (i = 0; i < 2; i++) {
                            if (data_fake.substrs[i].minlenp != minlenp) {
                                data->substrs[i].min_offset =
                                            data_fake.substrs[i].min_offset;
                                data->substrs[i].max_offset =
                                            data_fake.substrs[i].max_offset;
                                data->substrs[i].minlenp =
                                            data_fake.substrs[i].minlenp;
                                data->substrs[i].lookbehind += scan->flags;
                            }
                        }
                    }
                }
	    }
#endif
	}
	else if (OP(scan) == OPEN) {
	    if (stopparen != (I32)ARG(scan))
	        pars++;
	}
	else if (OP(scan) == CLOSE) {
	    if (stopparen == (I32)ARG(scan)) {
	        break;
	    }
	    if ((I32)ARG(scan) == is_par) {
		next = regnext(scan);
		if ( next && (OP(next) != WHILEM) && next < last)
		    is_par = 0;		
	    }
	    if (data)
		*(data->last_closep) = ARG(scan);
	}
	else if (OP(scan) == EVAL) {
		if (data)
		    data->flags |= SF_HAS_EVAL;
	}
	else if ( PL_regkind[OP(scan)] == ENDLIKE ) {
	    if (flags & SCF_DO_SUBSTR) {
                scan_commit(pRExC_state, data, minlenp, is_inf);
		flags &= ~SCF_DO_SUBSTR;
	    }
	    if (data && OP(scan)==ACCEPT) {
	        data->flags |= SCF_SEEN_ACCEPT;
	        if (stopmin > min)
	            stopmin = min;
	    }
	}
	else if (OP(scan) == LOGICAL && scan->flags == 2) 
	{
		if (flags & SCF_DO_SUBSTR) {
                    scan_commit(pRExC_state, data, minlenp, is_inf);
		    data->cur_is_floating = 1; 
		}
		is_inf = is_inf_internal = 1;
		if (flags & SCF_DO_STCLASS_OR) 
		    ssc_anything(data->start_class);
		flags &= ~SCF_DO_STCLASS;
	}
	else if (OP(scan) == GPOS) {
            if (!(RExC_rx->intflags & PREGf_GPOS_FLOAT) &&
	        !(delta || is_inf || (data && data->pos_delta)))
	    {
                if (!(RExC_rx->intflags & PREGf_ANCH) && (flags & SCF_DO_SUBSTR))
                    RExC_rx->intflags |= PREGf_ANCH_GPOS;
	        if (RExC_rx->gofs < (STRLEN)min)
		    RExC_rx->gofs = min;
            } else {
                RExC_rx->intflags |= PREGf_GPOS_FLOAT;
                RExC_rx->gofs = 0;
            }
	}
#ifdef TRIE_STUDY_OPT
#ifdef FULL_TRIE_STUDY
        else if (PL_regkind[OP(scan)] == TRIE) {
            regnode *trie_node= scan;
            regnode *tail= regnext(scan);
            reg_trie_data *trie = (reg_trie_data*)RExC_rxi->data->data[ ARG(scan) ];
            SSize_t max1 = 0, min1 = SSize_t_MAX;
            regnode_ssc accum;
            if (flags & SCF_DO_SUBSTR) { 
                scan_commit(pRExC_state, data, minlenp, is_inf);
            }
            if (flags & SCF_DO_STCLASS)
                ssc_init_zero(pRExC_state, &accum);
            if (!trie->jump) {
                min1= trie->minlen;
                max1= trie->maxlen;
            } else {
                const regnode *nextbranch= NULL;
                U32 word;
                for ( word=1 ; word <= trie->wordcount ; word++)
                {
                    SSize_t deltanext=0, minnext=0, f = 0, fake;
                    regnode_ssc this_class;
                    StructCopy(&zero_scan_data, &data_fake, scan_data_t);
                    if (data) {
                        data_fake.whilem_c = data->whilem_c;
                        data_fake.last_closep = data->last_closep;
                    }
                    else
                        data_fake.last_closep = &fake;
		    data_fake.pos_delta = delta;
                    if (flags & SCF_DO_STCLASS) {
                        ssc_init(pRExC_state, &this_class);
                        data_fake.start_class = &this_class;
                        f = SCF_DO_STCLASS_AND;
                    }
                    if (flags & SCF_WHILEM_VISITED_POS)
                        f |= SCF_WHILEM_VISITED_POS;
                    if (trie->jump[word]) {
                        if (!nextbranch)
                            nextbranch = trie_node + trie->jump[0];
                        scan= trie_node + trie->jump[word];
                        minnext = study_chunk(pRExC_state, &scan, minlenp,
                            &deltanext, (regnode *)nextbranch, &data_fake,
                            stopparen, recursed_depth, NULL, f, depth+1,
                            mutate_ok);
                    }
                    if (nextbranch && PL_regkind[OP(nextbranch)]==BRANCH)
                        nextbranch= regnext((regnode*)nextbranch);
                    if (min1 > (SSize_t)(minnext + trie->minlen))
                        min1 = minnext + trie->minlen;
                    if (deltanext == SSize_t_MAX) {
                        is_inf = is_inf_internal = 1;
                        max1 = SSize_t_MAX;
                    } else if (max1 < (SSize_t)(minnext + deltanext + trie->maxlen))
                        max1 = minnext + deltanext + trie->maxlen;
                    if (data_fake.flags & (SF_HAS_PAR|SF_IN_PAR))
                        pars++;
                    if (data_fake.flags & SCF_SEEN_ACCEPT) {
                        if ( stopmin > min + min1)
	                    stopmin = min + min1;
	                flags &= ~SCF_DO_SUBSTR;
	                if (data)
	                    data->flags |= SCF_SEEN_ACCEPT;
	            }
                    if (data) {
                        if (data_fake.flags & SF_HAS_EVAL)
                            data->flags |= SF_HAS_EVAL;
                        data->whilem_c = data_fake.whilem_c;
                    }
                    if (flags & SCF_DO_STCLASS)
                        ssc_or(pRExC_state, &accum, (regnode_charclass *) &this_class);
                }
            }
            if (flags & SCF_DO_SUBSTR) {
                data->pos_min += min1;
                data->pos_delta += max1 - min1;
                if (max1 != min1 || is_inf)
                    data->cur_is_floating = 1; 
            }
            min += min1;
            if (delta != SSize_t_MAX) {
                if (SSize_t_MAX - (max1 - min1) >= delta)
                    delta += max1 - min1;
                else
                    delta = SSize_t_MAX;
            }
            if (flags & SCF_DO_STCLASS_OR) {
                ssc_or(pRExC_state, data->start_class, (regnode_charclass *) &accum);
                if (min1) {
                    ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
                    flags &= ~SCF_DO_STCLASS;
                }
            }
            else if (flags & SCF_DO_STCLASS_AND) {
                if (min1) {
                    ssc_and(pRExC_state, data->start_class, (regnode_charclass *) &accum);
                    flags &= ~SCF_DO_STCLASS;
                }
                else {
		    INIT_AND_WITHP;
                    StructCopy(data->start_class, and_withp, regnode_ssc);
                    flags &= ~SCF_DO_STCLASS_AND;
                    StructCopy(&accum, data->start_class, regnode_ssc);
                    flags |= SCF_DO_STCLASS_OR;
                }
            }
            scan= tail;
            continue;
        }
#else
	else if (PL_regkind[OP(scan)] == TRIE) {
	    reg_trie_data *trie = (reg_trie_data*)RExC_rxi->data->data[ ARG(scan) ];
	    U8*bang=NULL;
	    min += trie->minlen;
	    delta += (trie->maxlen - trie->minlen);
	    flags &= ~SCF_DO_STCLASS; 
            if (flags & SCF_DO_SUBSTR) {
                scan_commit(pRExC_state, data, minlenp, is_inf);
    	        data->pos_min += trie->minlen;
    	        data->pos_delta += (trie->maxlen - trie->minlen);
		if (trie->maxlen != trie->minlen)
		    data->cur_is_floating = 1; 
    	    }
    	    if (trie->jump) 
               flags &= ~SCF_DO_SUBSTR;
	}
#endif 
#endif 
	scan = regnext(scan);
    }
  finish:
    if (frame) {
        depth = depth - 1;
        DEBUG_STUDYDATA("frame-end", data, depth, is_inf);
        DEBUG_PEEP("fend", scan, depth, flags);
        last = frame->last_regnode;
        scan = frame->next_regnode;
        stopparen = frame->stopparen;
        recursed_depth = frame->prev_recursed_depth;
        RExC_frame_last = frame->prev_frame;
        frame = frame->this_prev_frame;
        goto fake_study_recurse;
    }
    assert(!frame);
    DEBUG_STUDYDATA("pre-fin", data, depth, is_inf);
    *scanp = scan;
    *deltap = is_inf_internal ? SSize_t_MAX : delta;
    if (flags & SCF_DO_SUBSTR && is_inf)
	data->pos_delta = SSize_t_MAX - data->pos_min;
    if (is_par > (I32)U8_MAX)
	is_par = 0;
    if (is_par && pars==1 && data) {
	data->flags |= SF_IN_PAR;
	data->flags &= ~SF_HAS_PAR;
    }
    else if (pars && data) {
	data->flags |= SF_HAS_PAR;
	data->flags &= ~SF_IN_PAR;
    }
    if (flags & SCF_DO_STCLASS_OR)
	ssc_and(pRExC_state, data->start_class, (regnode_charclass *) and_withp);
    if (flags & SCF_TRIE_RESTUDY)
        data->flags |= 	SCF_TRIE_RESTUDY;
    DEBUG_STUDYDATA("post-fin", data, depth, is_inf);
    {
        SSize_t final_minlen= min < stopmin ? min : stopmin;
        if (!(RExC_seen & REG_UNBOUNDED_QUANTIFIER_SEEN)) {
            if (final_minlen > SSize_t_MAX - delta)
                RExC_maxlen = SSize_t_MAX;
            else if (RExC_maxlen < final_minlen + delta)
                RExC_maxlen = final_minlen + delta;
        }
        return final_minlen;
    }
    NOT_REACHED;