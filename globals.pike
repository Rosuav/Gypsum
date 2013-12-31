/**
 * Load up the globals and apply those which need changing
 */
void create(string n,string which)
{
	array(string) arr=indices(this);
	if (which && which!="") arr=which/" ";
	foreach (arr,string f) if (f!="create") add_gypsum_constant(f,this[f]);
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
	if (!G->G->windows) G->G->windows=([]);
	if (!G->G->statustexts) G->G->statustexts=([]);
}

//Usage: Instead of G->G->asdf->qwer(), use bouncer("asdf","qwer") and it'll late-bind.
/**
 * 
 *
 */
class bouncer(string ... keys)
{
	mixed `()(mixed ... args)
	{
		mixed func=G->G; foreach (keys,string k) func=func[k];
		return func(@args);
	}
}

//Usage: gtksignal(some_object,"some_signal",handler,arg,arg,arg) --> save that object.
//Equivalent to some_object->signal_connect("some_signal",handler,arg,arg,arg)
//When it expires, the signal is removed. obj should be a GTK2.G.Object or similar.
class gtksignal(object obj)
{
	int signal_id;
	void create(mixed ... args) {signal_id=obj->signal_connect(@args);}
	void destroy() {if (obj && signal_id) obj->signal_disconnect(signal_id);}
}

//Something like strftime(3). If passed an int, is equivalent to strftime(format,gmtime(tm)).
//Recognizes a subset of strftime(3)'s formatting codes - notably not the locale-based ones.
//Month/day names are not localized.
/**
 * 
 *
 */
string strftime(string format,int|mapping(string:int) tm)
{
	if (intp(tm)) tm=gmtime(tm);
	return replace(format,([
		"%%":"%",
		"%a":({"Sun","Mon","Tue","Wed","Thu","Fri","Sat"})[tm->wday],
		"%A":({"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"})[tm->wday],
		"%b":({"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"})[tm->mon],
		"%B":({"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"})[tm->mon],
		"%C":sprintf("%02d",tm->year/100+19),
		"%d":sprintf("%02d",tm->mday),
		"%H":sprintf("%02d",tm->hour),
		"%I":sprintf("%02d",tm->hour%12),
		"%m":sprintf("%02d",tm->mon+1),
		"%M":sprintf("%02d",tm->min),
		"%p":({"AM","PM"})[tm->hour>=12], //So tell me, why is %p in uppercase...
		"%P":({"am","pm"})[tm->hour>=12], //... and %P in lowercase?
		"%y":sprintf("%02d",tm->year%100),
		"%Y":sprintf("%04d",tm->year+1900),
	]));
}

//Exactly the same as a GTK2.TextView but with set_text() and get_text() methods like the GTK2.Entry
//Should be able to be used like an Entry.
class MultiLineEntryField
{
	inherit GTK2.TextView;
	this_program set_text(mixed ... args)
	{
		get_buffer()->set_text(@args);
		return this;
	}
	string get_text()
	{
		object buf=get_buffer();
		return buf->get_text(buf->get_start_iter(),buf->get_end_iter(),0);
	}
}

//GTK2.ComboBox designed for text strings. Has set_text() and get_text() methods.
//Should be able to be used like an Entry.
class SelectBox(array(string) strings)
{
	inherit GTK2.ComboBox;
	void create() {::create(""); foreach (strings,string str) append_text(str);}
	this_program set_text(string txt)
	{
		set_active(search(strings,txt));
		return this;
	}
	string get_text()
	{
		int idx=get_active();
		return (idx>=0 && idx<sizeof(strings)) && strings[idx];
	}
}

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

//Wants a new name... Puts this plugin into the Plugins menu.
class plugin_menu
{
	//Provide:
	constant menu_label=0; //(string) The label that goes on your menu. If not provided, will use the plugin name.
	constant menu_accel_key=0; //(int) Accelerator key. Provide if you want an accelerator.
	constant menu_accel_mods=0; //(int) Modifier keys, eg GTK2.GDK_CONTROL_MASK. Ignored if !menu_accel_key.
	void menu_clicked() { }
	//End provide.

	mapping(string:mixed) mi=([]);
	void create(string|void name)
	{
		if (!name) return;
		if (G->G->plugin_menu[name]) mi=G->G->plugin_menu[name]; else G->G->plugin_menu[name]=mi;
		if (mi->menuitem) mi->menuitem->get_child()->set_text(menu_label||name);
		else
		{
			mi->menuitem=GTK2.MenuItem(menu_label||name);
			if (menu_accel_key) mi->menuitem->add_accelerator("activate",G->G->accel,menu_accel_key,menu_accel_mods,GTK2.ACCEL_VISIBLE);
			G->G->plugin_menu[0]->add(mi->menuitem->show());
		}
		mi->signals=({gtksignal(mi->menuitem,"activate",menu_clicked)});
	}
}

//Generic window handler. If a plugin inherits this, it will normally show the window on startup and keep it there, though other patterns are available.
class window
{
	mapping(string:mixed) win=([]);

	//Replace this and call the original after assigning to win->mainwindow.
	void makewindow() { }

	//Subclasses should call ::dosignals() and then append to to win->signals. This is the
	//only place where win->signals is reset.
	void dosignals()
	{
		win->signals=({ });
	}
	void create(string|void name)
	{
		if (name) {if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;}
		if (!win->mainwindow) makewindow();
		win->mainwindow->set_skip_taskbar_hint(1)->set_skip_pager_hint(1)->show_all();
		dosignals();
	}
	void showwindow()
	{
		if (!win->mainwindow) {makewindow(); dosignals();}
		win->mainwindow->set_no_show_all(0)->show_all();
	}
	int hidewindow()
	{
		win->mainwindow->hide();
		return 1; //Allow this to be used as a delete_event (suppressing window destruction)
	}
}

//Subclass of window that handles save/load of position automatically.
//TODO: Merge code with the corresponding functionality in window.pike.
class movablewindow
{
	inherit window;
	constant pos_key="foobar/winpos"; //Set this to the persist[] key in which to store and from which to retrieve the window pos
	int x,y; //Preset x,y in create() to have a default position
	constant load_size=0; //If set to 1, will attempt to load the size as well as position. (It'll always be saved.)

	void makewindow()
	{
		if (array pos=persist[pos_key])
		{
			if (sizeof(pos)>2 && load_size) win->mainwindow->set_default_size(pos[2],pos[3]);
			win->x=1; call_out(lambda() {m_delete(win,"x");},1);
			win->mainwindow->move(pos[0],pos[1]);
		}
		::makewindow();
	}

	void configevent(object self,object ev)
	{
		#if constant(COMPAT_SIGNAL)
		if (ev->type!="configure") return;
		#endif
		if (!has_index(win,"x")) call_out(savepos,0.1);
		mapping pos=self->get_position(); win->x=pos->x; win->y=pos->y;
	}

	void savepos()
	{
		mapping sz=win->mainwindow->get_size();
		persist[pos_key]=({m_delete(win,"x"),m_delete(win,"y"),sz->width,sz->height});
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			#if constant(COMPAT_SIGNAL)
			/* NOTE: Pike 7.8.700 has a refcount bug with the "event" event.
			Newer versions of Pike don't have this bug - see commit ff1242 in
			branch 7.9 (and therefore 8.0) - but those same versions also have
			the ability to hook "before" events, which is what we need for the
			configure_event - that functionality was added in b29c8c (7.9
			branch) and a4d094 (7.8 branch, in version 7.8.733). This issue
			means that this would shortly cause Pike to either crash hard or
			get into a nasty spin. To avoid the issue, I have simply disabled
			the event hook (here and the equiv in window.pike), which means
			window positions simply won't save. As a workaround, a "Save all
			window positions" menu item has been deployed, but that's clunky.
			Hopefully some other workaround can be found! */
			//gtksignal(win->mainwindow,"event",configevent),
			#else
			gtksignal(win->mainwindow,"configure_event",configevent,0,UNDEFINED,1),
			#endif
		});
		#if constant(COMPAT_SIGNAL)
		win->save_position_hook=configevent;
		#endif
	}
}

//Base class for a configuration dialog. Permits the setup of anything where you have a list of keyworded items, can create/retrieve/update/delete them by keyword.
class configdlg
{
	inherit window;
	//Provide me...
	mapping(string:mixed) windowprops=(["title":"Configure"]);
	//Create and return a widget (most likely a layout widget) representing all the custom content.
	//If allow_rename (see below), this must assign to win->kwd a GTK2.Entry for editing the keyword;
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or it may be a GTK2.Label, or it may be omitted altogether).
	GTK2.Widget make_content() { }
	mapping(string:mapping(string:mixed)) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping.
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping. The mapping is already inside items[], so this is also a good place to trigger a persist[] save.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword. The mapping has already been removed from items[], so as above, save here.
	//... optionally provide me...
	string actionbtn; //If set, a special "action button" will be included, otherwise not. This is its caption.
	void action_callback() { } //Callback when the action button is clicked (provide if actionbtn is set)
	constant allow_new=1; //Set to 0 to remove the -- New -- entry; if omitted, -- New -- will be present and entries can be created.
	constant allow_delete=1; //Set to 0 to disable the Delete button (it'll always be present)
	constant allow_rename=1; //Set to 0 to ignore changes to keywords
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
		string newkwd=allow_rename?win->kwd->get_text():oldkwd;
		if (newkwd=="") return; //TODO: Be a tad more courteous.
		mapping info;
		if (allow_rename) info=m_delete(items,oldkwd); else info=items[oldkwd];
		if (!info)
			if (allow_new) info=([]); else return;
		if (allow_rename) items[newkwd]=info;
		save_content(info);
		if (newkwd!=oldkwd)
		{
			[object iter,object store]=win->sel->get_selected();
			if (!oldkwd) win->sel->select_iter(iter=store->append());
			store->set_value(iter,0,newkwd);
		}
	}

	void pb_delete()
	{
		if (!allow_delete) return; //Shouldn't happen - allow_delete should be a constant, so the signal won't even be connected to. But check just in case.
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		if (!kwd) return;
		store->remove(iter);
		delete_content(kwd,m_delete(items,kwd));
	}

	void selchanged()
	{
		string kwd=selecteditem();
		mapping info=items[kwd] || ([]);
		if (win->kwd) win->kwd->set_text(kwd || "");
		load_content(info);
	}

	void makewindow()
	{
		object ls=GTK2.ListStore(({"string"}));
		foreach (sort(indices(items)),string kwd) ls->set_value(ls->append(),0,kwd); //Is there no simpler way to pre-fill the liststore?
		object new; if (allow_new) ls->set_value(new=ls->append(),0,"-- New --");
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
					->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1,"sensitive":allow_delete])))
					->add(win->pb_close=GTK2.Button((["label":"_Close","use-underline":1])))
				,0,0,0)
			);
		win->sel=win->list->get_selection(); win->sel->select_iter(new||ls->get_iter_first()); selchanged();
		::makewindow();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			actionbtn && gtksignal(win->pb_action,"clicked",action_callback),
			gtksignal(win->pb_save,"clicked",pb_save),
			allow_delete && gtksignal(win->pb_delete,"clicked",pb_delete),
			gtksignal(win->pb_close,"clicked",lambda() {win->mainwindow->destroy();}), //Has to be done with a lambda, I think to dispose of the args
			gtksignal(win->sel,"changed",selchanged),
		});
	}
}

//Inherit this to get a spot on the main window's status bar.
//By default you get a simple GTK2.Label (hence the name "text"),
//but this can be altered by overriding makestatus().
class statustext
{
	mapping(string:mixed) statustxt=([]);
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) {if (G->G->statustexts[cmdname]) statustxt=G->G->statustexts[cmdname]; else G->G->statustexts[cmdname]=statustxt;}
		if (!statustxt->lbl)
			G->G->window->statusbar->pack_start(GTK2.Frame()
				->add(statustxt->lbl=makestatus())
				->set_shadow_type(GTK2.SHADOW_ETCHED_OUT)
			,0,0,3)->show_all();
	}
	GTK2.Widget makestatus() {return GTK2.Label((["xalign":0.0]));}
	void setstatus(string txt) {statustxt->lbl->set_text(txt);}
}

string gypsum_version()
{
	return String.trim_all_whites(Stdio.read_file("VERSION"));
}

/**
 * Attempt to invoke a web browser. Returns 1 if it believes it did, 0 if not.
 */
int invoke_browser(string url)
{
	foreach (({
		#ifdef __NT__
		//Windows
		({"cmd","/c","start"}),
		#elif __APPLE__
		//Darwin
		({"open"}),
		#else
		//Linux, various. Try the first one in the list; if it doesn't
		//work, go on to the next, and the next. A sloppy technique. :(
		({"xdg-open"}),
		({"exo-open"}),
		({"gnome-open"}),
		({"kde-open"}),
		#endif
	}),array(string) cmd) catch
	{
		Process.create_process(cmd+({url}));
		return 1; //If no exception is thrown, hope that it worked.
	};
}
