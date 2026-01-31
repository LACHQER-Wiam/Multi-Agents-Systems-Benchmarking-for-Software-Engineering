cmdline_insert_reg(int *gotesc UNUSED)
{
    int		i;
    int		c;
    int		save_new_cmdpos = new_cmdpos;
#ifdef USE_ON_FLY_SCROLL
    dont_scroll = TRUE;	
#endif
    putcmdline('"', TRUE);
    ++no_mapping;
    ++allow_keys;
    i = c = plain_vgetc();	
    if (i == Ctrl_O)
	i = Ctrl_R;		
    if (i == Ctrl_R)
	c = plain_vgetc();	
    extra_char = NUL;
    --no_mapping;
    --allow_keys;
#ifdef FEAT_EVAL
    new_cmdpos = -1;
    if (c == '=')
    {
	if (ccline.cmdfirstc == '='  
		|| cmdline_star > 0) 
	{
	    beep_flush();
	    c = ESC;
	}
	else
	    c = get_expr_register();
    }
#endif
    if (c != ESC)	    
    {
	cmdline_paste(c, i == Ctrl_R, FALSE);
#ifdef FEAT_EVAL
	if (aborting())
	{
	    *gotesc = TRUE;  
	    return GOTO_NORMAL_MODE;
	}
#endif
	KeyTyped = FALSE;	
#ifdef FEAT_EVAL
	if (new_cmdpos >= 0)
	{
	    if (new_cmdpos > ccline.cmdlen)
		ccline.cmdpos = ccline.cmdlen;
	    else
		ccline.cmdpos = new_cmdpos;
	}
#endif
    }
    new_cmdpos = save_new_cmdpos;
    redrawcmd();
    return CMDLINE_NOT_CHANGED;
}