readconf_main(void)
{
int sep = 0;
struct stat statbuf;
uschar *s, *filename;
uschar *list = config_main_filelist;
while((filename = string_nextinlist(&list, &sep, big_buffer, big_buffer_size))
       != NULL)
  {
  #if defined(CONFIGURE_FILE_USE_NODE) || defined(CONFIGURE_FILE_USE_EUID)
  uschar *suffix = filename + Ustrlen(filename);
  #ifdef CONFIGURE_FILE_USE_NODE
  struct utsname uts;
  if (uname(&uts) >= 0)
    {
    #ifdef CONFIGURE_FILE_USE_EUID
    sprintf(CS suffix, ".%ld.%.256s", (long int)original_euid, uts.nodename);
    config_file = Ufopen(filename, "rb");
    if (config_file == NULL)
    #endif  
      {
      sprintf(CS suffix, ".%.256s", uts.nodename);
      config_file = Ufopen(filename, "rb");
      }
    }
  #endif  
  #ifdef CONFIGURE_FILE_USE_EUID
  if (config_file == NULL)
    {
    sprintf(CS suffix, ".%ld", (long int)original_euid);
    config_file = Ufopen(filename, "rb");
    }
  #endif  
  if (config_file == NULL)
    {
    *suffix = 0;
    config_file = Ufopen(filename, "rb");
    }
  #else  
  config_file = Ufopen(filename, "rb");
  #endif
  if (config_file != NULL || errno != ENOENT) break;
  }
if (config_file != NULL)
  {
  config_filename = config_main_filename = string_copy(filename);
  }
else
  {
  if (filename == NULL)
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "non-existent configuration file(s): "
      "%s", config_main_filelist);
  else
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "%s", string_open_failed(errno,
      "configuration file %s", filename));
  }
if (!config_changed)
  {
  if (fstat(fileno(config_file), &statbuf) != 0)
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "failed to stat configuration file %s",
      big_buffer);
  if ((statbuf.st_uid != root_uid                
       #ifdef CONFIGURE_OWNER
       && statbuf.st_uid != config_uid           
       #endif
         ) ||                                    
      (statbuf.st_gid != root_gid                
       #ifdef CONFIGURE_GROUP
       && statbuf.st_gid != config_gid           
       #endif
       && (statbuf.st_mode & 020) != 0) ||       
      ((statbuf.st_mode & 2) != 0))              
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "Exim configuration file %s has the "
      "wrong owner, group, or mode", big_buffer);
  }
while ((s = get_config_line()) != NULL)
  {
  if (isupper(s[0])) read_macro_assignment(s);
  else if (Ustrncmp(s, "domainlist", 10) == 0)
    read_named_list(&domainlist_anchor, &domainlist_count,
      MAX_NAMED_LIST, s+10, US"domain list");
  else if (Ustrncmp(s, "hostlist", 8) == 0)
    read_named_list(&hostlist_anchor, &hostlist_count,
      MAX_NAMED_LIST, s+8, US"host list");
  else if (Ustrncmp(s, US"addresslist", 11) == 0)
    read_named_list(&addresslist_anchor, &addresslist_count,
      MAX_NAMED_LIST, s+11, US"address list");
  else if (Ustrncmp(s, US"localpartlist", 13) == 0)
    read_named_list(&localpartlist_anchor, &localpartlist_count,
      MAX_NAMED_LIST, s+13, US"local part list");
  else
    (void) readconf_handle_option(s, optionlist_config, optionlist_config_size,
      NULL, US"main option \"%s\" unknown");
  }
if (local_sender_retain && local_from_check)
  log_write(0, LOG_MAIN|LOG_PANIC_DIE, "both local_from_check and "
    "local_sender_retain are set; this combination is not allowed");
if (timezone_string != NULL && *timezone_string == 0) timezone_string = NULL;
if (retry_interval_max > 24*60*60) retry_interval_max = 24*60*60;
if (remote_max_parallel <= 0) remote_max_parallel = 1;
freeze_tell_config = freeze_tell;
if (primary_hostname == NULL)
  {
  uschar *hostname;
  struct utsname uts;
  if (uname(&uts) < 0)
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "uname() failed to yield host name");
  hostname = US uts.nodename;
  if (Ustrchr(hostname, '.') == NULL)
    {
    int af = AF_INET;
    struct hostent *hostdata;
    #if HAVE_IPV6
    if (!disable_ipv6 && (dns_ipv4_lookup == NULL ||
         match_isinlist(hostname, &dns_ipv4_lookup, 0, NULL, NULL, MCL_DOMAIN,
           TRUE, NULL) != OK))
      af = AF_INET6;
    #else
    af = AF_INET;
    #endif
    for (;;)
      {
      #if HAVE_IPV6
        #if HAVE_GETIPNODEBYNAME
        int error_num;
        hostdata = getipnodebyname(CS hostname, af, 0, &error_num);
        #else
        hostdata = gethostbyname2(CS hostname, af);
        #endif
      #else
      hostdata = gethostbyname(CS hostname);
      #endif
      if (hostdata != NULL)
        {
        hostname = US hostdata->h_name;
        break;
        }
      if (af == AF_INET) break;
      af = AF_INET;
      }
    }
  primary_hostname = string_copy(hostname);
  }
smtp_active_hostname = primary_hostname;
if (*spool_directory == 0)
  log_write(0, LOG_MAIN|LOG_PANIC_DIE, "spool_directory undefined: cannot "
    "proceed");
s = expand_string(spool_directory);
if (s == NULL)
  log_write(0, LOG_MAIN|LOG_PANIC_DIE, "failed to expand spool_directory "
    "\"%s\": %s", spool_directory, expand_string_message);
spool_directory = s;
if (*log_file_path != 0)
  {
  uschar *ss, *sss;
  int sep = ':';                       
  s = expand_string(log_file_path);
  if (s == NULL)
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "failed to expand log_file_path "
      "\"%s\": %s", log_file_path, expand_string_message);
  ss = s;
  while ((sss = string_nextinlist(&ss,&sep,big_buffer,big_buffer_size)) != NULL)
    {
    uschar *t;
    if (sss[0] == 0 || Ustrcmp(sss, "syslog") == 0) continue;
    t = Ustrstr(sss, "%s");
    if (t == NULL)
      log_write(0, LOG_MAIN|LOG_PANIC_DIE, "log_file_path \"%s\" does not "
        "contain \"%%s\"", sss);
    *t = 'X';
    t = Ustrchr(sss, '%');
    if (t != NULL)
      {
      if (t[1] != 'D' || Ustrchr(t+2, '%') != NULL)
        log_write(0, LOG_MAIN|LOG_PANIC_DIE, "log_file_path \"%s\" contains "
          "unexpected \"%%\" character", s);
      }
    }
  log_file_path = s;
  }
if (syslog_facility_str != NULL)
  {
  int i;
  uschar *s = syslog_facility_str;
  if ((Ustrlen(syslog_facility_str) >= 4) &&
        (strncmpic(syslog_facility_str, US"log_", 4) == 0))
    s += 4;
  for (i = 0; i < syslog_list_size; i++)
    {
    if (strcmpic(s, syslog_list[i].name) == 0)
      {
      syslog_facility = syslog_list[i].value;
      break;
      }
    }
  if (i >= syslog_list_size)
    {
    log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
      "failed to interpret syslog_facility \"%s\"", syslog_facility_str);
    }
  }
if (*pid_file_path != 0)
  {
  s = expand_string(pid_file_path);
  if (s == NULL)
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "failed to expand pid_file_path "
      "\"%s\": %s", pid_file_path, expand_string_message);
  pid_file_path = s;
  }
regex_From = regex_must_compile(uucp_from_pattern, FALSE, TRUE);
if (smtp_ratelimit_mail != NULL)
  {
  unpick_ratelimit(smtp_ratelimit_mail, &smtp_rlm_threshold,
    &smtp_rlm_base, &smtp_rlm_factor, &smtp_rlm_limit);
  }
if (smtp_ratelimit_rcpt != NULL)
  {
  unpick_ratelimit(smtp_ratelimit_rcpt, &smtp_rlr_threshold,
    &smtp_rlr_base, &smtp_rlr_factor, &smtp_rlr_limit);
  }
if (qualify_domain_sender == NULL)
  qualify_domain_sender = primary_hostname;
if (qualify_domain_recipient == NULL)
  qualify_domain_recipient = qualify_domain_sender;
if (system_filter_uid_set && !system_filter_gid_set)
  {
  struct passwd *pw = getpwuid(system_filter_uid);
  if (pw == NULL)
    log_write(0, LOG_MAIN|LOG_PANIC_DIE, "Failed to look up uid %ld",
      (long int)system_filter_uid);
  system_filter_gid = pw->pw_gid;
  system_filter_gid_set = TRUE;
  }
if (errors_reply_to != NULL)
  {
  uschar *errmess;
  int start, end, domain;
  uschar *recipient = parse_extract_address(errors_reply_to, &errmess,
    &start, &end, &domain, FALSE);
  if (recipient == NULL)
    log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
      "error in errors_reply_to (%s): %s", errors_reply_to, errmess);
  if (domain == 0)
    log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
      "errors_reply_to (%s) does not contain a domain", errors_reply_to);
  }
if (smtp_accept_max == 0 &&
    (smtp_accept_queue > 0 || smtp_accept_max_per_host != NULL))
  log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
    "smtp_accept_max must be set if smtp_accept_queue or "
    "smtp_accept_max_per_host is set");
if (host_number_string != NULL)
  {
  uschar *end;
  uschar *s = expand_string(host_number_string);
  long int n = Ustrtol(s, &end, 0);
  while (isspace(*end)) end++;
  if (*end != 0)
    log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
      "localhost_number value is not a number: %s", s);
  if (n > LOCALHOST_MAX)
    log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
      "localhost_number is greater than the maximum allowed value (%d)",
        LOCALHOST_MAX);
  host_number = n;
  }
#ifdef SUPPORT_TLS
if ((tls_verify_hosts != NULL || tls_try_verify_hosts != NULL) &&
     tls_verify_certificates == NULL)
  log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
    "tls_%sverify_hosts is set, but tls_verify_certificates is not set",
    (tls_verify_hosts != NULL)? "" : "try_");
if (openssl_options != NULL)
  {
# ifdef USE_GNUTLS
  log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
    "openssl_options is set but we're using GnuTLS");
# else
  long dummy;
  if (!(tls_openssl_options_parse(openssl_options, &dummy)))
    log_write(0, LOG_PANIC_DIE|LOG_CONFIG,
      "openssl_options parse error: %s", openssl_options);
# endif
  }
#endif
}