//Install this plugin, then send the main process a SIGHUP to get a quick dump of thread status.

void showthreads()
{
	if (mixed ex=catch {foreach (Thread.all_threads(),object t) werror("\nThread %d:\n%s\n",t->id_number(),describe_backtrace(t->backtrace()));})
		werror("Exception while dumping threads:\n%s\n",describe_error(ex));
}


void create(string name)
{
	signal(signum("SIGHUP"),showthreads);
}
