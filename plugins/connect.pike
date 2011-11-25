inherit cmdbase;

mapping(string:string) host=(["threshold":"thresholdrpg.com 23","minstrelhall":"gideon.rosuav.com 221"]);

int process(string param)
{
	if (param=="") param="threshold";
	if (!host[param]) {say("%% Connect to what?"); return 1;}
	sscanf(host[param],"%s %d",G->G->conn_host,G->G->conn_port);
	G->G->connect();
	return 1;
}
