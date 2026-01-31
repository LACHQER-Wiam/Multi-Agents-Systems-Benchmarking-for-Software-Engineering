int ssl3_get_new_session_ticket(SSL *s)
{
    int ok, al, ret = 0, ticklen;
    long n;
    const unsigned char *p;
    unsigned char *d;
    n = s->method->ssl_get_message(s,
                                   SSL3_ST_CR_SESSION_TICKET_A,
                                   SSL3_ST_CR_SESSION_TICKET_B,
                                   SSL3_MT_NEWSESSION_TICKET, 16384, &ok);
    if (!ok)
        return ((int)n);
    if (n < 6) {
        al = SSL_AD_DECODE_ERROR;
        SSLerr(SSL_F_SSL3_GET_NEW_SESSION_TICKET, SSL_R_LENGTH_MISMATCH);
        goto f_err;
    }
    p = d = (unsigned char *)s->init_msg;
    if (s->session->session_id_length > 0) {
        int i = s->session_ctx->session_cache_mode;
        SSL_SESSION *new_sess;
        if (i & SSL_SESS_CACHE_CLIENT) {
            if (i & SSL_SESS_CACHE_NO_INTERNAL_STORE) {
                if (s->session_ctx->remove_session_cb != NULL)
                    s->session_ctx->remove_session_cb(s->session_ctx,
                                                      s->session);
            } else {
                SSL_CTX_remove_session(s->session_ctx, s->session);
            }
        }
        if ((new_sess = ssl_session_dup(s->session, 0)) == 0) {
            al = SSL_AD_INTERNAL_ERROR;
            SSLerr(SSL_F_SSL3_GET_NEW_SESSION_TICKET, ERR_R_MALLOC_FAILURE);
            goto f_err;
        }
        SSL_SESSION_free(s->session);
        s->session = new_sess;
    }
    n2l(p, s->session->tlsext_tick_lifetime_hint);
    n2s(p, ticklen);
    if (ticklen + 6 != n) {
        al = SSL_AD_DECODE_ERROR;
        SSLerr(SSL_F_SSL3_GET_NEW_SESSION_TICKET, SSL_R_LENGTH_MISMATCH);
        goto f_err;
    }
    if (s->session->tlsext_tick) {
        OPENSSL_free(s->session->tlsext_tick);
        s->session->tlsext_ticklen = 0;
    }
    s->session->tlsext_tick = OPENSSL_malloc(ticklen);
    if (!s->session->tlsext_tick) {
        SSLerr(SSL_F_SSL3_GET_NEW_SESSION_TICKET, ERR_R_MALLOC_FAILURE);
        goto err;
    }
    memcpy(s->session->tlsext_tick, p, ticklen);
    s->session->tlsext_ticklen = ticklen;
    EVP_Digest(p, ticklen,
               s->session->session_id, &s->session->session_id_length,
# ifndef OPENSSL_NO_SHA256
               EVP_sha256(), NULL);
# else
               EVP_sha1(), NULL);
# endif
    ret = 1;
    return (ret);
 f_err:
    ssl3_send_alert(s, SSL3_AL_FATAL, al);
 err:
    s->state = SSL_ST_ERR;
    return (-1);
}