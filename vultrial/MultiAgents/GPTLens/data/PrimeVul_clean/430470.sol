gopherToHTML(GopherStateData * gopherState, char *inbuf, int len)
{
    char *pos = inbuf;
    char *lpos = NULL;
    char *tline = NULL;
    LOCAL_ARRAY(char, line, TEMP_BUF_SIZE);
    char *name = NULL;
    char *selector = NULL;
    char *host = NULL;
    char *port = NULL;
    char *escaped_selector = NULL;
    const char *icon_url = NULL;
    char gtype;
    StoreEntry *entry = NULL;
    memset(line, '\0', TEMP_BUF_SIZE);
    entry = gopherState->entry;
    if (gopherState->conversion == GopherStateData::HTML_INDEX_PAGE) {
        char *html_url = html_quote(entry->url());
        gopherHTMLHeader(entry, "Gopher Index %s", html_url);
        storeAppendPrintf(entry,
                          "<p>This is a searchable Gopher index. Use the search\n"
                          "function of your browser to enter search terms.\n"
                          "<ISINDEX>\n");
        gopherHTMLFooter(entry);
        entry->flush();
        gopherState->HTML_header_added = 1;
        return;
    }
    if (gopherState->conversion == GopherStateData::HTML_CSO_PAGE) {
        char *html_url = html_quote(entry->url());
        gopherHTMLHeader(entry, "CSO Search of %s", html_url);
        storeAppendPrintf(entry,
                          "<P>A CSO database usually contains a phonebook or\n"
                          "directory.  Use the search function of your browser to enter\n"
                          "search terms.</P><ISINDEX>\n");
        gopherHTMLFooter(entry);
        entry->flush();
        gopherState->HTML_header_added = 1;
        return;
    }
    SBuf outbuf;
    if (!gopherState->HTML_header_added) {
        if (gopherState->conversion == GopherStateData::HTML_CSO_RESULT)
            gopherHTMLHeader(entry, "CSO Search Result", NULL);
        else
            gopherHTMLHeader(entry, "Gopher Menu", NULL);
        outbuf.append ("<PRE>");
        gopherState->HTML_header_added = 1;
        gopherState->HTML_pre = 1;
    }
    while (pos < inbuf + len) {
        int llen;
        int left = len - (pos - inbuf);
        lpos = (char *)memchr(pos, '\n', left);
        if (lpos) {
            ++lpos;             
            llen = lpos - pos;
        } else {
            llen = left;
        }
        if (gopherState->len + llen >= TEMP_BUF_SIZE) {
            debugs(10, DBG_IMPORTANT, "GopherHTML: Buffer overflow. Lost some data on URL: " << entry->url()  );
            llen = TEMP_BUF_SIZE - gopherState->len - 1;
        }
        if (!lpos) {
            memcpy(gopherState->buf + gopherState->len, pos, llen);
            gopherState->len += llen;
            break;
        }
        if (gopherState->len != 0) {
            memcpy(line, gopherState->buf, gopherState->len);
            memcpy(line + gopherState->len, pos, llen);
            llen += gopherState->len;
            gopherState->len = 0;
        } else {
            memcpy(line, pos, llen);
        }
        line[llen + 1] = '\0';
        pos = lpos;
        if (*line == '.') {
            memset(line, '\0', TEMP_BUF_SIZE);
            continue;
        }
        switch (gopherState->conversion) {
        case GopherStateData::HTML_INDEX_RESULT:
        case GopherStateData::HTML_DIR: {
            tline = line;
            gtype = *tline;
            ++tline;
            name = tline;
            selector = strchr(tline, TAB);
            if (selector) {
                *selector = '\0';
                ++selector;
                host = strchr(selector, TAB);
                if (host) {
                    *host = '\0';
                    ++host;
                    port = strchr(host, TAB);
                    if (port) {
                        char *junk;
                        port[0] = ':';
                        junk = strchr(host, TAB);
                        if (junk)
                            *junk++ = 0;    
                        else {
                            junk = strchr(host, '\r');
                            if (junk)
                                *junk++ = 0;    
                            else {
                                junk = strchr(host, '\n');
                                if (junk)
                                    *junk++ = 0;    
                            }
                        }
                        if ((port[1] == '0') && (!port[2]))
                            port[0] = 0;    
                    }
                    escaped_selector = xstrdup(rfc1738_escape_part(selector));
                    switch (gtype) {
                    case GOPHER_DIRECTORY:
                        icon_url = mimeGetIconURL("internal-menu");
                        break;
                    case GOPHER_HTML:
                    case GOPHER_FILE:
                        icon_url = mimeGetIconURL("internal-text");
                        break;
                    case GOPHER_INDEX:
                    case GOPHER_CSO:
                        icon_url = mimeGetIconURL("internal-index");
                        break;
                    case GOPHER_IMAGE:
                    case GOPHER_GIF:
                    case GOPHER_PLUS_IMAGE:
                        icon_url = mimeGetIconURL("internal-image");
                        break;
                    case GOPHER_SOUND:
                    case GOPHER_PLUS_SOUND:
                        icon_url = mimeGetIconURL("internal-sound");
                        break;
                    case GOPHER_PLUS_MOVIE:
                        icon_url = mimeGetIconURL("internal-movie");
                        break;
                    case GOPHER_TELNET:
                    case GOPHER_3270:
                        icon_url = mimeGetIconURL("internal-telnet");
                        break;
                    case GOPHER_BIN:
                    case GOPHER_MACBINHEX:
                    case GOPHER_DOSBIN:
                    case GOPHER_UUENCODED:
                        icon_url = mimeGetIconURL("internal-binary");
                        break;
                    case GOPHER_INFO:
                        icon_url = NULL;
                        break;
                    default:
                        icon_url = mimeGetIconURL("internal-unknown");
                        break;
                    }
                    if ((gtype == GOPHER_TELNET) || (gtype == GOPHER_3270)) {
                        if (strlen(escaped_selector) != 0)
                            outbuf.appendf("<IMG border=\"0\" SRC=\"%s\"> <A HREF=\"telnet:
                                           icon_url, escaped_selector, rfc1738_escape_part(host),
                                           *port ? ":" : "", port, html_quote(name));
                        else
                            outbuf.appendf("<IMG border=\"0\" SRC=\"%s\"> <A HREF=\"telnet:
                                           icon_url, rfc1738_escape_part(host), *port ? ":" : "",
                                           port, html_quote(name));
                    } else if (gtype == GOPHER_INFO) {
                        outbuf.appendf("\t%s\n", html_quote(name));
                    } else {
                        if (strncmp(selector, "GET /", 5) == 0) {
                            outbuf.appendf("<IMG border=\"0\" SRC=\"%s\"> <A HREF=\"http:
                                           icon_url, host, rfc1738_escape_unescaped(selector + 5), html_quote(name));
                        } else if (gtype == GOPHER_WWW) {
                            outbuf.appendf("<IMG border=\"0\" SRC=\"%s\"> <A HREF=\"gopher:
                                           icon_url, rfc1738_escape_unescaped(selector), html_quote(name));
                        } else {
                            outbuf.appendf("<IMG border=\"0\" SRC=\"%s\"> <A HREF=\"gopher:
                                           icon_url, host, gtype, escaped_selector, html_quote(name));
                        }
                    }
                    safe_free(escaped_selector);
                } else {
                    memset(line, '\0', TEMP_BUF_SIZE);
                    continue;
                }
            } else {
                memset(line, '\0', TEMP_BUF_SIZE);
                continue;
            }
            break;
            }           
        case GopherStateData::HTML_CSO_RESULT: {
            if (line[0] == '-') {
                int code, recno;
                char *s_code, *s_recno, *result;
                s_code = strtok(line + 1, ":\n");
                s_recno = strtok(NULL, ":\n");
                result = strtok(NULL, "\n");
                if (!result)
                    break;
                code = atoi(s_code);
                recno = atoi(s_recno);
                if (code != 200)
                    break;
                if (gopherState->cso_recno != recno) {
                    outbuf.appendf("</PRE><HR noshade size=\"1px\"><H2>Record# %d<br><i>%s</i></H2>\n<PRE>", recno, html_quote(result));
                    gopherState->cso_recno = recno;
                } else {
                    outbuf.appendf("%s\n", html_quote(result));
                }
                break;
            } else {
                int code;
                char *s_code, *result;
                s_code = strtok(line, ":");
                result = strtok(NULL, "\n");
                if (!result)
                    break;
                code = atoi(s_code);
                switch (code) {
                case 200: {
                    break;
                }
                case 102:   
                case 501:   
                case 502: { 
                    outbuf.appendf("</PRE><HR noshade size=\"1px\"><H2>%s</H2>\n<PRE>", html_quote(result));
                    break;
                }
                }
            }
            }           
        default:
            break;      
        }           
    }               
    if (outbuf.length() > 0) {
        entry->append(outbuf.rawContent(), outbuf.length());
        entry->flush();
    }
    return;
}