inherit command;

mapping(string:mapping) worlds=([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG"]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall"]),
]);

int process(string param)
{
	if (param=="") param=G->G->window->recon() || "minstrelhall";
	if (!worlds[param])
	{
		if (sscanf(param,"%s %d",string host,int port) && port) G->G->window->connect((["host":host,"port":port,"name":sprintf("%s : %d",host,port),"recon":param]));
		else say("%% Connect to what?");
		return 1;
	}
	worlds[param]->recon=param;
	G->G->window->connect(worlds[param]);
	return 1;
}

int dc(string param) {G->G->window->connect(0); return 1;}

void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
}
