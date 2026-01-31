static void mkiss_close(struct tty_struct *tty)
{
	struct mkiss *ax;
	write_lock_irq(&disc_data_lock);
	ax = tty->disc_data;
	tty->disc_data = NULL;
	write_unlock_irq(&disc_data_lock);
	if (!ax)
		return;
	if (!refcount_dec_and_test(&ax->refcnt))
		wait_for_completion(&ax->dead);
	netif_stop_queue(ax->dev);
	unregister_netdev(ax->dev);
	kfree(ax->rbuff);
	kfree(ax->xbuff);
	ax->tty = NULL;
	free_netdev(ax->dev);
}