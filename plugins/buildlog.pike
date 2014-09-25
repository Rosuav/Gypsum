//Debug help: enable/disable/parse the build log
inherit command;

constant plugin_active_by_default = 1;
constant docstring=#"
The build log keeps track of every file built this session.
It's helpful for tracking down issues with plugins, or with
code left lurking around for whatever reason. If there are
multiple versions of a file in memory, it's possible that
different ones will be called on by different code, which is
potentially very confusing. You can safely ignore this if you
are not developing/debugging something.

Type \"/buildlog help\" for usage information.
";

int process(string param,mapping(string:mixed) subw)
{
	switch (param)
	{
		case "on": case "activate":
			if (G->G->buildlog) say(subw,"%% Build log already active, '/buildlog off' to deactivate.");
			else {G->G->buildlog=([]); say(subw,"%% Build log activated, '/buildlog off' to deactivate.");}
			return 1;
		case "off": case "deactivate":
			if (!m_delete(G->G,"buildlog")) say(subw,"%% Build log wasn't active, '/buildlog on' to activate.");
			else say(subw,"%% Build log deactivated, '/buildlog on' to reactivate.");
			return 1;
		case "":
			if (G->G->buildlog)
			{
				say(subw,"%%%% Running GC... %d",gc());
				foreach (G->G->buildlog;string fn;mapping objects) if (sizeof(objects)>1)
					say(subw,"%%%% %s:%{ %d%}",fn,sort(indices(objects)));
				say(subw,"%%%% %d total file names listed.",sizeof(G->G->buildlog));
				return 1;
			}
			//else fall through
		case "help": default:
			say(subw,"%% "+replace((docstring/"\n\n")[0],"\n","\n%% "));
			say(subw,"%% Usage:");
			say(subw,"%% /buildlog on - activate the log");
			say(subw,"%% /buildlog off - deactivate the log");
			say(subw,"%% /buildlog - garbage collect, then list which files have more");
			say(subw,"%%     than one version active (and give a count of total files)");
			say(subw,"%% /buildlog help - show this info");
			return 1;
	}
}
