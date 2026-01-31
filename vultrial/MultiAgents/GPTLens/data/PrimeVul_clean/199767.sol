inbound_cap_ls (server *serv, char *nick, char *extensions_str,
					 const message_tags_data *tags_data)
{
	char buffer[256];	
	guint32 want_cap; 
	guint32 want_sasl; 
	char **extensions;
	int i;
	EMIT_SIGNAL_TIMESTAMP (XP_TE_CAPLIST, serv->server_session, nick,
								  extensions_str, NULL, NULL, 0, tags_data->timestamp);
	want_cap = 0;
	want_sasl = 0;
	extensions = g_strsplit (extensions_str, " ", 0);
	strcpy (buffer, "CAP REQ :");
	for (i=0; extensions[i]; i++)
	{
		const char *extension = extensions[i];
		if (!strcmp (extension, "identify-msg"))
		{
			strcat (buffer, "identify-msg ");
			want_cap = 1;
		}
		if (!strcmp (extension, "multi-prefix"))
		{
			strcat (buffer, "multi-prefix ");
			want_cap = 1;
		}
		if (!strcmp (extension, "away-notify"))
		{
			strcat (buffer, "away-notify ");
			want_cap = 1;
		}
		if (!strcmp (extension, "account-notify"))
		{
			strcat (buffer, "account-notify ");
			want_cap = 1;
		}
		if (!strcmp (extension, "extended-join"))
		{
			strcat (buffer, "extended-join ");
			want_cap = 1;
		}
		if (!strcmp (extension, "userhost-in-names"))
		{
			strcat (buffer, "userhost-in-names ");
			want_cap = 1;
		}
		if (!strcmp (extension, "znc.in/server-time-iso"))
		{
			strcat (buffer, "znc.in/server-time-iso ");
			want_cap = 1;
		}
		if (!strcmp (extension, "znc.in/server-time"))
		{
			strcat (buffer, "znc.in/server-time ");
			want_cap = 1;
		}
		if (prefs.hex_irc_cap_server_time
			 && !strcmp (extension, "server-time"))
		{
			strcat (buffer, "server-time ");
			want_cap = 1;
		}
		if (!strcmp (extension, "sasl")
			&& ((serv->loginmethod == LOGIN_SASL && strlen (serv->password) != 0)
			|| (serv->loginmethod == LOGIN_SASLEXTERNAL && serv->have_cert)))
		{
			strcat (buffer, "sasl ");
			want_cap = 1;
			want_sasl = 1;
		}
	}
	g_strfreev (extensions);
	if (want_cap)
	{
		EMIT_SIGNAL_TIMESTAMP (XP_TE_CAPREQ, serv->server_session,
									  buffer + 9, NULL, NULL, NULL, 0,
									  tags_data->timestamp);
		tcp_sendf (serv, "%s\r\n", g_strchomp (buffer));
	}
	if (!want_sasl)
	{
		serv->sent_capend = TRUE;
		tcp_send_len (serv, "CAP END\r\n", 9);
	}
}