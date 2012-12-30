//Command function base.

class command
{
	int process(string param,mapping(string:mixed) subw) {}
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

class window
{
	mapping(string:mixed) win=([]);
	void makewindow() {}
	void dosignals() {m_delete(win,"signals");}
	void create(string name)
	{
		if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;
		if (!win->mainwindow) makewindow();
		win->mainwindow->show_all();
		dosignals();
	}
	void showwindow()
	{
		if (!win->mainwindow) {makewindow(); dosignals();}
		win->mainwindow->set_no_show_all(0)->show_all();
	}
}

void create(string name)
{
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
	if (!G->G->windows) G->G->windows=([]);
	add_constant("command",command);
	add_constant("hook",hook);
	add_constant("window",window);
}
