inherit command;

mapping(string:mapping) worlds=([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG"]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall"]),
]);

int process(string param)
{
	if (param=="") param="threshold";
	if (!worlds[param]) {say("%% Connect to what?"); return 1;}
	G->G->connect(worlds[param]);
	return 1;
}
