//Command function base.

mapping(string:mixed) commands=([]);
mapping(string:mixed) hooks=([]);

class command
{
	int process(string param) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) G->G->commands[cmdname]=process;
	}
}

class hook
{
	int inputhook(string line) {}
	int outputhook(string line) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) G->G->hooks[cmdname]=this;
	}
}

void create(string name)
{
	if (!G->G->commands)
	{
		G->G->commands=commands;
		G->G->hooks=hooks;
	}
	else
	{
		commands=G->G->commands;
		hooks=G->G->hooks;
	}
	add_constant("command",command);
	add_constant("hook",hook);
}
