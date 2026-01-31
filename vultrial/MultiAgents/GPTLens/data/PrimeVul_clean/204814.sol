static void sixpack_close(struct tty_struct *tty)
{
	struct sixpack *sp;
	write_lock_irq(&disc_data_lock);
	sp = tty->disc_data;
	tty->disc_data = NULL;
	write_unlock_irq(&disc_data_lock);
	if (!sp)
		return;
	if (!refcount_dec_and_test(&sp->refcnt))
		wait_for_completion(&sp->dead);
	netif_stop_queue(sp->dev);
	del_timer_sync(&sp->tx_t);
	del_timer_sync(&sp->resync_t);
	unregister_netdev(sp->dev);
	kfree(sp->rbuff);
	kfree(sp->xbuff);
	free_netdev(sp->dev);
}