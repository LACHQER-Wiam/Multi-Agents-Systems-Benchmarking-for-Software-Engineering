PQconnectPoll(PGconn *conn)
{
	bool		reset_connection_state_machine = false;
	bool		need_new_connection = false;
	PGresult   *res;
	char		sebuf[PG_STRERROR_R_BUFLEN];
	int			optval;
	if (conn == NULL)
		return PGRES_POLLING_FAILED;
	switch (conn->status)
	{
		case CONNECTION_BAD:
			return PGRES_POLLING_FAILED;
		case CONNECTION_OK:
			return PGRES_POLLING_OK;
		case CONNECTION_AWAITING_RESPONSE:
		case CONNECTION_AUTH_OK:
		case CONNECTION_CHECK_WRITABLE:
		case CONNECTION_CONSUME:
		case CONNECTION_CHECK_STANDBY:
			{
				int			n = pqReadData(conn);
				if (n < 0)
					goto error_return;
				if (n == 0)
					return PGRES_POLLING_READING;
				break;
			}
		case CONNECTION_STARTED:
		case CONNECTION_MADE:
			break;
		case CONNECTION_SSL_STARTUP:
		case CONNECTION_NEEDED:
		case CONNECTION_GSS_STARTUP:
		case CONNECTION_CHECK_TARGET:
			break;
		default:
			appendPQExpBufferStr(&conn->errorMessage,
								 libpq_gettext("invalid connection state, probably indicative of memory corruption\n"));
			goto error_return;
	}
keep_going:						
	if (conn->try_next_addr)
	{
		if (conn->addr_cur && conn->addr_cur->ai_next)
		{
			conn->addr_cur = conn->addr_cur->ai_next;
			reset_connection_state_machine = true;
		}
		else
			conn->try_next_host = true;
		conn->try_next_addr = false;
	}
	if (conn->try_next_host)
	{
		pg_conn_host *ch;
		struct addrinfo hint;
		int			thisport;
		int			ret;
		char		portstr[MAXPGPATH];
		if (conn->whichhost + 1 < conn->nconnhost)
			conn->whichhost++;
		else
		{
			if (conn->target_server_type == SERVER_TYPE_PREFER_STANDBY &&
				conn->nconnhost > 0)
			{
				conn->target_server_type = SERVER_TYPE_PREFER_STANDBY_PASS2;
				conn->whichhost = 0;
			}
			else
				goto error_return;
		}
		release_conn_addrinfo(conn);
		ch = &conn->connhost[conn->whichhost];
		MemSet(&hint, 0, sizeof(hint));
		hint.ai_socktype = SOCK_STREAM;
		conn->addrlist_family = hint.ai_family = AF_UNSPEC;
		if (ch->port == NULL || ch->port[0] == '\0')
			thisport = DEF_PGPORT;
		else
		{
			if (!parse_int_param(ch->port, &thisport, conn, "port"))
				goto error_return;
			if (thisport < 1 || thisport > 65535)
			{
				appendPQExpBuffer(&conn->errorMessage,
								  libpq_gettext("invalid port number: \"%s\"\n"),
								  ch->port);
				goto keep_going;
			}
		}
		snprintf(portstr, sizeof(portstr), "%d", thisport);
		switch (ch->type)
		{
			case CHT_HOST_NAME:
				ret = pg_getaddrinfo_all(ch->host, portstr, &hint,
										 &conn->addrlist);
				if (ret || !conn->addrlist)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("could not translate host name \"%s\" to address: %s\n"),
									  ch->host, gai_strerror(ret));
					goto keep_going;
				}
				break;
			case CHT_HOST_ADDRESS:
				hint.ai_flags = AI_NUMERICHOST;
				ret = pg_getaddrinfo_all(ch->hostaddr, portstr, &hint,
										 &conn->addrlist);
				if (ret || !conn->addrlist)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("could not parse network address \"%s\": %s\n"),
									  ch->hostaddr, gai_strerror(ret));
					goto keep_going;
				}
				break;
			case CHT_UNIX_SOCKET:
#ifdef HAVE_UNIX_SOCKETS
				conn->addrlist_family = hint.ai_family = AF_UNIX;
				UNIXSOCK_PATH(portstr, thisport, ch->host);
				if (strlen(portstr) >= UNIXSOCK_PATH_BUFLEN)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("Unix-domain socket path \"%s\" is too long (maximum %d bytes)\n"),
									  portstr,
									  (int) (UNIXSOCK_PATH_BUFLEN - 1));
					goto keep_going;
				}
				ret = pg_getaddrinfo_all(NULL, portstr, &hint,
										 &conn->addrlist);
				if (ret || !conn->addrlist)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("could not translate Unix-domain socket path \"%s\" to address: %s\n"),
									  portstr, gai_strerror(ret));
					goto keep_going;
				}
#else
				Assert(false);
#endif
				break;
		}
		conn->addr_cur = conn->addrlist;
		reset_connection_state_machine = true;
		conn->try_next_host = false;
	}
	if (reset_connection_state_machine)
	{
		conn->pversion = PG_PROTOCOL(3, 0);
		conn->send_appname = true;
#ifdef USE_SSL
		conn->allow_ssl_try = (conn->sslmode[0] != 'd');	
		conn->wait_ssl_try = (conn->sslmode[0] == 'a'); 
#endif
#ifdef ENABLE_GSS
		conn->try_gss = (conn->gssencmode[0] != 'd');	
#endif
		reset_connection_state_machine = false;
		need_new_connection = true;
	}
	if (need_new_connection)
	{
		pqDropConnection(conn, true);
		pqDropServerData(conn);
		conn->asyncStatus = PGASYNC_IDLE;
		conn->xactStatus = PQTRANS_IDLE;
		conn->pipelineStatus = PQ_PIPELINE_OFF;
		pqClearAsyncResult(conn);
		conn->status = CONNECTION_NEEDED;
		need_new_connection = false;
	}
	switch (conn->status)
	{
		case CONNECTION_NEEDED:
			{
				{
					struct addrinfo *addr_cur = conn->addr_cur;
					char		host_addr[NI_MAXHOST];
					if (addr_cur == NULL)
					{
						conn->try_next_host = true;
						goto keep_going;
					}
					memcpy(&conn->raddr.addr, addr_cur->ai_addr,
						   addr_cur->ai_addrlen);
					conn->raddr.salen = addr_cur->ai_addrlen;
					if (conn->connip != NULL)
					{
						free(conn->connip);
						conn->connip = NULL;
					}
					getHostaddr(conn, host_addr, NI_MAXHOST);
					if (host_addr[0])
						conn->connip = strdup(host_addr);
					conn->sock = socket(addr_cur->ai_family, SOCK_STREAM, 0);
					if (conn->sock == PGINVALID_SOCKET)
					{
						int			errorno = SOCK_ERRNO;
						if (addr_cur->ai_next != NULL ||
							conn->whichhost + 1 < conn->nconnhost)
						{
							conn->try_next_addr = true;
							goto keep_going;
						}
						emitHostIdentityInfo(conn, host_addr);
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("could not create socket: %s\n"),
										  SOCK_STRERROR(errorno, sebuf, sizeof(sebuf)));
						goto error_return;
					}
					emitHostIdentityInfo(conn, host_addr);
					if (!IS_AF_UNIX(addr_cur->ai_family))
					{
						if (!connectNoDelay(conn))
						{
							conn->try_next_addr = true;
							goto keep_going;
						}
					}
					if (!pg_set_noblock(conn->sock))
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("could not set socket to nonblocking mode: %s\n"),
										  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
						conn->try_next_addr = true;
						goto keep_going;
					}
#ifdef F_SETFD
					if (fcntl(conn->sock, F_SETFD, FD_CLOEXEC) == -1)
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("could not set socket to close-on-exec mode: %s\n"),
										  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
						conn->try_next_addr = true;
						goto keep_going;
					}
#endif							
					if (!IS_AF_UNIX(addr_cur->ai_family))
					{
#ifndef WIN32
						int			on = 1;
#endif
						int			usekeepalives = useKeepalives(conn);
						int			err = 0;
						if (usekeepalives < 0)
						{
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("keepalives parameter must be an integer\n"));
							err = 1;
						}
						else if (usekeepalives == 0)
						{
						}
#ifndef WIN32
						else if (setsockopt(conn->sock,
											SOL_SOCKET, SO_KEEPALIVE,
											(char *) &on, sizeof(on)) < 0)
						{
							appendPQExpBuffer(&conn->errorMessage,
											  libpq_gettext("%s(%s) failed: %s\n"),
											  "setsockopt",
											  "SO_KEEPALIVE",
											  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
							err = 1;
						}
						else if (!setKeepalivesIdle(conn)
								 || !setKeepalivesInterval(conn)
								 || !setKeepalivesCount(conn))
							err = 1;
#else							
#ifdef SIO_KEEPALIVE_VALS
						else if (!setKeepalivesWin32(conn))
							err = 1;
#endif							
#endif							
						else if (!setTCPUserTimeout(conn))
							err = 1;
						if (err)
						{
							conn->try_next_addr = true;
							goto keep_going;
						}
					}
					conn->sigpipe_so = false;
#ifdef MSG_NOSIGNAL
					conn->sigpipe_flag = true;
#else
					conn->sigpipe_flag = false;
#endif							
#ifdef SO_NOSIGPIPE
					optval = 1;
					if (setsockopt(conn->sock, SOL_SOCKET, SO_NOSIGPIPE,
								   (char *) &optval, sizeof(optval)) == 0)
					{
						conn->sigpipe_so = true;
						conn->sigpipe_flag = false;
					}
#endif							
					if (connect(conn->sock, addr_cur->ai_addr,
								addr_cur->ai_addrlen) < 0)
					{
						if (SOCK_ERRNO == EINPROGRESS ||
#ifdef WIN32
							SOCK_ERRNO == EWOULDBLOCK ||
#endif
							SOCK_ERRNO == EINTR)
						{
							conn->status = CONNECTION_STARTED;
							return PGRES_POLLING_WRITING;
						}
					}
					else
					{
						conn->status = CONNECTION_STARTED;
						goto keep_going;
					}
					connectFailureMessage(conn, SOCK_ERRNO);
					conn->try_next_addr = true;
					goto keep_going;
				}
			}
		case CONNECTION_STARTED:
			{
				ACCEPT_TYPE_ARG3 optlen = sizeof(optval);
				if (getsockopt(conn->sock, SOL_SOCKET, SO_ERROR,
							   (char *) &optval, &optlen) == -1)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("could not get socket error status: %s\n"),
									  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
					goto error_return;
				}
				else if (optval != 0)
				{
					connectFailureMessage(conn, optval);
					conn->try_next_addr = true;
					goto keep_going;
				}
				conn->laddr.salen = sizeof(conn->laddr.addr);
				if (getsockname(conn->sock,
								(struct sockaddr *) &conn->laddr.addr,
								&conn->laddr.salen) < 0)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("could not get client address from socket: %s\n"),
									  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
					goto error_return;
				}
				conn->status = CONNECTION_MADE;
				return PGRES_POLLING_WRITING;
			}
		case CONNECTION_MADE:
			{
				char	   *startpacket;
				int			packetlen;
				if (conn->requirepeer && conn->requirepeer[0] &&
					IS_AF_UNIX(conn->raddr.addr.ss_family))
				{
#ifndef WIN32
					char		pwdbuf[BUFSIZ];
					struct passwd pass_buf;
					struct passwd *pass;
					int			passerr;
#endif
					uid_t		uid;
					gid_t		gid;
					errno = 0;
					if (getpeereid(conn->sock, &uid, &gid) != 0)
					{
						if (errno == ENOSYS)
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("requirepeer parameter is not supported on this platform\n"));
						else
							appendPQExpBuffer(&conn->errorMessage,
											  libpq_gettext("could not get peer credentials: %s\n"),
											  strerror_r(errno, sebuf, sizeof(sebuf)));
						goto error_return;
					}
#ifndef WIN32
					passerr = pqGetpwuid(uid, &pass_buf, pwdbuf, sizeof(pwdbuf), &pass);
					if (pass == NULL)
					{
						if (passerr != 0)
							appendPQExpBuffer(&conn->errorMessage,
											  libpq_gettext("could not look up local user ID %d: %s\n"),
											  (int) uid,
											  strerror_r(passerr, sebuf, sizeof(sebuf)));
						else
							appendPQExpBuffer(&conn->errorMessage,
											  libpq_gettext("local user with ID %d does not exist\n"),
											  (int) uid);
						goto error_return;
					}
					if (strcmp(pass->pw_name, conn->requirepeer) != 0)
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("requirepeer specifies \"%s\", but actual peer user name is \"%s\"\n"),
										  conn->requirepeer, pass->pw_name);
						goto error_return;
					}
#else							
					Assert(false);
#endif							
				}
				if (IS_AF_UNIX(conn->raddr.addr.ss_family))
				{
#ifdef USE_SSL
					conn->allow_ssl_try = false;
#endif
#ifdef ENABLE_GSS
					conn->try_gss = false;
#endif
				}
#ifdef ENABLE_GSS
				if (conn->try_gss && !conn->gctx)
					conn->try_gss = pg_GSS_have_cred_cache(&conn->gcred);
				if (conn->try_gss && !conn->gctx)
				{
					ProtocolVersion pv = pg_hton32(NEGOTIATE_GSS_CODE);
					if (pqPacketSend(conn, 0, &pv, sizeof(pv)) != STATUS_OK)
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("could not send GSSAPI negotiation packet: %s\n"),
										  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
						goto error_return;
					}
					conn->status = CONNECTION_GSS_STARTUP;
					return PGRES_POLLING_READING;
				}
				else if (!conn->gctx && conn->gssencmode[0] == 'r')
				{
					appendPQExpBufferStr(&conn->errorMessage,
										 libpq_gettext("GSSAPI encryption required but was impossible (possibly no credential cache, no server support, or using a local socket)\n"));
					goto error_return;
				}
#endif
#ifdef USE_SSL
				if (pqsecure_initialize(conn, false, true) < 0)
					goto error_return;
				if (conn->allow_ssl_try && !conn->wait_ssl_try &&
					!conn->ssl_in_use
#ifdef ENABLE_GSS
					&& !conn->gssenc
#endif
					)
				{
					ProtocolVersion pv;
					pv = pg_hton32(NEGOTIATE_SSL_CODE);
					if (pqPacketSend(conn, 0, &pv, sizeof(pv)) != STATUS_OK)
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("could not send SSL negotiation packet: %s\n"),
										  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
						goto error_return;
					}
					conn->status = CONNECTION_SSL_STARTUP;
					return PGRES_POLLING_READING;
				}
#endif							
				startpacket = pqBuildStartupPacket3(conn, &packetlen,
													EnvironmentOptions);
				if (!startpacket)
				{
					appendPQExpBufferStr(&conn->errorMessage,
										 libpq_gettext("out of memory\n"));
					goto error_return;
				}
				if (pqPacketSend(conn, 0, startpacket, packetlen) != STATUS_OK)
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("could not send startup packet: %s\n"),
									  SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
					free(startpacket);
					goto error_return;
				}
				free(startpacket);
				conn->status = CONNECTION_AWAITING_RESPONSE;
				return PGRES_POLLING_READING;
			}
		case CONNECTION_SSL_STARTUP:
			{
#ifdef USE_SSL
				PostgresPollingStatusType pollres;
				if (!conn->ssl_in_use)
				{
					char		SSLok;
					int			rdresult;
					rdresult = pqReadData(conn);
					if (rdresult < 0)
					{
						goto error_return;
					}
					if (rdresult == 0)
					{
						return PGRES_POLLING_READING;
					}
					if (pqGetc(&SSLok, conn) < 0)
					{
						return PGRES_POLLING_READING;
					}
					if (SSLok == 'S')
					{
						conn->inStart = conn->inCursor;
						if (pqsecure_initialize(conn, true, false) != 0)
							goto error_return;
					}
					else if (SSLok == 'N')
					{
						conn->inStart = conn->inCursor;
						if (conn->sslmode[0] == 'r' ||	
							conn->sslmode[0] == 'v')	
						{
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("server does not support SSL, but SSL was required\n"));
							goto error_return;
						}
						conn->allow_ssl_try = false;
						conn->status = CONNECTION_MADE;
						return PGRES_POLLING_WRITING;
					}
					else if (SSLok == 'E')
					{
						conn->status = CONNECTION_AWAITING_RESPONSE;
						goto keep_going;
					}
					else
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("received invalid response to SSL negotiation: %c\n"),
										  SSLok);
						goto error_return;
					}
				}
				pollres = pqsecure_open_client(conn);
				if (pollres == PGRES_POLLING_OK)
				{
					conn->status = CONNECTION_MADE;
					return PGRES_POLLING_WRITING;
				}
				if (pollres == PGRES_POLLING_FAILED)
				{
					if (conn->sslmode[0] == 'p' 
						&& conn->allow_ssl_try	
						&& !conn->wait_ssl_try) 
					{
						conn->allow_ssl_try = false;
						need_new_connection = true;
						goto keep_going;
					}
					goto error_return;
				}
				return pollres;
#else							
				goto error_return;
#endif							
			}
		case CONNECTION_GSS_STARTUP:
			{
#ifdef ENABLE_GSS
				PostgresPollingStatusType pollres;
				if (conn->try_gss && !conn->gctx)
				{
					char		gss_ok;
					int			rdresult = pqReadData(conn);
					if (rdresult < 0)
						goto error_return;
					else if (rdresult == 0)
						return PGRES_POLLING_READING;
					if (pqGetc(&gss_ok, conn) < 0)
						return PGRES_POLLING_READING;
					if (gss_ok == 'E')
					{
						conn->try_gss = false;
						need_new_connection = true;
						goto keep_going;
					}
					conn->inStart = conn->inCursor;
					if (gss_ok == 'N')
					{
						if (conn->gssencmode[0] == 'r')
						{
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("server doesn't support GSSAPI encryption, but it was required\n"));
							goto error_return;
						}
						conn->try_gss = false;
						conn->status = CONNECTION_MADE;
						return PGRES_POLLING_WRITING;
					}
					else if (gss_ok != 'G')
					{
						appendPQExpBuffer(&conn->errorMessage,
										  libpq_gettext("received invalid response to GSSAPI negotiation: %c\n"),
										  gss_ok);
						goto error_return;
					}
				}
				pollres = pqsecure_open_gss(conn);
				if (pollres == PGRES_POLLING_OK)
				{
					conn->status = CONNECTION_MADE;
					return PGRES_POLLING_WRITING;
				}
				else if (pollres == PGRES_POLLING_FAILED &&
						 conn->gssencmode[0] == 'p')
				{
					conn->try_gss = false;
					need_new_connection = true;
					goto keep_going;
				}
				return pollres;
#else							
				goto error_return;
#endif							
			}
		case CONNECTION_AWAITING_RESPONSE:
			{
				char		beresp;
				int			msgLength;
				int			avail;
				AuthRequest areq;
				int			res;
				conn->inCursor = conn->inStart;
				if (pqGetc(&beresp, conn))
				{
					return PGRES_POLLING_READING;
				}
				if (!(beresp == 'R' || beresp == 'E'))
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("expected authentication request from server, but received %c\n"),
									  beresp);
					goto error_return;
				}
				if (pqGetInt(&msgLength, 4, conn))
				{
					return PGRES_POLLING_READING;
				}
				if (beresp == 'R' && (msgLength < 8 || msgLength > 2000))
				{
					appendPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("expected authentication request from server, but received %c\n"),
									  beresp);
					goto error_return;
				}
				if (beresp == 'E' && (msgLength < 8 || msgLength > 30000))
				{
					conn->inCursor = conn->inStart + 1; 
					if (pqGets_append(&conn->errorMessage, conn))
					{
						return PGRES_POLLING_READING;
					}
					conn->inStart = conn->inCursor;
					if (conn->errorMessage.len == 0 ||
						conn->errorMessage.data[conn->errorMessage.len - 1] != '\n')
					{
						appendPQExpBufferChar(&conn->errorMessage, '\n');
					}
					goto error_return;
				}
				msgLength -= 4;
				avail = conn->inEnd - conn->inCursor;
				if (avail < msgLength)
				{
					if (pqCheckInBufferSpace(conn->inCursor + (size_t) msgLength,
											 conn))
						goto error_return;
					return PGRES_POLLING_READING;
				}
				if (beresp == 'E')
				{
					if (pqGetErrorNotice3(conn, true))
					{
						return PGRES_POLLING_READING;
					}
					conn->inStart = conn->inCursor;
					if (strcmp(conn->last_sqlstate,
							   ERRCODE_CANNOT_CONNECT_NOW) == 0)
					{
						conn->try_next_host = true;
						goto keep_going;
					}
					pgpassfileWarning(conn);
#ifdef ENABLE_GSS
					if (conn->gssenc && conn->gssencmode[0] == 'p')
					{
						conn->try_gss = false;
						need_new_connection = true;
						goto keep_going;
					}
#endif
#ifdef USE_SSL
					if (conn->sslmode[0] == 'a' 
						&& !conn->ssl_in_use
						&& conn->allow_ssl_try
						&& conn->wait_ssl_try)
					{
						conn->wait_ssl_try = false;
						need_new_connection = true;
						goto keep_going;
					}
					if (conn->sslmode[0] == 'p' 
						&& conn->ssl_in_use
						&& conn->allow_ssl_try	
						&& !conn->wait_ssl_try) 
					{
						conn->allow_ssl_try = false;
						need_new_connection = true;
						goto keep_going;
					}
#endif
					goto error_return;
				}
				conn->auth_req_received = true;
				if (pqGetInt((int *) &areq, 4, conn))
				{
					return PGRES_POLLING_READING;
				}
				msgLength -= 4;
				res = pg_fe_sendauth(areq, msgLength, conn);
				conn->inStart = conn->inCursor;
				if (res != STATUS_OK)
					goto error_return;
				if (pqFlush(conn))
					goto error_return;
				if (areq == AUTH_REQ_OK)
				{
					conn->status = CONNECTION_AUTH_OK;
					conn->asyncStatus = PGASYNC_BUSY;
				}
				goto keep_going;
			}
		case CONNECTION_AUTH_OK:
			{
				if (PQisBusy(conn))
					return PGRES_POLLING_READING;
				res = PQgetResult(conn);
				if (res)
				{
					if (res->resultStatus != PGRES_FATAL_ERROR)
						appendPQExpBufferStr(&conn->errorMessage,
											 libpq_gettext("unexpected message from server during startup\n"));
					else if (conn->send_appname &&
							 (conn->appname || conn->fbappname))
					{
						const char *sqlstate;
						sqlstate = PQresultErrorField(res, PG_DIAG_SQLSTATE);
						if (sqlstate &&
							strcmp(sqlstate, ERRCODE_APPNAME_UNKNOWN) == 0)
						{
							PQclear(res);
							conn->send_appname = false;
							need_new_connection = true;
							goto keep_going;
						}
					}
					if (conn->errorMessage.len <= 0 ||
						conn->errorMessage.data[conn->errorMessage.len - 1] != '\n')
						appendPQExpBufferChar(&conn->errorMessage, '\n');
					PQclear(res);
					goto error_return;
				}
				conn->status = CONNECTION_CHECK_TARGET;
				goto keep_going;
			}
		case CONNECTION_CHECK_TARGET:
			{
				if (conn->target_server_type == SERVER_TYPE_READ_WRITE ||
					conn->target_server_type == SERVER_TYPE_READ_ONLY)
				{
					bool		read_only_server;
					if (conn->default_transaction_read_only == PG_BOOL_UNKNOWN ||
						conn->in_hot_standby == PG_BOOL_UNKNOWN)
					{
						conn->status = CONNECTION_OK;
						if (!PQsendQueryContinue(conn,
												 "SHOW transaction_read_only"))
							goto error_return;
						conn->status = CONNECTION_CHECK_WRITABLE;
						return PGRES_POLLING_READING;
					}
					read_only_server =
						(conn->default_transaction_read_only == PG_BOOL_YES ||
						 conn->in_hot_standby == PG_BOOL_YES);
					if ((conn->target_server_type == SERVER_TYPE_READ_WRITE) ?
						read_only_server : !read_only_server)
					{
						if (conn->target_server_type == SERVER_TYPE_READ_WRITE)
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("session is read-only\n"));
						else
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("session is not read-only\n"));
						conn->status = CONNECTION_OK;
						sendTerminateConn(conn);
						conn->try_next_host = true;
						goto keep_going;
					}
				}
				else if (conn->target_server_type == SERVER_TYPE_PRIMARY ||
						 conn->target_server_type == SERVER_TYPE_STANDBY ||
						 conn->target_server_type == SERVER_TYPE_PREFER_STANDBY)
				{
					if (conn->sversion < 90000)
						conn->in_hot_standby = PG_BOOL_NO;
					if (conn->in_hot_standby == PG_BOOL_UNKNOWN)
					{
						conn->status = CONNECTION_OK;
						if (!PQsendQueryContinue(conn,
												 "SELECT pg_catalog.pg_is_in_recovery()"))
							goto error_return;
						conn->status = CONNECTION_CHECK_STANDBY;
						return PGRES_POLLING_READING;
					}
					if ((conn->target_server_type == SERVER_TYPE_PRIMARY) ?
						(conn->in_hot_standby == PG_BOOL_YES) :
						(conn->in_hot_standby == PG_BOOL_NO))
					{
						if (conn->target_server_type == SERVER_TYPE_PRIMARY)
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("server is in hot standby mode\n"));
						else
							appendPQExpBufferStr(&conn->errorMessage,
												 libpq_gettext("server is not in hot standby mode\n"));
						conn->status = CONNECTION_OK;
						sendTerminateConn(conn);
						conn->try_next_host = true;
						goto keep_going;
					}
				}
				release_conn_addrinfo(conn);
				resetPQExpBuffer(&conn->errorMessage);
				conn->status = CONNECTION_OK;
				return PGRES_POLLING_OK;
			}
		case CONNECTION_CONSUME:
			{
				conn->status = CONNECTION_OK;
				if (!PQconsumeInput(conn))
					goto error_return;
				if (PQisBusy(conn))
				{
					conn->status = CONNECTION_CONSUME;
					return PGRES_POLLING_READING;
				}
				res = PQgetResult(conn);
				if (res != NULL)
				{
					PQclear(res);
					conn->status = CONNECTION_CONSUME;
					return PGRES_POLLING_READING;
				}
				conn->status = CONNECTION_CHECK_TARGET;
				goto keep_going;
			}
		case CONNECTION_CHECK_WRITABLE:
			{
				conn->status = CONNECTION_OK;
				if (!PQconsumeInput(conn))
					goto error_return;
				if (PQisBusy(conn))
				{
					conn->status = CONNECTION_CHECK_WRITABLE;
					return PGRES_POLLING_READING;
				}
				res = PQgetResult(conn);
				if (res && PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1)
				{
					char	   *val = PQgetvalue(res, 0, 0);
					if (strncmp(val, "on", 2) == 0)
					{
						conn->default_transaction_read_only = PG_BOOL_YES;
						conn->in_hot_standby = PG_BOOL_YES;
					}
					else
					{
						conn->default_transaction_read_only = PG_BOOL_NO;
						conn->in_hot_standby = PG_BOOL_NO;
					}
					PQclear(res);
					conn->status = CONNECTION_CONSUME;
					goto keep_going;
				}
				if (res)
					PQclear(res);
				appendPQExpBuffer(&conn->errorMessage,
								  libpq_gettext("\"%s\" failed\n"),
								  "SHOW transaction_read_only");
				conn->status = CONNECTION_OK;
				sendTerminateConn(conn);
				conn->try_next_host = true;
				goto keep_going;
			}
		case CONNECTION_CHECK_STANDBY:
			{
				conn->status = CONNECTION_OK;
				if (!PQconsumeInput(conn))
					goto error_return;
				if (PQisBusy(conn))
				{
					conn->status = CONNECTION_CHECK_STANDBY;
					return PGRES_POLLING_READING;
				}
				res = PQgetResult(conn);
				if (res && PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1)
				{
					char	   *val = PQgetvalue(res, 0, 0);
					if (strncmp(val, "t", 1) == 0)
						conn->in_hot_standby = PG_BOOL_YES;
					else
						conn->in_hot_standby = PG_BOOL_NO;
					PQclear(res);
					conn->status = CONNECTION_CONSUME;
					goto keep_going;
				}
				if (res)
					PQclear(res);
				appendPQExpBuffer(&conn->errorMessage,
								  libpq_gettext("\"%s\" failed\n"),
								  "SELECT pg_is_in_recovery()");
				conn->status = CONNECTION_OK;
				sendTerminateConn(conn);
				conn->try_next_host = true;
				goto keep_going;
			}
		default:
			appendPQExpBuffer(&conn->errorMessage,
							  libpq_gettext("invalid connection state %d, "
											"probably indicative of memory corruption\n"),
							  conn->status);
			goto error_return;
	}
error_return:
	conn->status = CONNECTION_BAD;
	return PGRES_POLLING_FAILED;
}