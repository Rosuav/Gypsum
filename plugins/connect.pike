inherit command;

mapping(string:mapping) worlds=([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG"]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall"]),
]);

int process(string param,int|void newtab)
{
	if (param=="") param=G->G->window->recon() || "minstrelhall";
	mapping info=worlds[param];
	if (!info)
	{
		if (sscanf(param,"%s%*[ :]%d",string host,int port) && port) info=(["host":host,"port":port,"name":sprintf("%s : %d",host,port)]);
		else {say("%% Connect to what?"); return 1;}
	}
	info->recon=param;
	G->G->window->connect(info,newtab && G->G->window->subwindow("New tab"));
	return 1;
}

int dc(string param) {G->G->window->connect(0); return 1;}

int listworlds(string param)
{
	say("%% The following worlds are recognized:");
	say(sprintf("%%%%   %-14s %-20s %-20s %4s","Keyword","Name","Host","Port"));
	foreach (sort(indices(worlds)),string kwd)
	{
		mapping info=worlds[kwd];
		say(sprintf("%%%%   %-14s %-20s %-20s %4d",kwd,info->name,info->host,info->port));
	}
	say("%% Connect to any of the above worlds with: /connect keyword");
	say("%% Connect to any other MUD with: /connect host:port");
	return 1;
}

void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
	G->G->commands->c=process;
	G->G->commands->worlds=listworlds;
}
