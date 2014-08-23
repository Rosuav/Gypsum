//Debug help: enable/disable/show the build log
inherit command;

int process(string param,mapping(string:mixed) subw)
{
	switch (param)
	{
		case "":
			if (!G->G->buildlog) {say(subw,"%% Build log not active, '/buildlog on' to activate."); return 1;}
			say(subw,"%%%% Running GC... %d",gc());
			foreach (G->G->buildlog;string fn;mapping objects) if (sizeof(objects)>1)
				say(subw,"%%%% %s:%{ %d%}",fn,sort(indices(objects)));
			say(subw,"%%%% %d total file names listed.",sizeof(G->G->buildlog));
			return 1;
		case "on": case "activate":
			if (G->G->buildlog) say(subw,"%% Build log already active, '/buildlog off' to deactivate.");
			else {G->G->buildlog=([]); say(subw,"%% Build log activated, '/buildlog off' to deactivate.");}
			return 1;
		case "off": case "deactivate":
			if (!m_delete(G->G,"buildlog")) say(subw,"%% Build log wasn't active, '/buildlog on' to activate.");
			else say(subw,"%% Build log deactivated, '/buildlog on' to reactivate.");
			return 1;
		default:
			say(subw,"%% Unrecognized subcommand.");
			return 1;
	}
}
