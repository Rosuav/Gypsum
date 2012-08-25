inherit command;

mapping(string:mapping) worlds=([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG"]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall"]),
]);

int process(string param)
{
	if (param=="") param="minstrelhall";
	if (!worlds[param]) {say("%% Connect to what?"); return 1;}
	G->G->window->connect(worlds[param]);
	return 1;
}

int dc(string param) {G->G->window->connect(0); return 1;}

void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
}
