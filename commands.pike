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
	int inputhook(string line,mapping(string:mixed) subw) {}
	int outputhook(string line,mapping(string:mixed) conn) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) G->G->hooks[cmdname]=this;
	}
}
class commandhook //If you want both, you need to call both create() functions.
{
	inherit command;
	inherit hook;
	void create(string name) {command::create(name); hook::create(name);}
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
	add_constant("commandhook",commandhook);
}
