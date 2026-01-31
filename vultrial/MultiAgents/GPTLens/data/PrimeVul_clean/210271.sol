sug_filltree(spellinfo_T *spin, slang_T *slang)
{
    char_u	*byts;
    idx_T	*idxs;
    int		depth;
    idx_T	arridx[MAXWLEN];
    int		curi[MAXWLEN];
    char_u	tword[MAXWLEN];
    char_u	tsalword[MAXWLEN];
    int		c;
    idx_T	n;
    unsigned	words_done = 0;
    int		wordcount[MAXWLEN];
    spin->si_foldroot = wordtree_alloc(spin);
    if (spin->si_foldroot == NULL)
	return FAIL;
    spin->si_sugtree = TRUE;
    byts = slang->sl_fbyts;
    idxs = slang->sl_fidxs;
    arridx[0] = 0;
    curi[0] = 1;
    wordcount[0] = 0;
    depth = 0;
    while (depth >= 0 && !got_int)
    {
	if (curi[depth] > byts[arridx[depth]])
	{
	    idxs[arridx[depth]] = wordcount[depth];
	    if (depth > 0)
		wordcount[depth - 1] += wordcount[depth];
	    --depth;
	    line_breakcheck();
	}
	else
	{
	    n = arridx[depth] + curi[depth];
	    ++curi[depth];
	    c = byts[n];
	    if (c == 0)
	    {
		tword[depth] = NUL;
		spell_soundfold(slang, tword, TRUE, tsalword);
		if (tree_add_word(spin, tsalword, spin->si_foldroot,
				words_done >> 16, words_done & 0xffff,
							   0) == FAIL)
		    return FAIL;
		++words_done;
		++wordcount[depth];
		spin->si_blocks_cnt = 0;
		while (n + 1 < slang->sl_fbyts_len && byts[n + 1] == 0)
		{
		    ++n;
		    ++curi[depth];
		}
	    }
	    else
	    {
		tword[depth++] = c;
		arridx[depth] = idxs[n];
		curi[depth] = 1;
		wordcount[depth] = 0;
	    }
	}
    }
    smsg(_("Total number of words: %d"), words_done);
    return OK;
}