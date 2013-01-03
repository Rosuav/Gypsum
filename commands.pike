//Command function base.

//Plugin that implements a command derived from its name
class command
{
	int process(string param,mapping(string:mixed) subw) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) G->G->commands[cmdname]=process;
	}
}

//Plugin that hooks input and/or output
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

//Generic window handler. If a plugin inherits this, it will normally show the window on startup and keep it there, though other patterns are available.
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

//Base class for a configuration dialog. Permits the setup of anything where you have a list of keyworded items, can create/retrieve/update/delete them by keyword.
class configdlg
{
	inherit window;
	//Provide me...
	mapping(string:mixed) windowprops=(["title":"Configure"]);
	GTK2.Widget make_content() { } //Create and return a widget (most likely a layout widget) representing all the custom content. Must assign to win->kwd a GTK2.Entry for editing the keyword.
	mapping(string:mixed) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping.
	string actionbtn; //If set, a special "action button" will be included, otherwise not. This is its caption.
	void action_callback() { } //Callback when the action button is clicked (provide if actionbtn is set)
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping. The mapping is already inside items[], so this is also a good place to trigger a persist[] save.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	//... end provide me.

	//Return the keyword of the selected item, or 0 if none (or new) is selected
	string selecteditem()
	{
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		return (kwd!="-- New --") && kwd; //TODO: Recognize the "New" entry by something other than its text
	}

	//Is there no simpler way to do this?
	string get_text(GTK2.TextView mle)
	{
		object buf=mle->get_buffer();
		return buf->get_text(buf->get_start_iter(),buf->get_end_iter(),0);
	}

	void pb_save()
	{
		string oldkwd=selecteditem();
		string newkwd=win->kwd->get_text();
		if (newkwd=="") return; //TODO: Be a tad more courteous.
		mapping info=m_delete(items,oldkwd) || ([]);
		items[newkwd]=info;
		save_content(info);
		if (newkwd!=oldkwd)
		{
			[object iter,object store]=win->sel->get_selected();
			if (!oldkwd) win->sel->select_iter(iter=store->append());
			store->set_value(iter,0,newkwd);
		}
	}

	void selchanged()
	{
		string kwd=selecteditem();
		mapping info=items[kwd] || ([]);
		win->kwd->set_text(kwd || "");
		load_content(info);
	}

	void makewindow()
	{
		object ls=GTK2.ListStore(({"string"}));
		foreach (sort(indices(items)),string kwd) ls->set_value(ls->append(),0,kwd); //Is there no simpler way to pre-fill the liststore?
		ls->set_value(ls->append(),0,"-- New --");
		win->mainwindow=GTK2.Window(windowprops+(["transient-for":G->G->window->mainwindow]))
			->add(GTK2.Vbox(0,10)
				->add(GTK2.Hbox(0,5)
					->add(win->list=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
						->append_column(GTK2.TreeViewColumn("Item",GTK2.CellRendererText(),"text",0))
					)
					->add(make_content())
				)
				->pack_end(
					(actionbtn?GTK2.Hbox(0,10)
					->add(win->pb_action=GTK2.Button((["label":actionbtn,"use-underline":1])))
					:GTK2.Hbox(0,10))
					->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
					->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1])))
					->add(win->pb_close=GTK2.Button((["label":"_Close","use-underline":1])))
				,0,0,0)
			);
		win->sel=win->list->get_selection();
	}

	void dosignals()
	{
		win->signals=({
			actionbtn && gtksignal(win->pb_action,"clicked",action_callback),
			gtksignal(win->pb_save,"clicked",pb_save),
			gtksignal(win->pb_close,"clicked",win->mainwindow->hide),
			gtksignal(win->sel,"changed",selchanged),
		});
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
	add_constant("configdlg",configdlg);
}
