set_fflags_platform(struct archive_write_disk *a, int fd, const char *name,
    mode_t mode, unsigned long set, unsigned long clear)
{
	int		 ret;
	int		 myfd = fd;
	int newflags, oldflags;
	const int sf_mask = 0
#if defined(FS_IMMUTABLE_FL)
	    | FS_IMMUTABLE_FL
#elif defined(EXT2_IMMUTABLE_FL)
	    | EXT2_IMMUTABLE_FL
#endif
#if defined(FS_APPEND_FL)
	    | FS_APPEND_FL
#elif defined(EXT2_APPEND_FL)
	    | EXT2_APPEND_FL
#endif
#if defined(FS_JOURNAL_DATA_FL)
	    | FS_JOURNAL_DATA_FL
#endif
	;
	if (set == 0 && clear == 0)
		return (ARCHIVE_OK);
	if (!S_ISREG(mode) && !S_ISDIR(mode))
		return (ARCHIVE_OK);
	if (myfd < 0) {
		myfd = open(name, O_RDONLY | O_NONBLOCK | O_BINARY |
		    O_CLOEXEC | O_NOFOLLOW);
		__archive_ensure_cloexec_flag(myfd);
	}
	if (myfd < 0)
		return (ARCHIVE_OK);
	ret = ARCHIVE_OK;
	if (ioctl(myfd,
#ifdef FS_IOC_GETFLAGS
	    FS_IOC_GETFLAGS,
#else
	    EXT2_IOC_GETFLAGS,
#endif
	    &oldflags) < 0)
		goto fail;
	newflags = (oldflags & ~clear) | set;
	if (ioctl(myfd,
#ifdef FS_IOC_SETFLAGS
	    FS_IOC_SETFLAGS,
#else
	    EXT2_IOC_SETFLAGS,
#endif
	    &newflags) >= 0)
		goto cleanup;
	if (errno != EPERM)
		goto fail;
	newflags &= ~sf_mask;
	oldflags &= sf_mask;
	newflags |= oldflags;
	if (ioctl(myfd,
#ifdef FS_IOC_SETFLAGS
	    FS_IOC_SETFLAGS,
#else
	    EXT2_IOC_SETFLAGS,
#endif
	    &newflags) >= 0)
		goto cleanup;
fail:
	archive_set_error(&a->archive, errno,
	    "Failed to set file flags");
	ret = ARCHIVE_WARN;
cleanup:
	if (fd < 0)
		close(myfd);
	return (ret);
}