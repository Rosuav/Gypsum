//Command function base.

mapping(string:mixed) command=([]);

class cmdbase
{
	int process(string param) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) G->G->command[cmdname]=process;
	}
}

void create(string name)
{
	if (!G->G->command)
	{
		G->G->command=command;
	}
	else
	{
		command=G->G->command;
	}
	add_constant("cmdbase",cmdbase);
}
