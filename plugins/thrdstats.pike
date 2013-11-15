//Install this plugin, then send the main process a SIGHUP to get a quick dump of thread status.

/**
 * Provides information about currently running threads.
 */
void showthreads()
{
	if (mixed ex=catch {foreach (Thread.all_threads(),object t) werror("\nThread %d:\n%s\n",t->id_number(),describe_backtrace(t->backtrace()));})
		werror("Exception while dumping threads:\n%s\n",describe_error(ex));
}

void create(string name)
{
	catch {signal(signum("SIGHUP"),showthreads);}; //This doesn't work on Windows. Quietly suppress the error and abandon the feature.
}
