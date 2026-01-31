static pj_xml_node *xml_parse_node( pj_pool_t *pool, pj_scanner *scanner)
{
    pj_xml_node *node;
    pj_str_t end_name;
    PJ_CHECK_STACK();
    if (*scanner->curptr != '<')
	on_syntax_error(scanner);
    if (*scanner->curptr == '<' && *(scanner->curptr+1) == '?') {
	pj_scan_advance_n(scanner, 2, PJ_FALSE);
	for (;;) {
	    pj_str_t dummy;
	    pj_scan_get_until_ch(scanner, '?', &dummy);
	    if (*scanner->curptr=='?' && *(scanner->curptr+1)=='>') {
		pj_scan_advance_n(scanner, 2, PJ_TRUE);
		break;
	    } else {
		pj_scan_advance_n(scanner, 1, PJ_FALSE);
	    }
	}
	return xml_parse_node(pool, scanner);
    }
    if (pj_scan_strcmp(scanner, "<!", 2) == 0) {
	pj_scan_advance_n(scanner, 2, PJ_FALSE);
	for (;;) {
	    pj_str_t dummy;
	    pj_scan_get_until_ch(scanner, '>', &dummy);
	    if (pj_scan_strcmp(scanner, ">", 1) == 0) {
		pj_scan_advance_n(scanner, 1, PJ_TRUE);
		break;
	    } else {
		pj_scan_advance_n(scanner, 1, PJ_FALSE);
	    }
	}
	return xml_parse_node(pool, scanner);
    }
    node = alloc_node(pool);
    pj_scan_get_char(scanner);
    pj_scan_get_until_chr( scanner, " />\t\r\n", &node->name);
    while (*scanner->curptr != '>' && *scanner->curptr != '/') {
	pj_xml_attr *attr = alloc_attr(pool);
	pj_scan_get_until_chr( scanner, "=> \t\r\n", &attr->name);
	if (*scanner->curptr == '=') {
	    pj_scan_get_char( scanner );
            pj_scan_get_quotes(scanner, "\"'", "\"'", 2, &attr->value);
	    ++attr->value.ptr;
	    attr->value.slen -= 2;
	}
	pj_list_push_back( &node->attr_head, attr );
    }
    if (*scanner->curptr == '/') {
	pj_scan_get_char(scanner);
	if (pj_scan_get_char(scanner) != '>')
	    on_syntax_error(scanner);
	return node;
    }
    if (pj_scan_get_char(scanner) != '>')
	on_syntax_error(scanner);
    while (*scanner->curptr == '<' && *(scanner->curptr+1) != '/'
				   && *(scanner->curptr+1) != '!')
    {
	pj_xml_node *sub_node = xml_parse_node(pool, scanner);
	pj_list_push_back( &node->node_head, sub_node );
    }
    if (!pj_scan_is_eof(scanner) && *scanner->curptr != '<') {
	pj_scan_get_until_ch(scanner, '<', &node->content);
    }
    if (*scanner->curptr == '<' && *(scanner->curptr+1) == '!' &&
	pj_scan_strcmp(scanner, "<![CDATA[", 9) == 0)
    {
	pj_scan_advance_n(scanner, 9, PJ_FALSE);
	pj_scan_get_until_ch(scanner, ']', &node->content);
	while (pj_scan_strcmp(scanner, "]]>", 3)) {
	    pj_str_t dummy;
	    pj_scan_advance_n(scanner, 1, PJ_FALSE);
	    pj_scan_get_until_ch(scanner, ']', &dummy);
	}
	node->content.slen = scanner->curptr - node->content.ptr;
	pj_scan_advance_n(scanner, 3, PJ_TRUE);
    }
    if (pj_scan_get_char(scanner) != '<' || pj_scan_get_char(scanner) != '/')
	on_syntax_error(scanner);
    pj_scan_get_until_chr(scanner, " \t>", &end_name);
    if (pj_stricmp(&node->name, &end_name) != 0)
	on_syntax_error(scanner);
    if (pj_scan_get_char(scanner) != '>')
	on_syntax_error(scanner);
    return node;
}