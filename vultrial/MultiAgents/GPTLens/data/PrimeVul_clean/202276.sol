block_insert(
    oparg_T		*oap,
    char_u		*s,
    int			b_insert,
    struct block_def	*bdp)
{
    int		ts_val;
    int		count = 0;	
    int		spaces = 0;	
    colnr_T	offset;		
    colnr_T	startcol;	
    unsigned	s_len;		
    char_u	*newp, *oldp;	
    linenr_T	lnum;		
    int		oldstate = State;
    State = INSERT;		
    s_len = (unsigned)STRLEN(s);
    for (lnum = oap->start.lnum + 1; lnum <= oap->end.lnum; lnum++)
    {
	block_prep(oap, bdp, lnum, TRUE);
	if (bdp->is_short && b_insert)
	    continue;	
	oldp = ml_get(lnum);
	if (b_insert)
	{
	    ts_val = bdp->start_char_vcols;
	    spaces = bdp->startspaces;
	    if (spaces != 0)
		count = ts_val - 1; 
	    offset = bdp->textcol;
	}
	else 
	{
	    ts_val = bdp->end_char_vcols;
	    if (!bdp->is_short) 
	    {
		spaces = (bdp->endspaces ? ts_val - bdp->endspaces : 0);
		if (spaces != 0)
		    count = ts_val - 1; 
		offset = bdp->textcol + bdp->textlen - (spaces != 0);
	    }
	    else 
	    {
		if (!bdp->is_MAX)
		    spaces = (oap->end_vcol - bdp->end_vcol) + 1;
		count = spaces;
		offset = bdp->textcol + bdp->textlen;
	    }
	}
	if (has_mbyte && spaces > 0)
	{
	    int off;
	    if (b_insert)
	    {
		off = (*mb_head_off)(oldp, oldp + offset + spaces);
		spaces -= off;
		count -= off;
	    }
	    else
	    {
		off = (*mb_head_off)(oldp, oldp + offset);
		offset -= off;
	    }
	}
	if (spaces < 0)  
	    spaces = 0;
	newp = alloc(STRLEN(oldp) + spaces + s_len
		    + (spaces > 0 && !bdp->is_short ? ts_val - spaces : 0)
								  + count + 1);
	if (newp == NULL)
	    continue;
	mch_memmove(newp, oldp, (size_t)offset);
	oldp += offset;
	vim_memset(newp + offset, ' ', (size_t)spaces);
	startcol = offset + spaces;
	mch_memmove(newp + startcol, s, (size_t)s_len);
	offset += s_len;
	if (spaces > 0 && !bdp->is_short)
	{
	    if (*oldp == TAB)
	    {
		vim_memset(newp + offset + spaces, ' ',
						    (size_t)(ts_val - spaces));
		oldp++;
		count++;
	    }
	    else
		count = spaces;
	}
	if (spaces > 0)
	    offset += count;
	STRMOVE(newp + offset, oldp);
	ml_replace(lnum, newp, FALSE);
	if (b_insert)
	    inserted_bytes(lnum, startcol, s_len);
	if (lnum == oap->end.lnum)
	{
	    curbuf->b_op_end.lnum = oap->end.lnum;
	    curbuf->b_op_end.col = offset;
	}
    } 
    changed_lines(oap->start.lnum + 1, 0, oap->end.lnum + 1, 0L);
    State = oldstate;
}