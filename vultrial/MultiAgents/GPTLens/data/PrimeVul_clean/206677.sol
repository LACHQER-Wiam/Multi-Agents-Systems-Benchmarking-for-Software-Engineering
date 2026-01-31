unix_expandpath(
    garray_T	*gap,
    char_u	*path,
    int		wildoff,
    int		flags,		
    int		didstar)	
{
    char_u	*buf;
    char_u	*path_end;
    char_u	*p, *s, *e;
    int		start_len = gap->ga_len;
    char_u	*pat;
    regmatch_T	regmatch;
    int		starts_with_dot;
    int		matches;
    int		len;
    int		starstar = FALSE;
    static int	stardepth = 0;	    
    DIR		*dirp;
    struct dirent *dp;
    if (stardepth > 0)
    {
	ui_breakcheck();
	if (got_int)
	    return 0;
    }
    buf = alloc(STRLEN(path) + BASENAMELEN + 5);
    if (buf == NULL)
	return 0;
    p = buf;
    s = buf;
    e = NULL;
    path_end = path;
    while (*path_end != NUL)
    {
	if (path_end >= path + wildoff && rem_backslash(path_end))
	    *p++ = *path_end++;
	else if (*path_end == '/')
	{
	    if (e != NULL)
		break;
	    s = p + 1;
	}
	else if (path_end >= path + wildoff
			 && (vim_strchr((char_u *)"*?[{~$", *path_end) != NULL
			     || (!p_fic && (flags & EW_ICASE)
					     && isalpha(PTR2CHAR(path_end)))))
	    e = p;
	if (has_mbyte)
	{
	    len = (*mb_ptr2len)(path_end);
	    STRNCPY(p, path_end, len);
	    p += len;
	    path_end += len;
	}
	else
	    *p++ = *path_end++;
    }
    e = p;
    *e = NUL;
    for (p = buf + wildoff; p < s; ++p)
	if (rem_backslash(p))
	{
	    STRMOVE(p, p + 1);
	    --e;
	    --s;
	}
    for (p = s; p < e; ++p)
	if (p[0] == '*' && p[1] == '*')
	    starstar = TRUE;
    starts_with_dot = *s == '.';
    pat = file_pat_to_reg_pat(s, e, NULL, FALSE);
    if (pat == NULL)
    {
	vim_free(buf);
	return 0;
    }
    if (flags & EW_ICASE)
	regmatch.rm_ic = TRUE;		
    else
	regmatch.rm_ic = p_fic;	
    if (flags & (EW_NOERROR | EW_NOTWILD))
	++emsg_silent;
    regmatch.regprog = vim_regcomp(pat, RE_MAGIC);
    if (flags & (EW_NOERROR | EW_NOTWILD))
	--emsg_silent;
    vim_free(pat);
    if (regmatch.regprog == NULL && (flags & EW_NOTWILD) == 0)
    {
	vim_free(buf);
	return 0;
    }
    if (!didstar && stardepth < 100 && starstar && e - s == 2
							  && *path_end == '/')
    {
	STRCPY(s, path_end + 1);
	++stardepth;
	(void)unix_expandpath(gap, buf, (int)(s - buf), flags, TRUE);
	--stardepth;
    }
    *s = NUL;
    dirp = opendir(*buf == NUL ? "." : (char *)buf);
    if (dirp != NULL)
    {
	for (;;)
	{
	    dp = readdir(dirp);
	    if (dp == NULL)
		break;
	    if ((dp->d_name[0] != '.' || starts_with_dot
			|| ((flags & EW_DODOT)
			    && dp->d_name[1] != NUL
			    && (dp->d_name[1] != '.' || dp->d_name[2] != NUL)))
		 && ((regmatch.regprog != NULL && vim_regexec(&regmatch,
					     (char_u *)dp->d_name, (colnr_T)0))
		   || ((flags & EW_NOTWILD)
		     && fnamencmp(path + (s - buf), dp->d_name, e - s) == 0)))
	    {
		STRCPY(s, dp->d_name);
		len = STRLEN(buf);
		if (starstar && stardepth < 100)
		{
		    STRCPY(buf + len, "/**");
		    STRCPY(buf + len + 3, path_end);
		    ++stardepth;
		    (void)unix_expandpath(gap, buf, len + 1, flags, TRUE);
		    --stardepth;
		}
		STRCPY(buf + len, path_end);
		if (mch_has_exp_wildcard(path_end)) 
		{
		    (void)unix_expandpath(gap, buf, len + 1, flags, FALSE);
		}
		else
		{
		    stat_T  sb;
		    if (*path_end != NUL)
			backslash_halve(buf + len + 1);
		    if ((flags & EW_ALLLINKS) ? mch_lstat((char *)buf, &sb) >= 0
						      : mch_getperm(buf) >= 0)
		    {
#ifdef MACOS_CONVERT
			size_t precomp_len = STRLEN(buf)+1;
			char_u *precomp_buf =
			    mac_precompose_path(buf, precomp_len, &precomp_len);
			if (precomp_buf)
			{
			    mch_memmove(buf, precomp_buf, precomp_len);
			    vim_free(precomp_buf);
			}
#endif
			addfile(gap, buf, flags);
		    }
		}
	    }
	}
	closedir(dirp);
    }
    vim_free(buf);
    vim_regfree(regmatch.regprog);
    matches = gap->ga_len - start_len;
    if (matches > 0)
	qsort(((char_u **)gap->ga_data) + start_len, matches,
						   sizeof(char_u *), pstrcmp);
    return matches;
}