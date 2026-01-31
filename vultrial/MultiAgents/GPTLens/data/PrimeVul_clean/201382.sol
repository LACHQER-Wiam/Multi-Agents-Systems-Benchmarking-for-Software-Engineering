drill_parse_T_code(gerb_file_t *fd, drill_state_t *state,
			gerbv_image_t *image, ssize_t file_line)
{
    int tool_num;
    gboolean done = FALSE;
    int temp;
    double size;
    gerbv_drill_stats_t *stats = image->drill_stats;
    gerbv_aperture_t *apert;
    gchar *tmps;
    gchar *string;
    dprintf("---> entering %s()...\n", __FUNCTION__);
    temp = gerb_fgetc(fd);
    dprintf("  Found a char '%s' (0x%02x) after the T\n",
	    gerbv_escape_char(temp), temp);
    if((temp == 'C') && ((fd->ptr + 2) < fd->datalen)){
    	if(gerb_fgetc(fd) == 'S'){
    	    if (gerb_fgetc(fd) == 'T' ){
    	  	fd->ptr -= 4;
    	  	tmps = get_line(fd++);
    	  	gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_NOTE, -1,
			_("Tool change stop switch found \"%s\" "
			    "at line %ld in file \"%s\""),
			tmps, file_line, fd->filename);
	  	g_free (tmps);
	  	return -1;
	    }
	    gerb_ungetc(fd);
	}
	gerb_ungetc(fd);
    }
    if( !(isdigit(temp) != 0 || temp == '+' || temp =='-') ) {
	if(temp != EOF) {
	    gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_ERROR, -1,
		   _("OrCAD bug: Junk text found in place of tool definition"));
	    tmps = get_line(fd);
	    gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_WARNING, -1,
		    _("Junk text \"%s\" "
			"at line %ld in file \"%s\""),
		    tmps, file_line, fd->filename);
	    g_free (tmps);
	    gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_WARNING, -1,
				  _("Ignoring junk text"));
	}
	return -1;
    }
    gerb_ungetc(fd);
    tool_num = (int) gerb_fgetint(fd, NULL);
    dprintf ("  Handling tool T%d at line %ld\n", tool_num, file_line);
    if (tool_num == 0) 
	return tool_num; 
    if (tool_num < TOOL_MIN || tool_num >= TOOL_MAX) {
	gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_ERROR, -1,
		_("Out of bounds drill number %d "
		    "at line %ld in file \"%s\""),
		tool_num, file_line, fd->filename);
    }
    state->current_tool = tool_num;
    apert = image->aperture[tool_num];
    temp = gerb_fgetc(fd);
    while (!done) {
	switch((char)temp) {
	case 'C':
	    size = read_double(fd, state->header_number_format, GERBV_OMIT_ZEROS_TRAILING, state->decimals);
	    dprintf ("  Read a size of %g\n", size);
	    if (state->unit == GERBV_UNIT_MM) {
		size /= 25.4;
	    } else if(size >= 4.0) {
		gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_ERROR, -1,
			_("Read a drill of diameter %g inches "
			    "at line %ld in file \"%s\""),
			    size, file_line, fd->filename);
		gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_WARNING, -1,
			_("Assuming units are mils"));
		size /= 1000.0;
	    }
	    if (size <= 0. || size >= 10000.) {
		gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_ERROR, -1,
			_("Unreasonable drill size %g found for drill %d "
			    "at line %ld in file \"%s\""),
			    size, tool_num, file_line, fd->filename);
	    } else {
		if (apert != NULL) {
		    if (apert->parameter[0] != size
		    ||  apert->type != GERBV_APTYPE_CIRCLE
		    ||  apert->nuf_parameters != 1
		    ||  apert->unit != GERBV_UNIT_INCH) {
			gerbv_stats_printf(stats->error_list,
				GERBV_MESSAGE_ERROR, -1,
				_("Found redefinition of drill %d "
				"at line %ld in file \"%s\""),
				tool_num, file_line, fd->filename);
		    }
		} else {
		    apert = image->aperture[tool_num] =
						g_new0(gerbv_aperture_t, 1);
		    if (apert == NULL)
			GERB_FATAL_ERROR("malloc tool failed in %s()",
					__FUNCTION__);
		    apert->parameter[0] = size;
		    apert->type = GERBV_APTYPE_CIRCLE;
		    apert->nuf_parameters = 1;
		    apert->unit = GERBV_UNIT_INCH;
		}
	    }
	    stats = image->drill_stats;
	    string = g_strdup_printf("%s", (state->unit == GERBV_UNIT_MM ? _("mm") : _("inch")));
	    drill_stats_add_to_drill_list(stats->drill_list, 
					  tool_num, 
					  state->unit == GERBV_UNIT_MM ? size*25.4 : size, 
					  string);
	    g_free(string);
	    break;
	case 'F':
	case 'S' :
	    gerb_fgetint(fd, NULL);
	    break;
	default:
	    gerb_ungetc(fd);
	    done = TRUE;
	    break;
	}  
	temp = gerb_fgetc(fd);
	if (EOF == temp) {
	    gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_ERROR, -1,
		    _("Unexpected EOF encountered in header of "
			"drill file \"%s\""), fd->filename);
	if ('\n' == temp || '\r' == temp)
	    gerb_ungetc(fd);
	}
    }     
    if (apert == NULL) {
        double dia;
	apert = image->aperture[tool_num] = g_new0(gerbv_aperture_t, 1);
	if (apert == NULL)
	    GERB_FATAL_ERROR("malloc tool failed in %s()", __FUNCTION__);
        dia = gerbv_get_tool_diameter(tool_num);
        if (dia <= 0) {
            dia = (double)(16 + 8 * tool_num) / 1000;
            if (tool_num != 0) {
		gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_ERROR, -1,
			_("Tool %02d used without being defined "
			    "at line %ld in file \"%s\""),
			tool_num, file_line, fd->filename);
		gerbv_stats_printf(stats->error_list, GERBV_MESSAGE_WARNING, -1,
			_("Setting a default size of %g\""), dia);
            }
	}
	apert->type = GERBV_APTYPE_CIRCLE;
	apert->nuf_parameters = 1;
	apert->parameter[0] = dia;
	if (tool_num != 0) {  
	    stats = image->drill_stats;
	    string = g_strdup_printf("%s", 
				     (state->unit == GERBV_UNIT_MM ? _("mm") : _("inch")));
	    drill_stats_add_to_drill_list(stats->drill_list, 
					  tool_num, 
					  state->unit == GERBV_UNIT_MM ? dia*25.4 : dia,
					  string);
	    g_free(string);
	}
    } 	
    dprintf("<----  ...leaving %s()\n", __FUNCTION__);
    return tool_num;
}