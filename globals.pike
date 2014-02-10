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
		"%I":sprintf("%02d",tm->hour%12 || 12),
		"%m":sprintf("%02d",tm->mon+1),
		"%M":sprintf("%02d",tm->min),
		"%S":sprintf("%02d",tm->sec),
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
	string get_text() //Like get_active_text() but will return 0 (not "") if nothing's selected (may not be necessary???)
	{
		int idx=get_active();
		return (idx>=0 && idx<sizeof(strings)) && strings[idx];
	}
}

//Advisory note that this widget should be packed without the GTK2.Expand|GTK2.Fill options
//As of 8.0.1 with CJA patch, this could safely be done with wid->set_data(), but it's not
//safe to call get_data() with a keyword that hasn't been set (it'll segfault older Pikes).
//So this works with a multiset instead.
multiset(GTK2.Widget) noexpand=(<>);
GTK2.Widget noex(GTK2.Widget wid) {noexpand[wid]=1; return wid;}

/** Create a GTK2.Table based on a 2D array of widgets
 * The contents will be laid out on the grid. Put a 0 in a cell to span
 * across multiple cells (the object preceding the 0 will span both cells).
 * Use noex(widget) to make a widget not expand (usually will want to do
 * this for a whole column). Shortcut: Labels can be included by simply
 * including a string - it will be turned into a label, expansion off, and
 * with options as set by the second parameter (if any).
 */
GTK2.Table GTK2Table(array(array(string|GTK2.Widget)) contents,mapping|void label_opts)
{
	if (!label_opts) label_opts=([]);
	GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),0);
	foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
	{
		int opt;
		if (stringp(obj)) {obj=GTK2.Label(label_opts+(["label":obj])); opt=GTK2.Fill;}
		else if (noexpand[obj]) noexpand[obj]=0; //Remove it from the set so we don't hang onto references to stuff we don't need
		else opt=GTK2.Fill|GTK2.Expand;
		int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
		tb->attach(obj,x,xend,y,y+1,opt,opt,1,1);
	}
	return tb;
}

//Like GTK2Table above, but specific to a two-column layout. Takes a 1D array and fractures it. Also sets labels to right-aligned.
GTK2.Table two_column(array(string|GTK2.Widget) contents) {return GTK2Table(contents/2,(["xalign":1.0]));}

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
	string hookname;
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",hookname);
		if (hookname) G->G->hooks[hookname]=this;
	}
	int nexthook(mapping(string:mixed) subw,string line)
	{
		if (hookname) {G->G->window->execcommand(subw,line,hookname); return 1;}
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
		mi->self=this;
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
	//TODO: Stock buttons, which come with stock events, which are automatically handled by dosignals
	//They'll use STOCK_* captions, but they're more than just that, as they do their events - eg close.
	mapping(string:mixed) win=([]);

	//Replace this and call the original after assigning to win->mainwindow.
	void makewindow() { }

	//Subclasses should call ::dosignals() and then append to to win->signals. This is the
	//only place where win->signals is reset. Note that it's perfectly legitimate to have
	//non-signals in the array; for future compatibility, ensure that everything is either
	//a gtksignal object or the integer 0, though currently nothing depends on this.
	void dosignals()
	{
		win->signals=({ });
	}
	void create(string|void name)
	{
		if (name) {if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;}
		win->self=this;
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
	int closewindow()
	{
		win->mainwindow->destroy();
		return 1;
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
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or
	//it may be a GTK2.Label, or it may be omitted altogether).
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
					win->buttonbox=(actionbtn?GTK2.Hbox(0,10)
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
			gtksignal(win->pb_close,"clicked",closewindow),
			gtksignal(win->sel,"changed",selchanged),
		});
	}
}

//Inherit this to get a spot on the main window's status bar.
//By default you get a simple GTK2.Label (hence the name "text"),
//but this can be altered by overriding makestatus(), which
//should normally set statustxt->lbl (but might wrap it in some
//other object if it wishes).
//TODO: Make it possible to go onto a second row of statusbar entries.
/* Possibility: Instead of putting them in a Vbox (see window.pike), put them into a TextView.

int main()
{
	GTK2.setup_gtk();
	object buf=GTK2.TextBuffer(),view=GTK2.TextView(buf)->set_editable(0)->set_wrap_mode(GTK2.WRAP_WORD)->set_cursor_visible(0);
	view->modify_base(GTK2.STATE_NORMAL,GTK2.GdkColor(240,240,240)); //Otherwise it has an ugly white background.
	function add=lambda(GTK2.Widget wid) {view->add_child_at_anchor(wid,buf->create_child_anchor(buf->get_end_iter())); buf->insert(buf->get_end_iter(),"  ",-1);};
	function frm=lambda(GTK2.Widget wid) {add(GTK2.Frame()->add(wid)->set_shadow_type(GTK2.SHADOW_ETCHED_OUT));};
	foreach (({"Asdf","qwer","zxcv","Testing, testing","1, 2, 3, 4"}),string x) frm(GTK2.Label(x));
	GTK2.Window(GTK2.WindowToplevel)->add(GTK2.Vbox(0,0)->add(GTK2.Button("This is the base width"))->add(view))->show_all()->signal_connect("delete-event",lambda() {exit(0);});
	return -1;
}

add() and frm() would be coded here, the labels would be done by makestatus() as per current, and the rest would go in window.pike.

TODO: Figure out how to change the base color to be "whatever the base color for a window is", rather than
hard-coding F0F0F0. Or how to make the TextView simply not draw a bg. Have emailed gtk-app-devel for ideas.

NOTE: This does not appear to work on Windows. GTK version is the same, and Pike 7.8.700 on Linux works,
but for some reason it's failing me on Windows. Weird weird weird, and very annoying.
*/

class statustext
{
	mapping(string:mixed) statustxt=([]);
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",string cmdname);
		if (cmdname) {if (G->G->statustexts[cmdname]) statustxt=G->G->statustexts[cmdname]; else G->G->statustexts[cmdname]=statustxt;}
		statustxt->self=this;
		if (!statustxt->lbl)
			G->G->window->statusbar->pack_start(GTK2.Frame()
				->add(makestatus())
				->set_shadow_type(GTK2.SHADOW_ETCHED_OUT)
			,0,0,3)->show_all();
	}
	GTK2.Widget makestatus() {return statustxt->lbl=GTK2.Label((["xalign":0.0]));}
	void setstatus(string txt) {statustxt->lbl->set_text(txt);}
}

string gypsum_version()
{
	return String.trim_all_whites(Stdio.read_file("VERSION"));
}

string pike_version()
{
	return sprintf("%d.%d.%d %s",
		__REAL_MAJOR__,__REAL_MINOR__,__REAL_BUILD__,
		#ifdef __NT__
		"Win",
		#elif defined(__OS2__)
		"OS/2",
		#elif defined(__APPLE__)
		"Mac",
		#elif defined(__amigaos__)
		"Amiga",
		#else
		"Linux",
		#endif
	);
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
		#elif defined(__APPLE__)
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

/**
 * Attempt to beep, if the user hasn't disabled it
 * Currently ignores the 'times' parameter and just beeps once.
 */
int beep(int|void times)
{
	if (!times) times=1;
	switch (persist["notif/beep"])
	{
		default: //Try everything.
			int fallthrough=1;
		case 1: //Attempt to call on an external program (which is probably setuid root on Linux)
			//On Debian-based Linuxes, this may require 'apt-get install beep' to get one
			//by Johnathan Nightingale, which seems to work well on my system.
			catch {Process.create_process(({"beep","-f800"})); return 1;};
			//If that throws, fall through in Default mode.
			if (!fallthrough) break;
		case 2: //Attempt a GTK beep
			catch {GTK2.GdkDisplay()->beep(); return 1;};
			//That might succeed without actually doing anything, so it's kept last.
			break;
		case 99: //Suppress altogether
			return 1; //Always succeeds.
	}
}
