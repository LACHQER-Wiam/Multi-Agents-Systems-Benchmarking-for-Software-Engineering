static bool tipc_crypto_key_rcv(struct tipc_crypto *rx, struct tipc_msg *hdr)
{
	struct tipc_crypto *tx = tipc_net(rx->net)->crypto_tx;
	struct tipc_aead_key *skey = NULL;
	u16 key_gen = msg_key_gen(hdr);
	u16 size = msg_data_sz(hdr);
	u8 *data = msg_data(hdr);
	spin_lock(&rx->lock);
	if (unlikely(rx->skey || (key_gen == rx->key_gen && rx->key.keys))) {
		pr_err("%s: key existed <%p>, gen %d vs %d\n", rx->name,
		       rx->skey, key_gen, rx->key_gen);
		goto exit;
	}
	skey = kmalloc(size, GFP_ATOMIC);
	if (unlikely(!skey)) {
		pr_err("%s: unable to allocate memory for skey\n", rx->name);
		goto exit;
	}
	skey->keylen = ntohl(*((__be32 *)(data + TIPC_AEAD_ALG_NAME)));
	memcpy(skey->alg_name, data, TIPC_AEAD_ALG_NAME);
	memcpy(skey->key, data + TIPC_AEAD_ALG_NAME + sizeof(__be32),
	       skey->keylen);
	if (unlikely(size != tipc_aead_key_size(skey))) {
		kfree(skey);
		skey = NULL;
		goto exit;
	}
	rx->key_gen = key_gen;
	rx->skey_mode = msg_key_mode(hdr);
	rx->skey = skey;
	rx->nokey = 0;
	mb(); 
exit:
	spin_unlock(&rx->lock);
	if (likely(skey && queue_delayed_work(tx->wq, &rx->work, 0)))
		return true;
	return false;
}