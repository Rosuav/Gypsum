inherit command;

constant plugin_active_by_default = 1;
constant docstring=#"
Implements the /connect, /dc, /worlds, and /c commands.

If you don't have this plugin active, you can still connect via the File menu,
but will not be able to use the shortcut reconnect-to-last-world feature.
There is generally no reason to unload this plugin.
";

int process(string param,mapping(string:mixed) subw)
{
	if (param=="" && !(param=subw->world)) return listworlds("",subw);
	G->G->window->connect(param,subw);
	return 1;
}

int dc(string param,mapping(string:mixed) subw) {G->G->window->connect(0,subw); return 1;}

int listworlds(string param,mapping(string:mixed) subw)
{
	say(subw,"%% The following worlds are recognized:");
	say(subw,"%%%%   %-14s %-20s %-20s %4s","Keyword","Name","Host","Port");
	mapping(string:mapping(string:mixed)) worlds=persist["worlds"];
	foreach (sort(indices(worlds)),string kwd)
	{
		mapping info=worlds[kwd];
		say(subw,"%%%%   %-14s %-20s %-20s %4d",kwd,info->name,info->host,info->port);
	}
	say(subw,"%% Connect to any of the above worlds with: /connect keyword");
	say(subw,"%% Connect to any other MUD with: /connect host:port");
	return 1;
}

protected void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
	G->G->commands->c=process;
	G->G->commands->worlds=listworlds;
}
