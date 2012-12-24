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
	if (newtab) G->G->window->addtab()->connect(info);
	else G->G->window->connect(info);
	return 1;
}

int dc(string param) {G->G->window->connect(0); return 1;}

void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
	G->G->commands->c=process;
}
