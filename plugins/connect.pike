inherit command;

constant plugin_active_by_default = 1;

/**
 * Displays the connection window dialog or attempts a connection to a world.
 *
 * @param 	The world to which to connect, or dlg option.
 * @return 	always returns 1
 */
int process(string param,mapping(string:mixed) subw)
{
	if (param=="" && !(param=subw->world)) return listworlds("",subw);
	mapping info=persist["worlds"][param];
	if (!info)
	{
		if (sscanf(param,"%s%*[ :]%d",string host,int port) && port) info=(["host":host,"port":port,"name":sprintf("%s : %d",host,port)]);
		else {say(subw,"%% Connect to what?"); return 1;}
	}
	G->G->window->connect(info,param,subw || G->G->window->subwindow("New tab"));
	return 1;
}

/**
 * Disconnect from current world
 */
int dc(string param,mapping(string:mixed) subw) {G->G->window->connect(0,subw); return 1;}

/**
 * List all the worlds in the global list to the provided sub window
 *
 * @param param Unused
 * @param subw	The window in which to print the world list.
 */
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

void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
	G->G->commands->c=process;
	G->G->commands->worlds=listworlds;
}
