setup_seccomp (FlatpakBwrap   *bwrap,
               const char     *arch,
               gulong          allowed_personality,
               FlatpakRunFlags run_flags,
               GError        **error)
{
  gboolean multiarch = (run_flags & FLATPAK_RUN_FLAG_MULTIARCH) != 0;
  gboolean devel = (run_flags & FLATPAK_RUN_FLAG_DEVEL) != 0;
  __attribute__((cleanup (cleanup_seccomp))) scmp_filter_ctx seccomp = NULL;
  struct
  {
    int                  scall;
    int                  errnum;
    struct scmp_arg_cmp *arg;
  } syscall_blocklist[] = {
    {SCMP_SYS (syslog), EPERM},
    {SCMP_SYS (uselib), EPERM},
    {SCMP_SYS (acct), EPERM},
    {SCMP_SYS (modify_ldt), EPERM},
    {SCMP_SYS (quotactl), EPERM},
    {SCMP_SYS (add_key), EPERM},
    {SCMP_SYS (keyctl), EPERM},
    {SCMP_SYS (request_key), EPERM},
    {SCMP_SYS (move_pages), EPERM},
    {SCMP_SYS (mbind), EPERM},
    {SCMP_SYS (get_mempolicy), EPERM},
    {SCMP_SYS (set_mempolicy), EPERM},
    {SCMP_SYS (migrate_pages), EPERM},
    {SCMP_SYS (unshare), EPERM},
    {SCMP_SYS (setns), EPERM},
    {SCMP_SYS (mount), EPERM},
    {SCMP_SYS (umount), EPERM},
    {SCMP_SYS (umount2), EPERM},
    {SCMP_SYS (pivot_root), EPERM},
#if defined(__s390__) || defined(__s390x__) || defined(__CRIS__)
    {SCMP_SYS (clone), EPERM, &SCMP_A1 (SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER)},
#else
    {SCMP_SYS (clone), EPERM, &SCMP_A0 (SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER)},
#endif
    {SCMP_SYS (ioctl), EPERM, &SCMP_A1 (SCMP_CMP_MASKED_EQ, 0xFFFFFFFFu, (int) TIOCSTI)},
    {SCMP_SYS (open_tree), ENOSYS},
    {SCMP_SYS (move_mount), ENOSYS},
    {SCMP_SYS (fsopen), ENOSYS},
    {SCMP_SYS (fsconfig), ENOSYS},
    {SCMP_SYS (fsmount), ENOSYS},
    {SCMP_SYS (fspick), ENOSYS},
    {SCMP_SYS (mount_setattr), ENOSYS},
  };
  struct
  {
    int                  scall;
    int                  errnum;
    struct scmp_arg_cmp *arg;
  } syscall_nondevel_blocklist[] = {
    {SCMP_SYS (perf_event_open), EPERM},
    {SCMP_SYS (personality), EPERM, &SCMP_A0 (SCMP_CMP_NE, allowed_personality)},
    {SCMP_SYS (ptrace), EPERM}
  };
  struct
  {
    int             family;
    FlatpakRunFlags flags_mask;
  } socket_family_allowlist[] = {
    { AF_UNSPEC, 0 },
    { AF_LOCAL, 0 },
    { AF_INET, 0 },
    { AF_INET6, 0 },
    { AF_NETLINK, 0 },
    { AF_CAN, FLATPAK_RUN_FLAG_CANBUS },
    { AF_BLUETOOTH, FLATPAK_RUN_FLAG_BLUETOOTH },
  };
  int last_allowed_family;
  int i, r;
  g_auto(GLnxTmpfile) seccomp_tmpf  = { 0, };
  seccomp = seccomp_init (SCMP_ACT_ALLOW);
  if (!seccomp)
    return flatpak_fail_error (error, FLATPAK_ERROR_SETUP_FAILED, _("Initialize seccomp failed"));
  if (arch != NULL)
    {
      uint32_t arch_id = 0;
      const uint32_t *extra_arches = NULL;
      if (strcmp (arch, "i386") == 0)
        {
          arch_id = SCMP_ARCH_X86;
        }
      else if (strcmp (arch, "x86_64") == 0)
        {
          arch_id = SCMP_ARCH_X86_64;
          extra_arches = seccomp_x86_64_extra_arches;
        }
      else if (strcmp (arch, "arm") == 0)
        {
          arch_id = SCMP_ARCH_ARM;
        }
#ifdef SCMP_ARCH_AARCH64
      else if (strcmp (arch, "aarch64") == 0)
        {
          arch_id = SCMP_ARCH_AARCH64;
          extra_arches = seccomp_aarch64_extra_arches;
        }
#endif
      if (arch_id != 0)
        {
          r = seccomp_arch_add (seccomp, arch_id);
          if (r < 0 && r != -EEXIST)
            return flatpak_fail_error (error, FLATPAK_ERROR_SETUP_FAILED, _("Failed to add architecture to seccomp filter"));
          if (multiarch && extra_arches != NULL)
            {
              for (i = 0; extra_arches[i] != 0; i++)
                {
                  r = seccomp_arch_add (seccomp, extra_arches[i]);
                  if (r < 0 && r != -EEXIST)
                    return flatpak_fail_error (error, FLATPAK_ERROR_SETUP_FAILED, _("Failed to add multiarch architecture to seccomp filter"));
                }
            }
        }
    }
  for (i = 0; i < G_N_ELEMENTS (syscall_blocklist); i++)
    {
      int scall = syscall_blocklist[i].scall;
      int errnum = syscall_blocklist[i].errnum;
      g_return_val_if_fail (errnum == EPERM || errnum == ENOSYS, FALSE);
      if (syscall_blocklist[i].arg)
        r = seccomp_rule_add (seccomp, SCMP_ACT_ERRNO (errnum), scall, 1, *syscall_blocklist[i].arg);
      else
        r = seccomp_rule_add (seccomp, SCMP_ACT_ERRNO (errnum), scall, 0);
      if (r < 0 && r == -EFAULT )
        return flatpak_fail_error (error, FLATPAK_ERROR_SETUP_FAILED, _("Failed to block syscall %d"), scall);
    }
  if (!devel)
    {
      for (i = 0; i < G_N_ELEMENTS (syscall_nondevel_blocklist); i++)
        {
          int scall = syscall_nondevel_blocklist[i].scall;
          int errnum = syscall_nondevel_blocklist[i].errnum;
          g_return_val_if_fail (errnum == EPERM || errnum == ENOSYS, FALSE);
          if (syscall_nondevel_blocklist[i].arg)
            r = seccomp_rule_add (seccomp, SCMP_ACT_ERRNO (errnum), scall, 1, *syscall_nondevel_blocklist[i].arg);
          else
            r = seccomp_rule_add (seccomp, SCMP_ACT_ERRNO (errnum), scall, 0);
          if (r < 0 && r == -EFAULT )
            return flatpak_fail_error (error, FLATPAK_ERROR_SETUP_FAILED, _("Failed to block syscall %d"), scall);
        }
    }
          seccomp_rule_add_exact (seccomp, SCMP_ACT_ERRNO (EAFNOSUPPORT), SCMP_SYS (socket), 1, SCMP_A0 (SCMP_CMP_EQ, disallowed));
        }
      last_allowed_family = family;
    }
  seccomp_rule_add_exact (seccomp, SCMP_ACT_ERRNO (EAFNOSUPPORT), SCMP_SYS (socket), 1, SCMP_A0 (SCMP_CMP_GE, last_allowed_family + 1));
  if (!glnx_open_anonymous_tmpfile_full (O_RDWR | O_CLOEXEC, "/tmp", &seccomp_tmpf, error))
    return FALSE;
  if (seccomp_export_bpf (seccomp, seccomp_tmpf.fd) != 0)
    return flatpak_fail_error (error, FLATPAK_ERROR_SETUP_FAILED, _("Failed to export bpf"));
  lseek (seccomp_tmpf.fd, 0, SEEK_SET);
  flatpak_bwrap_add_args_data_fd (bwrap,
                                  "--seccomp", glnx_steal_fd (&seccomp_tmpf.fd), NULL);
  return TRUE;
}