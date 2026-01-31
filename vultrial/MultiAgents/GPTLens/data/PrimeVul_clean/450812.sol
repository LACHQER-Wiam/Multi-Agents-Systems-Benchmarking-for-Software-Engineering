glob (const char *pattern, int flags, int (*errfunc) (const char *, int),
      glob_t *pglob)
{
  const char *filename;
  char *dirname = NULL;
  size_t dirlen;
  int status;
  size_t oldcount;
  int meta;
  int dirname_modified;
  int malloc_dirname = 0;
  glob_t dirs;
  int retval = 0;
  size_t alloca_used = 0;
  if (pattern == NULL || pglob == NULL || (flags & ~__GLOB_FLAGS) != 0)
    {
      __set_errno (EINVAL);
      return -1;
    }
  if (pattern[0] && pattern[strlen (pattern) - 1] == '/')
    flags |= GLOB_ONLYDIR;
  if (!(flags & GLOB_DOOFFS))
    pglob->gl_offs = 0;
  if (!(flags & GLOB_APPEND))
    {
      pglob->gl_pathc = 0;
      if (!(flags & GLOB_DOOFFS))
        pglob->gl_pathv = NULL;
      else
        {
          size_t i;
          if (pglob->gl_offs >= ~((size_t) 0) / sizeof (char *))
            return GLOB_NOSPACE;
          pglob->gl_pathv = (char **) malloc ((pglob->gl_offs + 1)
                                              * sizeof (char *));
          if (pglob->gl_pathv == NULL)
            return GLOB_NOSPACE;
          for (i = 0; i <= pglob->gl_offs; ++i)
            pglob->gl_pathv[i] = NULL;
        }
    }
  if (flags & GLOB_BRACE)
    {
      const char *begin;
      if (flags & GLOB_NOESCAPE)
        begin = strchr (pattern, '{');
      else
        {
          begin = pattern;
          while (1)
            {
              if (*begin == '\0')
                {
                  begin = NULL;
                  break;
                }
              if (*begin == '\\' && begin[1] != '\0')
                ++begin;
              else if (*begin == '{')
                break;
              ++begin;
            }
        }
      if (begin != NULL)
        {
          size_t firstc;
          char *alt_start;
          const char *p;
          const char *next;
          const char *rest;
          size_t rest_len;
          char *onealt;
          size_t pattern_len = strlen (pattern) - 1;
          int alloca_onealt = glob_use_alloca (alloca_used, pattern_len);
          if (alloca_onealt)
            onealt = alloca_account (pattern_len, alloca_used);
          else
            {
              onealt = malloc (pattern_len);
              if (onealt == NULL)
                return GLOB_NOSPACE;
            }
          alt_start = mempcpy (onealt, pattern, begin - pattern);
          next = next_brace_sub (begin + 1, flags);
          if (next == NULL)
            {
            illegal_brace:
              if (__glibc_unlikely (!alloca_onealt))
                free (onealt);
              flags &= ~GLOB_BRACE;
              goto no_brace;
            }
          rest = next;
          while (*rest != '}')
            {
              rest = next_brace_sub (rest + 1, flags);
              if (rest == NULL)
                goto illegal_brace;
            }
          rest_len = strlen (++rest) + 1;
          firstc = pglob->gl_pathc;
          p = begin + 1;
          while (1)
            {
              int result;
              mempcpy (mempcpy (alt_start, p, next - p), rest, rest_len);
              result = glob (onealt,
                             ((flags & ~(GLOB_NOCHECK | GLOB_NOMAGIC))
                              | GLOB_APPEND), errfunc, pglob);
              if (result && result != GLOB_NOMATCH)
                {
                  if (__glibc_unlikely (!alloca_onealt))
                    free (onealt);
                  if (!(flags & GLOB_APPEND))
                    {
                      globfree (pglob);
                      pglob->gl_pathc = 0;
                    }
                  return result;
                }
              if (*next == '}')
                break;
              p = next + 1;
              next = next_brace_sub (p, flags);
              assert (next != NULL);
            }
          if (__glibc_unlikely (!alloca_onealt))
            free (onealt);
          if (pglob->gl_pathc != firstc)
            return 0;
          else if (!(flags & (GLOB_NOCHECK|GLOB_NOMAGIC)))
            return GLOB_NOMATCH;
        }
    }
 no_brace:
  oldcount = pglob->gl_pathc + pglob->gl_offs;
  filename = strrchr (pattern, '/');
#if defined __MSDOS__ || defined WINDOWS32
  if (filename == NULL)
    filename = strchr (pattern, ':');
#endif 
  dirname_modified = 0;
  if (filename == NULL)
    {
      if ((flags & (GLOB_TILDE|GLOB_TILDE_CHECK)) && pattern[0] == '~')
        {
          dirname = (char *) pattern;
          dirlen = strlen (pattern);
          filename = NULL;
        }
      else
        {
          if (__glibc_unlikely (pattern[0] == '\0'))
            {
              dirs.gl_pathv = NULL;
              goto no_matches;
            }
          filename = pattern;
          dirname = (char *) ".";
          dirlen = 0;
        }
    }
  else if (filename == pattern
           || (filename == pattern + 1 && pattern[0] == '\\'
               && (flags & GLOB_NOESCAPE) == 0))
    {
      dirname = (char *) "/";
      dirlen = 1;
      ++filename;
    }
  else
    {
      char *newp;
      dirlen = filename - pattern;
#if defined __MSDOS__ || defined WINDOWS32
      if (*filename == ':'
          || (filename > pattern + 1 && filename[-1] == ':'))
        {
          char *drive_spec;
          ++dirlen;
          drive_spec = __alloca (dirlen + 1);
          *((char *) mempcpy (drive_spec, pattern, dirlen)) = '\0';
          if (__glob_pattern_p (drive_spec, !(flags & GLOB_NOESCAPE)))
            return GLOB_NOMATCH;
        }
#endif
      if (glob_use_alloca (alloca_used, dirlen + 1))
        newp = alloca_account (dirlen + 1, alloca_used);
      else
        {
          newp = malloc (dirlen + 1);
          if (newp == NULL)
            return GLOB_NOSPACE;
          malloc_dirname = 1;
        }
      *((char *) mempcpy (newp, pattern, dirlen)) = '\0';
      dirname = newp;
      ++filename;
#if defined __MSDOS__ || defined WINDOWS32
      bool drive_root = (dirlen > 1
                         && (dirname[dirlen - 1] == ':'
                             || (dirlen > 2 && dirname[dirlen - 2] == ':'
                                 && dirname[dirlen - 1] == '/')));
#else
      bool drive_root = false;
#endif
      if (filename[0] == '\0' && dirlen > 1 && !drive_root)
        {
          int orig_flags = flags;
          if (!(flags & GLOB_NOESCAPE) && dirname[dirlen - 1] == '\\')
            {
              char *p = (char *) &dirname[dirlen - 1];
              while (p > dirname && p[-1] == '\\') --p;
              if ((&dirname[dirlen] - p) & 1)
                {
                  *(char *) &dirname[--dirlen] = '\0';
                  flags &= ~(GLOB_NOCHECK | GLOB_NOMAGIC);
                }
            }
          int val = glob (dirname, flags | GLOB_MARK, errfunc, pglob);
          if (val == 0)
            pglob->gl_flags = ((pglob->gl_flags & ~GLOB_MARK)
                               | (flags & GLOB_MARK));
          else if (val == GLOB_NOMATCH && flags != orig_flags)
            {
              dirs.gl_pathv = NULL;
              flags = orig_flags;
              oldcount = pglob->gl_pathc + pglob->gl_offs;
              goto no_matches;
            }
          retval = val;
          goto out;
        }
    }
  if ((flags & (GLOB_TILDE|GLOB_TILDE_CHECK)) && dirname[0] == '~')
    {
      if (dirname[1] == '\0' || dirname[1] == '/'
          || (!(flags & GLOB_NOESCAPE) && dirname[1] == '\\'
              && (dirname[2] == '\0' || dirname[2] == '/')))
        {
          char *home_dir = getenv ("HOME");
          int malloc_home_dir = 0;
          if (home_dir == NULL || home_dir[0] == '\0')
            {
#ifdef WINDOWS32
              const char *home_drive = getenv ("HOMEDRIVE");
              const char *home_path = getenv ("HOMEPATH");
              if (home_drive != NULL && home_path != NULL)
                {
                  size_t home_drive_len = strlen (home_drive);
                  size_t home_path_len = strlen (home_path);
                  char *mem = alloca (home_drive_len + home_path_len + 1);
                  memcpy (mem, home_drive, home_drive_len);
                  memcpy (mem + home_drive_len, home_path, home_path_len + 1);
                  home_dir = mem;
                }
              else
                home_dir = "c:/users/default"; 
#else
              int err;
              struct passwd *p;
              struct passwd pwbuf;
              struct scratch_buffer s;
              scratch_buffer_init (&s);
              while (true)
                {
                  p = NULL;
                  err = __getlogin_r (s.data, s.length);
                  if (err == 0)
                    {
# if defined HAVE_GETPWNAM_R || defined _LIBC
                      size_t ssize = strlen (s.data) + 1;
                      err = getpwnam_r (s.data, &pwbuf, s.data + ssize,
                                        s.length - ssize, &p);
# else
                      p = getpwnam (s.data);
                      if (p == NULL)
                        err = errno;
# endif
                    }
                  if (err != ERANGE)
                    break;
                  if (!scratch_buffer_grow (&s))
                    {
                      retval = GLOB_NOSPACE;
                      goto out;
                    }
                }
              if (err == 0)
                {
                  home_dir = strdup (p->pw_dir);
                  malloc_home_dir = 1;
                }
              scratch_buffer_free (&s);
              if (err == 0 && home_dir == NULL)
                {
                  retval = GLOB_NOSPACE;
                  goto out;
                }
#endif 
            }
          if (home_dir == NULL || home_dir[0] == '\0')
            {
              if (__glibc_unlikely (malloc_home_dir))
                free (home_dir);
              if (flags & GLOB_TILDE_CHECK)
                {
                  retval = GLOB_NOMATCH;
                  goto out;
                }
              else
                {
                  home_dir = (char *) "~"; 
                  malloc_home_dir = 0;
                }
            }
          if (dirname[1] == '\0')
            {
              if (__glibc_unlikely (malloc_dirname))
                free (dirname);
              dirname = home_dir;
              dirlen = strlen (dirname);
              malloc_dirname = malloc_home_dir;
            }
          else
            {
              char *newp;
              size_t home_len = strlen (home_dir);
              int use_alloca = glob_use_alloca (alloca_used, home_len + dirlen);
              if (use_alloca)
                newp = alloca_account (home_len + dirlen, alloca_used);
              else
                {
                  newp = malloc (home_len + dirlen);
                  if (newp == NULL)
                    {
                      if (__glibc_unlikely (malloc_home_dir))
                        free (home_dir);
                      retval = GLOB_NOSPACE;
                      goto out;
                    }
                }
              mempcpy (mempcpy (newp, home_dir, home_len),
                       &dirname[1], dirlen);
              if (__glibc_unlikely (malloc_dirname))
                free (dirname);
              dirname = newp;
              dirlen += home_len - 1;
              malloc_dirname = !use_alloca;
              if (__glibc_unlikely (malloc_home_dir))
                free (home_dir);
            }
          dirname_modified = 1;
        }
      else
        {
#ifndef WINDOWS32
          char *end_name = strchr (dirname, '/');
          char *user_name;
          int malloc_user_name = 0;
          char *unescape = NULL;
          if (!(flags & GLOB_NOESCAPE))
            {
              if (end_name == NULL)
                {
                  unescape = strchr (dirname, '\\');
                  if (unescape)
                    end_name = strchr (unescape, '\0');
                }
              else
                unescape = memchr (dirname, '\\', end_name - dirname);
            }
          if (end_name == NULL)
            user_name = dirname + 1;
          else
            {
              char *newp;
              if (glob_use_alloca (alloca_used, end_name - dirname))
                newp = alloca_account (end_name - dirname, alloca_used);
              else
                {
                  newp = malloc (end_name - dirname);
                  if (newp == NULL)
                    {
                      retval = GLOB_NOSPACE;
                      goto out;
                    }
                  malloc_user_name = 1;
                }
              if (unescape != NULL)
                {
                  char *p = mempcpy (newp, dirname + 1,
                                     unescape - dirname - 1);
                  char *q = unescape;
                  while (*q != '\0')
                    {
                      if (*q == '\\')
                        {
                          if (q[1] == '\0')
                            {
                              if (filename == NULL)
                                *p++ = '\\';
                              break;
                            }
                          ++q;
                        }
                      *p++ = *q++;
                    }
                  *p = '\0';
                }
              else
                *((char *) mempcpy (newp, dirname + 1, end_name - dirname - 1))
                  = '\0';
              user_name = newp;
            }
          {
            struct passwd *p;
            struct scratch_buffer pwtmpbuf;
            scratch_buffer_init (&pwtmpbuf);
#  if defined HAVE_GETPWNAM_R || defined _LIBC
            struct passwd pwbuf;
            while (getpwnam_r (user_name, &pwbuf,
                               pwtmpbuf.data, pwtmpbuf.length, &p)
                   == ERANGE)
              {
                if (!scratch_buffer_grow (&pwtmpbuf))
                  {
                    retval = GLOB_NOSPACE;
                    goto out;
                  }
              }
#  else
            p = getpwnam (user_name);
#  endif
            if (__glibc_unlikely (malloc_user_name))
              free (user_name);
            if (p != NULL)
              {
                size_t home_len = strlen (p->pw_dir);
                size_t rest_len = end_name == NULL ? 0 : strlen (end_name);
                char *d;
                if (__glibc_unlikely (malloc_dirname))
                  free (dirname);
                malloc_dirname = 0;
                if (glob_use_alloca (alloca_used, home_len + rest_len + 1))
                  dirname = alloca_account (home_len + rest_len + 1,
                                            alloca_used);
                else
                  {
                    dirname = malloc (home_len + rest_len + 1);
                    if (dirname == NULL)
                      {
                        scratch_buffer_free (&pwtmpbuf);
                        retval = GLOB_NOSPACE;
                        goto out;
                      }
                    malloc_dirname = 1;
                  }
                d = mempcpy (dirname, p->pw_dir, home_len);
                if (end_name != NULL)
                  d = mempcpy (d, end_name, rest_len);
                *d = '\0';
                dirlen = home_len + rest_len;
                dirname_modified = 1;
              }
            else
              {
                if (flags & GLOB_TILDE_CHECK)
                  {
                    retval = GLOB_NOMATCH;
                    goto out;
                  }
              }
            scratch_buffer_free (&pwtmpbuf);
          }
#endif 
        }
    }
  if (filename == NULL)
    {
      size_t newcount = pglob->gl_pathc + pglob->gl_offs;
      char **new_gl_pathv;
      if (newcount > SIZE_MAX / sizeof (char *) - 2)
        {
        nospace:
          free (pglob->gl_pathv);
          pglob->gl_pathv = NULL;
          pglob->gl_pathc = 0;
          retval = GLOB_NOSPACE;
          goto out;
        }
      new_gl_pathv = realloc (pglob->gl_pathv,
                              (newcount + 2) * sizeof (char *));
      if (new_gl_pathv == NULL)
        goto nospace;
      pglob->gl_pathv = new_gl_pathv;
      if (flags & GLOB_MARK && is_dir (dirname, flags, pglob))
        {
          char *p;
          pglob->gl_pathv[newcount] = malloc (dirlen + 2);
          if (pglob->gl_pathv[newcount] == NULL)
            goto nospace;
          p = mempcpy (pglob->gl_pathv[newcount], dirname, dirlen);
          p[0] = '/';
          p[1] = '\0';
          if (__glibc_unlikely (malloc_dirname))
            free (dirname);
        }
      else
        {
          if (__glibc_unlikely (malloc_dirname))
            pglob->gl_pathv[newcount] = dirname;
          else
            {
              pglob->gl_pathv[newcount] = strdup (dirname);
              if (pglob->gl_pathv[newcount] == NULL)
                goto nospace;
            }
        }
      pglob->gl_pathv[++newcount] = NULL;
      ++pglob->gl_pathc;
      pglob->gl_flags = flags;
      return 0;
    }
  meta = __glob_pattern_type (dirname, !(flags & GLOB_NOESCAPE));
  if (meta & (GLOBPAT_SPECIAL | GLOBPAT_BRACKET))
    {
      size_t i;
      if (!(flags & GLOB_NOESCAPE) && dirlen > 0 && dirname[dirlen - 1] == '\\')
        {
          char *p = (char *) &dirname[dirlen - 1];
          while (p > dirname && p[-1] == '\\') --p;
          if ((&dirname[dirlen] - p) & 1)
            *(char *) &dirname[--dirlen] = '\0';
        }
      if (__glibc_unlikely ((flags & GLOB_ALTDIRFUNC) != 0))
        {
          dirs.gl_opendir = pglob->gl_opendir;
          dirs.gl_readdir = pglob->gl_readdir;
          dirs.gl_closedir = pglob->gl_closedir;
          dirs.gl_stat = pglob->gl_stat;
          dirs.gl_lstat = pglob->gl_lstat;
        }
      status = glob (dirname,
                     ((flags & (GLOB_ERR | GLOB_NOESCAPE
                                | GLOB_ALTDIRFUNC))
                      | GLOB_NOSORT | GLOB_ONLYDIR),
                     errfunc, &dirs);
      if (status != 0)
        {
          if ((flags & GLOB_NOCHECK) == 0 || status != GLOB_NOMATCH)
            {
              retval = status;
              goto out;
            }
          goto no_matches;
        }
      for (i = 0; i < dirs.gl_pathc; ++i)
        {
          size_t old_pathc;
          old_pathc = pglob->gl_pathc;
          status = glob_in_dir (filename, dirs.gl_pathv[i],
                                ((flags | GLOB_APPEND)
                                 & ~(GLOB_NOCHECK | GLOB_NOMAGIC)),
                                errfunc, pglob, alloca_used);
          if (status == GLOB_NOMATCH)
            continue;
          if (status != 0)
            {
              globfree (&dirs);
              globfree (pglob);
              pglob->gl_pathc = 0;
              retval = status;
              goto out;
            }
          if (prefix_array (dirs.gl_pathv[i],
                            &pglob->gl_pathv[old_pathc + pglob->gl_offs],
                            pglob->gl_pathc - old_pathc))
            {
              globfree (&dirs);
              globfree (pglob);
              pglob->gl_pathc = 0;
              retval = GLOB_NOSPACE;
              goto out;
            }
        }
      flags |= GLOB_MAGCHAR;
      if (pglob->gl_pathc + pglob->gl_offs == oldcount)
        {
        no_matches:
          if (flags & GLOB_NOCHECK)
            {
              size_t newcount = pglob->gl_pathc + pglob->gl_offs;
              char **new_gl_pathv;
              if (newcount > SIZE_MAX / sizeof (char *) - 2)
                {
                nospace2:
                  globfree (&dirs);
                  retval = GLOB_NOSPACE;
                  goto out;
                }
              new_gl_pathv = realloc (pglob->gl_pathv,
                                      (newcount + 2) * sizeof (char *));
              if (new_gl_pathv == NULL)
                goto nospace2;
              pglob->gl_pathv = new_gl_pathv;
              pglob->gl_pathv[newcount] = strdup (pattern);
              if (pglob->gl_pathv[newcount] == NULL)
                {
                  globfree (&dirs);
                  globfree (pglob);
                  pglob->gl_pathc = 0;
                  retval = GLOB_NOSPACE;
                  goto out;
                }
              ++pglob->gl_pathc;
              ++newcount;
              pglob->gl_pathv[newcount] = NULL;
              pglob->gl_flags = flags;
            }
          else
            {
              globfree (&dirs);
              retval = GLOB_NOMATCH;
              goto out;
            }
        }
      globfree (&dirs);
    }
  else
    {
      size_t old_pathc = pglob->gl_pathc;
      int orig_flags = flags;
      if (meta & GLOBPAT_BACKSLASH)
        {
          char *p = strchr (dirname, '\\'), *q;
          q = p;
          do
            {
              if (*p == '\\')
                {
                  *q = *++p;
                  --dirlen;
                }
              else
                *q = *p;
              ++q;
            }
          while (*p++ != '\0');
          dirname_modified = 1;
        }
      if (dirname_modified)
        flags &= ~(GLOB_NOCHECK | GLOB_NOMAGIC);
      status = glob_in_dir (filename, dirname, flags, errfunc, pglob,
                            alloca_used);
      if (status != 0)
        {
          if (status == GLOB_NOMATCH && flags != orig_flags
              && pglob->gl_pathc + pglob->gl_offs == oldcount)
            {
              dirs.gl_pathv = NULL;
              flags = orig_flags;
              goto no_matches;
            }
          retval = status;
          goto out;
        }
      if (dirlen > 0)
        {
          if (prefix_array (dirname,
                            &pglob->gl_pathv[old_pathc + pglob->gl_offs],
                            pglob->gl_pathc - old_pathc))
            {
              globfree (pglob);
              pglob->gl_pathc = 0;
              retval = GLOB_NOSPACE;
              goto out;
            }
        }
    }
  if (flags & GLOB_MARK)
    {
      size_t i;
      for (i = oldcount; i < pglob->gl_pathc + pglob->gl_offs; ++i)
        if (is_dir (pglob->gl_pathv[i], flags, pglob))
          {
            size_t len = strlen (pglob->gl_pathv[i]) + 2;
            char *new = realloc (pglob->gl_pathv[i], len);
            if (new == NULL)
              {
                globfree (pglob);
                pglob->gl_pathc = 0;
                retval = GLOB_NOSPACE;
                goto out;
              }
            strcpy (&new[len - 2], "/");
            pglob->gl_pathv[i] = new;
          }
    }
  if (!(flags & GLOB_NOSORT))
    {
      qsort (&pglob->gl_pathv[oldcount],
             pglob->gl_pathc + pglob->gl_offs - oldcount,
             sizeof (char *), collated_compare);
    }
 out:
  if (__glibc_unlikely (malloc_dirname))
    free (dirname);
  return retval;
}