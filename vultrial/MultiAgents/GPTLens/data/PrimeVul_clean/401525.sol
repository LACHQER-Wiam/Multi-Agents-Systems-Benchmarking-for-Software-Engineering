void update_process_times(int user_tick)
{
	struct task_struct *p = current;
	account_process_tick(p, user_tick);
	run_local_timers();
	rcu_sched_clock_irq(user_tick);
#ifdef CONFIG_IRQ_WORK
	if (in_irq())
		irq_work_tick();
#endif
	scheduler_tick();
	if (IS_ENABLED(CONFIG_POSIX_TIMERS))
		run_posix_cpu_timers();
	this_cpu_add(net_rand_state.s1, rol32(jiffies, 24) + user_tick);
}