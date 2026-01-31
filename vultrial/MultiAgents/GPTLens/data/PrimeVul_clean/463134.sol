static int write_entry(struct mailbox *mailbox,
                       unsigned int uid,
                       const char *entry,
                       const char *userid,
                       const struct buf *value,
                       int ignorequota,
                       int silent,
                       const struct annotate_metadata *mdata,
                       int maywrite)
{
    char key[MAX_MAILBOX_PATH+1];
    int keylen, r;
    annotate_db_t *d = NULL;
    struct buf oldval = BUF_INITIALIZER;
    const char *mboxname = mailbox ? mailbox->name : "";
    modseq_t modseq = mdata ? mdata->modseq : 0;
    r = _annotate_getdb(mboxname, uid, CYRUSDB_CREATE, &d);
    if (r)
        return r;
    annotate_begin(d);
    keylen = make_key(mboxname, uid, entry, userid, key, sizeof(key));
    struct annotate_metadata oldmdata;
    r = read_old_value(d, key, keylen, &oldval, &oldmdata);
    if (r) goto out;
    if (oldval.len == value->len && (!value->len || !memcmp(oldval.s, value->s, value->len)))
        goto out;
    if (!maywrite) {
        r = IMAP_PERMISSION_DENIED;
        if (r) goto out;
    }
    if (mailbox) {
        if (!ignorequota) {
            quota_t qdiffs[QUOTA_NUMRESOURCES] = QUOTA_DIFFS_DONTCARE_INITIALIZER;
            qdiffs[QUOTA_ANNOTSTORAGE] = value->len - (quota_t)oldval.len;
            r = mailbox_quota_check(mailbox, qdiffs);
            if (r) goto out;
        }
        mailbox_annot_changed(mailbox, uid, entry, userid, &oldval, value, silent);
        if (uid && !mdata) {
            modseq = mailbox->i.highestmodseq;
        }
    }
    if (!value->len && !uid) {
#if DEBUG
        syslog(LOG_ERR, "write_entry: deleting key %s from %s",
                key_as_string(d, key, keylen), d->filename);
#endif
        do {
            r = cyrusdb_delete(d->db, key, keylen, tid(d), 1);
        } while (r == CYRUSDB_AGAIN);
    }
    else {
        struct buf data = BUF_INITIALIZER;
        unsigned char flags = 0;
        if (!value->len || value->s == NULL) {
            flags |= ANNOTATE_FLAG_DELETED;
        }
        else {
            if (!userid) goto out;
        }
        make_entry(&data, value, modseq, flags);
#if DEBUG
        syslog(LOG_ERR, "write_entry: storing key %s (value: %s) to %s (modseq=" MODSEQ_FMT ")",
                key_as_string(d, key, keylen), value->s, d->filename, modseq);
#endif
        do {
            r = cyrusdb_store(d->db, key, keylen, data.s, data.len, tid(d));
        } while (r == CYRUSDB_AGAIN);
        buf_free(&data);
    }
    if (!mailbox)
        sync_log_annotation("");
out:
    annotate_putdb(&d);
    buf_free(&oldval);
    return r;
}