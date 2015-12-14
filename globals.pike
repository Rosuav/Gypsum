/*
 * Globals are available globally (duh). Everything in this file, bar create(),
 * can be referenced by its name in any file other than gypsum.pike and persist.pike
 * (those two are loaded prior to this, and are special). Anything beginning with
 * an underscore, however, is deemed private. It can still be referenced externally,
 * but will not be added as a constant.
 */
void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_gypsum_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
	if (!G->G->windows) G->G->windows=([]);
	if (!G->G->statustexts) G->G->statustexts=([]);
	if (!G->G->tabstatuses) G->G->tabstatuses=([]);
	if (!G->G->dns_a) G->G->dns_a=([]); //Two separate caches, for simplicity.
	if (!G->G->dns_aaaa) G->G->dns_aaaa=([]); //0 means unknown or error; ({ }) meeans successful empty response.
}

//In any place where binary data is used, use the type name "bytes" rather than "string"
//for clarity. In all cases, "string" means "string(0..1114111)" aka Unicode; anything
//binary should be clearly marked. (Also, no surrogates, thanks! There's no way to say
//that in the typedefs, but just avoid using codepoints in the surrogate range, either
//singly or in pairs. Conversion to UTF-8 will (correctly) fail on surrogates.)
typedef string(0..255) bytes;
//Something that's ASCII-only can be trivially treated as either bytes or text (assuming
//a UTF-8 transmission stream, which most of this does, and also compatible with the
//common assumption by servers and clients that eight-bit Extended ASCII is in use).
typedef string(0..127) ascii;
//Note that in modern Pikes, these could be spelled string(8bit) and string(7bit), but
//for compatibility, they're spelled in full.

//Usage: Instead of G->G->asdf->qwer(), use bouncer("asdf","qwer") and it'll late-bind.
//Note that this is relatively slow (a run-time lookup every call), and should normally
//be avoided in favour of a reload-time replacement. But otherwise, this is a late-bind
//callable that can be passed around pretty much like a function.
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
	void create(mixed ... args) {if (obj) signal_id=obj->signal_connect(@args);}
	void destroy() {if (obj && signal_id) obj->signal_disconnect(signal_id);}
}

//Something like strftime(3). If passed an int, is equivalent to strftime(format,gmtime(tm)).
//Recognizes a subset of strftime(3)'s formatting codes - notably not the locale-based ones.
//Month/day names are not localized. Unrecognized percent codes are copied through unchanged.
//Note that %% handling is not guaranteed to work in the presence of unrecognized percent
//codes, as the parsing is extremely simplistic. (I don't have any bizarre demo cases though.)
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

//TODO: Migrate some of these GTK utility functions/classes to something importable,
//which can then be used elsewhere (eg in shed/translit.pike). And then propose them
//for backporting into core, maybe?
class MessageBox
{
	inherit GTK2.MessageDialog;
	function callback;

	void create(int flags,int type,int buttons,string message,GTK2.Window parent,function|void cb,mixed|void cb_arg)
	{
		callback=cb;
		#if constant(COMPAT_MSGDLG)
		//There's some sort of issue in older Pikes (7.8 only) regarding the parent.
		//TODO: Hunt down what it was and put a better note here.
		::create(flags,type,buttons,message);
		#else
		::create(flags,type,buttons,message,parent);
		#endif
		signal_connect("response",response,cb_arg);
		show();
	}

	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback) callback(button,cb_arg);
	}
}

class confirm
{
	inherit MessageBox;
	void create(int flags,string message,GTK2.Window parent,function cb,mixed|void cb_arg)
	{
		::create(flags,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK_CANCEL,message,parent,cb,cb_arg);
	}
	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback && button==GTK2.RESPONSE_OK) callback(cb_arg);
	}
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
	string get_text() //Like get_active_text() but will return 0 (not "") if nothing's selected (may not strictly be necessary, but it's consistent with entry fields and such)
	{
		int idx=get_active();
		return (idx>=0 && idx<sizeof(strings)) && strings[idx];
	}
	void set_strings(array(string) newstrings)
	{
		foreach (strings,string str) remove_text(0);
		foreach (strings=newstrings,string str) append_text(str);
	}
}

//Advisory note that this widget should be packed without the GTK2.Expand|GTK2.Fill options
//As of Pike 8.0.2, this could safely be done with wid->set_data(), but it's not
//safe to call get_data() with a keyword that hasn't been set (it'll segfault older Pikes).
//So this works with a multiset instead.
multiset(GTK2.Widget) _noexpand=(<>);
GTK2.Widget noex(GTK2.Widget wid) {_noexpand[wid]=1; return wid;}

/** Create a GTK2.Table based on a 2D array of widgets
 * The contents will be laid out on the grid. Put a 0 in a cell to span
 * across multiple cells (the object preceding the 0 will span both cells).
 * Use noex(widget) to make a widget not expand (usually will want to do
 * this for a whole column). Shortcut: Labels can be included by simply
 * including a string - it will be turned into a label, expansion off, and
 * with options as set by the second parameter (if any).
 * A leading 0 on a line will be quietly ignored, not resulting in any
 * spanning. Recommended for unlabelled objects in a column of labels.
 */
GTK2.Table GTK2Table(array(array(string|GTK2.Widget)) contents,mapping|void label_opts)
{
	if (!label_opts) label_opts=([]);
	GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),0);
	foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
	{
		int opt=0;
		if (stringp(obj)) {obj=GTK2.Label(label_opts+(["label":obj])); opt=GTK2.Fill;}
		else if (_noexpand[obj]) _noexpand[obj]=0; //Remove it from the set so we don't hang onto references to stuff we don't need
		else opt=GTK2.Fill|GTK2.Expand;
		int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
		tb->attach(obj,x,xend,y,y+1,opt,opt,1,1);
	}
	return tb;
}

//Like GTK2Table above, but specific to a two-column layout. Takes a 1D array and fractures it. Also sets labels to right-aligned.
//This is the most normal way to lay out labelled objects - labels on the left, objects on the right.
GTK2.Table two_column(array(string|GTK2.Widget) contents) {return GTK2Table(contents/2,(["xalign":1.0]));}

//End of generic GTK utility classes/functions

//Begin plugin inheritables

//Plugin that implements a command derived from its name
class command
{
	constant provides="slash command";
	int process(string param,mapping(string:mixed) subw) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) G->G->commands[name]=process;
	}
}

//Plugin that hooks various events, most commonly input (text entered by user) and output (text comes from server)
class hook
{
	constant provides="event hook";

	//Legacy signature - deprecated 20150422 but still supported. If you provide either of
	//these functions, don't override the corresponding modern function (input or output).
	int inputhook(string line,mapping(string:mixed) subw) {}
	int outputhook(string line,mapping(string:mixed) conn) {}

	//Override any or all of these functions to get notified on certain events.
	//The first two have default implementations to handle the legacy form, but can
	//be overridden happily. Eventually they will be replaced with empty functions
	//and the above versions dropped.
	int input(mapping(string:mixed) subw,string line) {return inputhook(line,subw);}
	int output(mapping(string:mixed) subw,string line) {return outputhook(line,subw->connection);}
	int prompt(mapping(string:mixed) subw,string prompt) { }
	int closetab(mapping(string:mixed) subw,int index) { }
	int switchtabs(mapping(string:mixed) subw) { }

	string hookname;
	void create(string name)
	{
		//Slightly different from the others in that it needs to retain its hookname
		//There's a lot of similarity in these base inheritables. Is it worth trying
		//to unify them? It'd make plugin unloading look cleaner.
		sscanf(explode_path(name)[-1],"%s.pike",hookname);
		if (hookname) G->G->hooks[hookname]=this;
	}

	//Special case for the input hook: call every hook past this one. It's the only
	//common case where this functionality is needed, although there's no particular
	//reason to preclude other hooks from doing it.
	int nexthook(mapping(string:mixed) subw,string line)
	{
		if (hookname) {G->G->window->execcommand(subw,line,hookname); return 1;}
	}
}

//Plugin that has a menu item (in the Plugins menu by default, or optionally a different menu).
//Kinda wants a better name, but it's a bit stuck now.
class plugin_menu
{
	constant provides="Plugins menu entry";
	//Provide:
	constant menu_label=0; //(string) The initial label for your menu item. (If not provided, will use the plugin name for backward compat.)
	constant menu_accel_key=0; //(int) Accelerator key. Provide if you want an accelerator.
	constant menu_accel_mods=0; //(int) Modifier keys, eg GTK2.GDK_CONTROL_MASK. Ignored if !menu_accel_key.
	constant menu_parent="plugins"; //Which menu (file/options/plugins/help) this item belongs in - don't change without good reason
	void menu_clicked() { }
	//End provide.
	//TODO: Consider having an "additional menu item" option. It seems to be the only case where any plugin wants to double-inherit.
	//Or possibly don't, because of the UI downside of having two menu items. It might be better to consciously discourage it with rough syntax.

	mapping(string:mixed) mi=([]);
	void create(string|void name)
	{
		if (!name) return;
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (G->G->plugin_menu[name]) mi=G->G->plugin_menu[name]; else G->G->plugin_menu[name]=mi;
		mi->self=this;
		if (mi->menuitem)
		{
			set_menu_text(menu_label||name);
			//NOTE: Don't deduplicate this with make_menuitem(); when window.pike gets updated,
			//make_menuitem() will be called for all plugin menu entries, and then afterward
			//they don't (necessarily) get reloaded, so create() won't get re-called.
			mi->signals=({gtksignal(mi->menuitem,"activate",menu_clicked)});
		}
		else make_menuitem(name);
	}

	void set_menu_text(string text) {mi->menuitem->get_child()->set_text_with_mnemonic(text);}

	void make_menuitem(string name)
	{
		mi->menuitem=GTK2.MenuItem(menu_label||name);
		if (menu_accel_key) mi->menuitem->add_accelerator("activate",G->G->accel,menu_accel_key,menu_accel_mods,GTK2.ACCEL_VISIBLE);
		G->G->window->menus[menu_parent]->add(mi->menuitem->show());
		mi->signals=({gtksignal(mi->menuitem,"activate",menu_clicked)});
	}
}

//Generic window handler. If a plugin inherits this, it will normally show the window on startup and
//keep it there, though other patterns are possible. For instance, the window might be hidden when
//there's nothing useful to show; although this can cause unnecessary flicker, and so should be kept
//to a minimum (don't show/hide/show/hide in rapid succession). Note that this (via a subclass)
//implements the core window, not just plugin windows, as there's no fundamental difference.
//Transient windows (eg popups etc) are best implemented with nested classes - see usage of configdlg
//('inherit configdlg') for the most common example of this.
class window
{
	constant provides="window";
	mapping(string:mixed) win=([]);
	constant is_subwindow=1; //Set to 0 to disable the taskbar/pager hinting

	//Replace this and call the original after assigning to win->mainwindow.
	void makewindow() {if (win->accelgroup) win->mainwindow->add_accel_group(win->accelgroup);}

	//Stock item creation: Close button. Calls closewindow(), same as clicking the cross does.
	GTK2.Button stock_close()
	{
		if (!win->accelgroup) win->accelgroup=GTK2.AccelGroup();
		return win->stock_close=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_CLOSE]))
			->add_accelerator("clicked",win->accelgroup,0xFF1B,0,0); //Esc as a shortcut for Close
	}

	//Subclasses should call ::dosignals() and then append to to win->signals. This is the
	//only place where win->signals is reset. Note that it's perfectly legitimate to have
	//non-signals in the array; for future compatibility, ensure that everything is either
	//a gtksignal object or the integer 0, though as of 20150103 nothing depends on this.
	void dosignals()
	{
		//NOTE: This does *not* use += here - this is where we (re)initialize the array.
		win->signals=({
			gtksignal(win->mainwindow,"delete_event",closewindow),
			win->stock_close && gtksignal(win->stock_close,"clicked",closewindow),
		});
		collect_signals("sig_", win);
	}

	void collect_signals(string prefix, mapping(string:mixed) searchme,mixed|void arg)
	{
		foreach (indices(this),string key) if (has_prefix(key,prefix) && callablep(this[key]))
		{
			//Function names of format sig_x_y become a signal handler for win->x signal y.
			//(Note that classes are callable, so they can be used as signal handlers too.)
			//This may pose problems, as it's possible for x and y to have underscores in
			//them, so we scan along and find the shortest such name that exists in win[].
			//If there's none, ignore it. This can create ambiguities, but only in really
			//contrived situations, so I'm deciding not to care. :)
			array parts=(key/"_")[1..];
			int b4=(parts[0]=="b4"); if (b4) parts=parts[1..]; //sig_b4_some_object_some_signal will connect _before_ the normal action
			for (int i=0;i<sizeof(parts)-1;++i) if (mixed obj=searchme[parts[..i]*"_"])
			{
				if (objectp(obj) && callablep(obj->signal_connect))
				{
					win->signals+=({gtksignal(obj,parts[i+1..]*"_",this[key],arg,UNDEFINED,b4)});
					break;
				}
			}
		}
	}
	void create(string|void name)
	{
		if (name) sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) {if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;}
		win->self=this;
		if (!win->mainwindow) makewindow();
		if (is_subwindow) win->mainwindow->set_transient_for(win->_parentwindow || G->G->window->mainwindow);
		win->mainwindow->set_skip_taskbar_hint(is_subwindow)->set_skip_pager_hint(is_subwindow)->show_all();
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
		return 1; //Simplify anti-destruction as "return hidewindow()". Note that this can make updating tricky - be aware of this.
	}
	int closewindow()
	{
		win->mainwindow->destroy();
		return 1;
	}
}

//Subclass of window that handles save/load of position automatically.
class movablewindow
{
	inherit window;
	constant pos_key=0; //(string) Set this to the persist[] key in which to store and from which to retrieve the window pos
	constant load_size=0; //If set to 1, will attempt to load the size as well as position. (It'll always be saved.)
	constant provides=0;

	void makewindow()
	{
		if (array pos=persist[pos_key])
		{
			if (sizeof(pos)>3 && load_size) win->mainwindow->set_default_size(pos[2],pos[3]);
			win->x=1; call_out(lambda() {m_delete(win,"x");},1);
			win->mainwindow->move(pos[0],pos[1]);
		}
		::makewindow();
	}

	void sig_b4_mainwindow_configure_event()
	{
		if (!has_index(win,"x")) call_out(savepos,0.1);
		mapping pos=win->mainwindow->get_position(); win->x=pos->x; win->y=pos->y;
	}

	void savepos()
	{
		if (!pos_key) {werror("%% Assertion failed: Cannot save position without pos_key set!"); return;} //Shouldn't happen.
		mapping sz=win->mainwindow->get_size();
		persist[pos_key]=({m_delete(win,"x"),m_delete(win,"y"),sz->width,sz->height});
	}

	void dosignals()
	{
		::dosignals();
	}
}

//Base class for a configuration dialog. Permits the setup of anything where you
//have a list of keyworded items, can create/retrieve/update/delete them by keyword.
/* Idea: Allow the displayed name to differ from the items[] key. This could be
done with a translation mapping, for instance; and a standard rule of "0 means
-- New --" could allow us to distinguish the 'real' New from one that happens
to have that keyword value. I can think of two ways to do this within GTK: one,
subclass ListStore to return different values; two, subclass CellRendererText
to display certain strings differently. Obviously the latter is better! But I
can't get either to work, at the moment. The key functions don't seem to come
back to Pike code. It might require writing C level code, which would mean I
can't depend on this technique (as it won't work on all platforms and old Pike
versions). Still, if this could be done, it would be handy. Maybe it can be
pulled off by having a two-column ListStore, where the first is the keyword
and the second is the display text?? Might have synchronization problems,
though. Would need to dig into it and see how well it actually works. */
//Note that the strongest call for the above idea (the numpad nav dlg) is now
//coping in a different way, albeit unideally, so this isn't urgent.
//It may be worth breaking out some of this code into a dedicated ListBox class
//for future reuse. Currently I don't actually need that for Gypsum, but it'd
//make a nice utility class for other programs.
class configdlg
{
	inherit window;
	//Provide me...
	mapping(string:mixed) windowprops=(["title":"Configure"]);
	mapping(string:mapping(string:mixed)) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping, or something out of persist[] (and see persist_key)
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword.
	string actionbtn; //(DEPRECATED) If set, a special "action button" will be included, otherwise not. This is its caption.
	void action_callback() { } //(DEPRECATED) Callback when the action button is clicked (provide if actionbtn is set)
	constant allow_new=1; //Set to 0 to remove the -- New -- entry; if omitted, -- New -- will be present and entries can be created.
	constant allow_delete=1; //Set to 0 to disable the Delete button (it'll always be visible though)
	constant allow_rename=1; //Set to 0 to ignore changes to keywords
	constant strings=({ }); //Simple string bindings - see plugins/README
	constant ints=({ }); //Simple integer bindings, ditto
	constant bools=({ }); //Simple boolean bindings (to CheckButtons), ditto
	constant labels=({ }); //Labels for the above
	constant persist_key=0; //(string) Set this to the persist[] key to load items[] from; if set, persist will be saved after edits.
	constant descr_key=0; //(string) Set this to a key inside the info mapping to populate with descriptions. ADVISORY. Details may change, though the feature is almost certainly going to stick around.
	//... end provide me.

	void create() {::create();} //Pass on no args to the window constructor - all configdlgs are independent

	//Return the keyword of the selected item, or 0 if none (or new) is selected
	string selecteditem()
	{
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		return (kwd!="-- New --") && kwd; //TODO: Recognize the "New" entry by something other than its text
	}

	void sig_pb_save_clicked()
	{
		string oldkwd=selecteditem();
		string newkwd=allow_rename?win->kwd->get_text():oldkwd;
		if (newkwd=="") return; //Blank keywords currently disallowed
		if (newkwd=="-- New --") return; //Since selecteditem() currently depends on "-- New --" being the 'New' entry, don't let it be used anywhere else.
		mapping info;
		if (allow_rename) info=m_delete(items,oldkwd); else info=items[oldkwd];
		if (!info)
			if (allow_new) info=([]); else return;
		if (allow_rename) items[newkwd]=info;
		foreach (strings,string key) info[key]=win[key]->get_text();
		foreach (ints,string key) info[key]=(int)win[key]->get_text();
		foreach (bools,string key) info[key]=(int)win[key]->get_active();
		save_content(info);
		if (persist_key) persist->save();
		[object iter,object store]=win->sel->get_selected();
		if (newkwd!=oldkwd)
		{
			if (!oldkwd) win->sel->select_iter(iter=store->insert_before(win->new_iter));
			store->set_value(iter,0,newkwd);
		}
		if (descr_key && info[descr_key]) store->set_value(iter,1,info[descr_key]);
	}

	void sig_pb_delete_clicked()
	{
		if (!allow_delete) return; //The button will be insensitive anyway, but check just to be sure.
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		if (!kwd) return;
		store->remove(iter);
		foreach (strings+ints,string key) win[key]->set_text("");
		foreach (bools,string key) win[key]->set_active(0);
		delete_content(kwd,m_delete(items,kwd));
		if (persist_key) persist->save();
	}

	void sig_sel_changed()
	{
		string kwd=selecteditem();
		mapping info=items[kwd] || ([]);
		if (win->kwd) win->kwd->set_text(kwd || "");
		foreach (strings,string key) win[key]->set_text((string)(info[key] || ""));
		foreach (ints,string key) win[key]->set_text((string)info[key]);
		foreach (bools,string key) win[key]->set_active((int)info[key]);
		load_content(info);
	}

	void makewindow()
	{
		object ls=GTK2.ListStore(({"string","string"}));
		if (persist_key && !items) items=persist->setdefault(persist_key,([]));
		//TODO: Break out the list box code into a separate object - it'd be useful eg for zoneinfo.pike.
		foreach (sort(indices(items)),string kwd)
		{
			object iter=ls->append();
			ls->set_value(iter,0,kwd);
			if (string descr=descr_key && items[kwd][descr_key]) ls->set_value(iter,1,descr);
		}
		if (allow_new) ls->set_value(win->new_iter=ls->append(),0,"-- New --");
		win->mainwindow=GTK2.Window(windowprops)
			->add(GTK2.Vbox(0,10)
				->add(GTK2.Hbox(0,5)
					->add(win->list=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
						->append_column(GTK2.TreeViewColumn("Item",GTK2.CellRendererText(),"text",0))
						->append_column(GTK2.TreeViewColumn("",GTK2.CellRendererText(),"text",1))
					)
					->add(GTK2.Vbox(0,0)
						->add(make_content())
						->pack_end(
							(actionbtn?GTK2.HbuttonBox()
							->add(win->pb_action=GTK2.Button((["label":actionbtn,"use-underline":1])))
							:GTK2.HbuttonBox())
							->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
							->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1,"sensitive":allow_delete])))
						,0,0,0)
					)
				)
				->add(win->buttonbox=GTK2.HbuttonBox()->pack_end(stock_close(),0,0,0))
			);
		win->sel=win->list->get_selection(); win->sel->select_iter(win->new_iter||ls->get_iter_first()); sig_sel_changed();
		::makewindow();
	}

	//Iterates over labels, applying them to controls in this order:
	//1) win->kwd, if allow_rename is not zeroed
	//2) strings, creating Entry()
	//3) ints, ditto
	//4) bools, creating CheckButton()
	//5) strings, if marked to create MultiLineEntryField()
	//6) Descriptive text underneath
	//Not yet supported: Anything custom, eg insertion or reordering;
	//any other widget types eg SelectBox.
	//Hmm. Instead of this, would it be better to pass in an array alternating
	//labels and field names, and adorning the field names to say whether they
	//should be added to "'strings", "#ints", or "?bools", and build those from
	//this? Then multi-line ones could be identified as "''fieldname", order
	//could be completely custom, and something could be done for other types
	//too. Worth doing or not?
	array(string|GTK2.Widget) collect_widgets()
	{
		array stuff = ({ });
		array atend = ({ });
		Iterator lbl = get_iterator(labels);
		if (!lbl) return stuff;
		if (allow_rename)
		{
			stuff += ({lbl->value(), win->kwd=noex(GTK2.Entry())});
			if (!lbl->next()) return stuff;
		}
		foreach (strings+ints, string name)
		{
			string desc=lbl->value();
			if (desc[0]=='\n') //Hack: Multiline fields get shoved to the end.
				atend += ({GTK2.Frame(desc)->add(
					win[name]=MultiLineEntryField((["buffer":GTK2.TextBuffer(),"wrap-mode":GTK2.WRAP_WORD_CHAR]))->set_size_request(225,70)
				),0});
			else
				stuff += ({desc, win[name]=noex(GTK2.Entry())});
			if (!lbl->next()) return stuff+atend;
		}
		foreach (bools, string name)
		{
			stuff += ({0,win[name]=noex(GTK2.CheckButton(lbl->value()))});
			if (!lbl->next()) return stuff+atend;
		}
		stuff += atend; //Now grab any multiline string fields
		//Finally, consume the remaining entries making text. There'll most
		//likely be zero or one of them.
		foreach (lbl;;string text)
			if (text[0]=='\n') stuff += ({noex(GTK2.Label(text)->set_line_wrap(1)), 0});
			else stuff += ({text, 0});
		return stuff;
	}

	//Create and return a widget (most likely a layout widget) representing all the custom content.
	//If allow_rename (see below), this must assign to win->kwd a GTK2.Entry for editing the keyword;
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or
	//it may be a GTK2.Label, or it may be omitted altogether).
	//By default, makes a two_column based on collect_widgets. It's easy to override this to add some
	//additional widgets before or after the ones collect_widgets creates.
	GTK2.Widget make_content()
	{
		return two_column(collect_widgets());
	}

	//Attempt to select the given keyword - returns 1 if found, 0 if not
	int select_keyword(string kwd)
	{
		object ls=win->list->get_model();
		object iter=ls->get_iter_first();
		do
		{
			if (ls->get_value(iter,0)==kwd)
			{
				win->sel->select_iter(iter); sig_sel_changed();
				return 1;
			}
		} while (ls->iter_next(iter));
		return 0;
	}

	void dosignals()
	{
		::dosignals();
		if (actionbtn) win->signals+=({gtksignal(win->pb_action,"clicked",action_callback)});
	}
}

//Inherit this to get a spot on the main window's status bar.
//By default you get a simple GTK2.Label (hence the name "text"),
//but this can be altered by overriding makestatus(), which
//must set statustxt->lbl and return either it or a parent of it.
//For example, wrapping a label in an EventBox can be useful - see statusevent below.
//(Previously I had some notes here about wrapping to multiple lines. This
//is no longer an issue, but see aa6a01 if you want to know what was said.)
class statustext
{
	constant provides="status bar entry";
	mapping(string:mixed) statustxt=([]);
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) {if (G->G->statustexts[name]) statustxt=G->G->statustexts[name]; else G->G->statustexts[name]=statustxt;}
		statustxt->self=this;
		if (!statustxt->lbl)
		{
			GTK2.Widget frm=GTK2.Frame()
				->add(makestatus())
				->set_shadow_type(GTK2.SHADOW_ETCHED_OUT);
			G->G->window->win->statusbar->pack_start(frm,0,0,3)->show_all();
			if (!G->G->tooltips) G->G->tooltips=GTK2.Tooltips();
			G->G->tooltips->set_tip(frm,statustxt->tooltip || name);
		}
	}
	GTK2.Widget makestatus() {return statustxt->lbl=GTK2.Label((["xalign":0.0]));}
	void setstatus(string txt) {statustxt->lbl->set_text(txt);}
}

//Like statustext, but has an eventbox and responds to a double-click.
//As well as being useful in itself, this can be a template for other non-text
//statusbar usage - see makestatus() and imitate.
class statusevent
{
	inherit statustext;
	constant provides=0;
	void create(string name)
	{
		::create(name);
		statustxt->signals=({gtksignal(statustxt->evbox,"button_press_event",mousedown)});
	}

	GTK2.Widget makestatus()
	{
		return statustxt->evbox=GTK2.EventBox()->add(::makestatus());
	}

	void mousedown(object self,object ev)
	{
		if (ev->type=="2button_press") statusbar_double_click();
	}

	void statusbar_double_click() {/* Override me */}
}

//Like statustext, but keeps track of it greatest width and never shrinks from it
//The width is measured and set on statustxt->lbl.
//Currently considered ADVISORY for plugins as the name may change.
class statustext_maxwidth
{
	inherit statustext;
	void setstatus(string txt)
	{
		statustxt->lbl->set_text(txt);
		statustxt->lbl->set_size_request(statustxt->width=max(statustxt->width,GTK2.Label(txt)->size_request()->width),-1);
	}
}

//ADVISORY and currently undocumented: Per-tab status.
//The maketabstatus() function will be called for every subwindow
//and every time a subwindow is created. Currently, info for the
//per-subwindow stats is stored in subw[], using the plugin name as
//part of the key. This means there's actually no unified infomap as
//there is for most other inheritables. There is, however, a global
//registry of tab-status objects, keyed by the name.
//BEST PRACTICE: Use subw->world as the key for any status info, eg
//persist["your_plugin_name/"+subw->world] - this will allow for
//per-world configuration in a way the user will expect.
class tabstatus(string name)
{
	constant provides="per-tab status";
	//Set a tooltip globally or per-subw.
	string tooltip="";
	void create()
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return; //Must have a name.
		G->G->tabstatuses[name]=this;
		foreach (G->G->window->win->tabs,mapping subw)
			if (!subw["tabstatus/"+name]) install(subw);
	}
	GTK2.Widget maketabstatus(mapping(string:mixed) subw) {return GTK2.Label("Per-tab status");}
	void install(mapping(string:mixed) subw)
	{
		GTK2.Widget frm=GTK2.Frame()
			->add(maketabstatus(subw))
			->set_shadow_type(GTK2.SHADOW_ETCHED_OUT);
		if (!G->G->tooltips) G->G->tooltips=GTK2.Tooltips();
		update_tooltip(subw);
		subw->tabstatus->pack_start(subw["tabstatus/"+name]=frm->show_all(),0,0,0);
	}

	//Internal: Update the tooltip based on the previously-set strings
	//TODO: Doesn't seem to be working :(
	void update_tooltip(mapping(string:mixed) subw) {G->G->tooltips->set_tip(subw["tabstatus/"+name],subw["tabstatus/"+name+"/tooltip"] || tooltip);}

	//If !subw, sets the global default tip. If !newtip, resets to default.
	void set_tooltip(mapping(string:mixed) subw,string newtip)
	{
		if (subw)
		{
			subw["tabstatus/"+name+"/tooltip"]=newtip;
			update_tooltip(subw);
		}
		else
		{
			tooltip=newtip || "(no tooltip set by plugin "+name+")";
			foreach (G->G->window->win->tabs,mapping subw) update_tooltip(subw);
		}
	}

	//ADVISORY: Override this to be notified when a world is (dis)connected
	//On disconnect, world==0; on connect, it is a string identifier which
	//is about to be stored in subw->world. During this callback, the last
	//world that was connected (if any) can be seen in subw->world. (Note
	//that subw->world is not currently cleared on disconnection. But you
	//won't normally get a new connection while you're already connected,
	//so any nonzero world should be assumed to be "wasn't connected, now
	//will be".) Note: This is called when the world selection is made, NOT
	//when a connection is actually established. This may change in future.
	//This MAY end up being moved to the 'hook' inheritable. (???) If it
	//does, it might need to also distinguish "connecting" from "connected".
	//Possibly a "connection phase" that goes from "DNS" to "connecting"
	//to "connected" to "disconnected", and depends on subw->world?? It's
	//not as if the previous world will be all that useful anyway.
	void connected(mapping(string:mixed) subw,string world) { }
}

//End plugin inheritables

ascii gypsum_version()
{
	return String.trim_all_whites(Stdio.read_file("VERSION")); //Assumed (but not checked) to be all-ASCII. Don't break this, kthx.
}

ascii pike_version()
{
	return sprintf("%d.%d.%d %s",
		__REAL_MAJOR__,__REAL_MINOR__,__REAL_BUILD__,
		#ifdef __NT__
		"Win",
		#elif defined(__APPLE__)
		"Mac",
		//Other platforms may also be able to run Gypsum, but I don't support them.
		#else
		"Linux",
		#endif
	);
}

//Attempt to invoke a web browser. Returns 1 if it believes it did, 0 if not.
//Currently always calls on an external command, and has no way of knowing
//whether it truly succeeded or not; in any case, it's asynchronous.
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

/*
 * Return just the text out of one line from subw->lines
 *
 * Will cache its response. This may cause problems, if the line can get
 * changed. Anything that mutates a line MUST m_delete(line[0],"text");
 * to wipe that cache.
 */
string line_text(array line)
{
	if (string t=line[0]->text) return t;
	return line[0]->text=filter(line,stringp)*"";
}

//Redirect a stream to a specified file; undoes the redirect on destruction automatically.
//Passing a file name as the target will truncate it. Explicitly open the file if you wish to append.
class redirect(Stdio.File file,string|Stdio.File|void target)
{
	Stdio.File dup;
	void create()
	{
		#if __VERSION__ < 8.0
		//Pike 7.8's Stdio.File::dup() doesn't seem to work properly,
		//so we reach into the object's internals.
		dup=Stdio.File();
		dup->assign(file->_fd->dup());
		#else
		dup=file->dup();
		#endif
		if (!target)
		{
			//Is there a cross-platform way to find the null device? Python has os.devnull for that.
			#ifdef __NT__
			target="nul";
			#else
			target="/dev/null";
			#endif
		}
		if (stringp(target)) target=Stdio.File(target,"wct");
		target->dup2(file);
		target->close();
	}
	void destroy()
	{
		//Undo the redirection by assigning the old copy back in.
		dup->dup2(file);
	}
}

//Format an integer seconds according to a base value. The base ensures that
//the display is stable as the time ticks down.
string format_time(int delay,int|void base,int|void resolution)
{
	/*
	Open question: Is it better to show 60 seconds as "60" or as "01:00"?

	Previously, this would show it as 60 (unless it's ticking down from a longer time, of course),
	but this makes HP/SP/EP display - which can't know what they're ticking down from - to look
	a bit odd. Changing it 20140117 to show as 01:00. Question is still open as to how it ought
	best to be done. There are arguments on both sides.
	*/
	if (resolution) delay-=delay%resolution;
	if (delay<=0) return "";
	switch (max(delay,base))
	{
		case 0..59: return sprintf("%02d",delay);
		case 60..3599: return sprintf("%02d:%02d",delay/60,delay%60);
		default: return sprintf("%02d:%02d:%02d",delay/3600,(delay/60)%60,delay%60);
	}
}

//Return the file from which some function or object was created
//Will take the deepest subclass available.
string origin(function|object func)
{
	//Always go via the program, in case the function actually comes from an inherited parent.
	program pgm=functionp(func)?function_program(func):object_program(func);
	string def=Program.defined(pgm);
	return def && (def/":")[0]; //Assume we don't have absolute Windows paths here, which this would break
}

//Figure out an actual file name based on the input
//Returns the input unchanged if nothing is found, but tries hard to find something.
//Throws exception on error, although this will often be more usefully just displayed.
string fn(string param)
{
	if (has_prefix(param,"/") && !has_suffix(param,".pike"))
	{
		//Allow "update /blah" to update the file where /blah is coded
		//Normally this will be "plugins/blah.pike", which just means you can omit the path and extension, but it helps with aliasing.
		function f=G->G->commands[param[1..]];
		if (!f) error("Command not found: "+param[1..]+"\n");
		string def=origin(f);
		if (!def) error("%% Function origin not found: "+param[1..]+"\n");
		param=def;
	}

	//Turn "cmd/update.pike:4" into "cmd/update.pike". This breaks on Windows path names, which
	//may be a problem; to prevent issues, always use relative paths. Auto-discovered plugins
	//use a relative path, but manually loaded ones could be problematic. (This is
	//an issue for loading plugins off a different drive, obviously. It is unsolvable for now.)
	if (has_value(param,":")) sscanf(param,"%s:",param);

	//Attempt to turn a base-name-only and/or a pathless name into a real name
	if (!has_value(param,".") && !file_stat(param) && file_stat(param+".pike")) param+=".pike";
	if (!has_value(param,"/") && !file_stat(param))
	{
		foreach (({"plugins","plugins/zz_local"}),string dir)
		{
			if (file_stat(dir+"/"+param)) {param=dir+"/"+param; break;}
			if (file_stat(dir+"/"+param+".pike")) {param=dir+"/"+param+".pike"; break;}
		}
	}
	return param;
}

//Convenience function: convert a number to hex. Saves typing; intended for use in a /x or equivalent.
string hex(int x,int|void digits) {return sprintf("%0*x",digits,x);}

//Or perhaps more convenient: a hexadecimal integer, with its repr being 0xNNNN.
//Basic operations on it should continue to return hex integers.
//Note that this method may not work on older Pikes, and therefore may need to be guarded with a
//COMPAT option. Checkout 0209a4 for an alternative implementation (with its own flaws).
//Note that explicit casts don't work on some Pikes unless spelled (int)mpz::this, so that's how it's written.
class Hex
{
	inherit Gmp.mpz;
	string _sprintf(int type,mapping|void params) {return sprintf(type=='O'?"0x%*x":(string)({'%','*',type}),params||([]),(int)mpz::this);}
}

//Similarly, show a time value.
class Time
{
	inherit Gmp.mpz;
	//Note that there's something odd about calling format_time(val) here, so I've simplified and inlined it.
	string _sprintf(int type,mapping|void params) {int val=(int)mpz::this; return type=='O' ? sprintf("%02d:%02d:%02d",val/3600,(val/60)%60,val%60) : ::_sprintf(type,params);}
}

//Probe a plugin and return a program usable for retrieving constants, but not
//for instantiation. This should be used any time the program won't be cloned,
//as it avoids creating log entries under that file name, and also permits the
//plugin to avoid loading itself completely. If there's any sort of exception,
//UNDEFINED will be returned; compilation errors are silenced.
//Note that compile_error() and compile_warning() are technically internal, but
//they're called by the compiler. I could create a dedicated class, but it's
//cheaper to use 'this' and have these functions defined here. They are thus
//available as constants, useless though that be.
void compile_error(string fn,int l,string msg) { }
void compile_warning(string fn,int l,string msg) { }
program probe_plugin(string filename)
{
	add_constant("COMPILE_ONLY",1);
	program ret=UNDEFINED;
	catch {ret=compile_string(Stdio.read_file(fn(filename)),".probe",this);};
	add_constant("COMPILE_ONLY");
	return ret;
}

//Look up some sort of name and return one or more IP addresses
//Note that an IP literal will result in the callback being called
//before DNS() returns, and then never afterward. Be prepared for this.
class DNS(string hostname,function callback)
{
	//NOTE: This would be more idiomatically spelled as "mixed ... cbargs" above, rather
	//than collecting them up in create(); but in current Pikes (as of 20150827) this is
	//not working. Until it's fixed _and_ the patch makes its way into all the Pikes I
	//support, it's safer to just use the non-idiomatic explicit form.
	array cbargs;
	//Note that async_dual_client would probably be better, but only marginally, so since it isn't available on all Pikes, I'll stick with UDP-only.
	object cli=Protocols.DNS.async_client();

	array(string) ips=({ }); //May be mutated; will only ever be appended to.
	int pending; //If this is nonzero, the callback will be called again - possibly with more IPs (but possibly not)

	void dnsresponse(string domain,mapping resp)
	{
		//For simplicity, don't bother caching negative responses. If we
		//get asked again for something that failed, it's quite possibly
		//because network settings have changed and there's a chance it
		//will now succeed.
		//TODO: Record the TTL somewhere, or add a call_out to remove it
		//TODO: If we have a positive response for one protocol, should we
		//use that rather than repeating the DNS lookups for the other?
		//eg if we look up minstrelhall.com and get 203.214.67.43 and no
		//AAAA records, should we use the 3600 TTL from the A record as
		//an indication that we shouldn't bother asking for AAAA records
		//for the next hour?
		//Note that technically there can be multiple different TTLs on
		//different records of the same type. In practice this will be a
		//rarity, so we can just take the lowest TTL from all answers and
		//apply that to all of them. All it means is that we miss out on
		//some possible caching... but frankly, I don't know what else
		//we could do, and it's not a normal thing to come across!
		//Note that we depend on upstream DNS not sending us superfluous responses. But
		//we'd depend on them to not send us outright forged responses anyway, so that's
		//not a big deal. If a server sends back a CNAME and a corresponding A/AAAA, we'll
		//get the right address. TODO: Properly handle CNAMEs, including firing off other
		//requests.
		//TODO: Is this getting incorrect results if additional records are sent? CHECK ME!
		array ans = (resp->an->a + resp->an->aaaa) - ({0});
		if (resp->qd[0]->type==Protocols.DNS.T_AAAA) G->G->dns_aaaa[domain]=ans;
		else G->G->dns_a[domain]=ans;
		ips += ans;
		callback(this,@cbargs);
	}

	void create(mixed ... args)
	{
		cbargs=args; //See above, can't be done the clean way.
		//TODO: What should be done if connection/protocol changes and we
		//have cached info? Should the cache retain A and AAAA records
		//separately, and proceed with the two parts independently?
		string prot=persist["connection/protocol"];
		//IP address literals get "resolved" instantly. And if the user requested direct connection attempts, same.
		//Note that direct connection attempts will normally result in synchronous DNS lookups. This will lag out the main
		//thread, and thus cause distinctly unpleasant problems on timeouts. But if you want it, go for it.
		if (prot=="*" || sscanf(hostname,"%d.%d.%d.%d",int q,int w,int e,int r)==4 || Protocols.IPv6.parse_addr(hostname))
		{
			ips=({hostname});
			call_out(callback,0,this,@cbargs); //The callback is always queued on the backend rather than being called synchronously.
			return;
		}
		if (prot!="6") {++pending; cli->do_query(hostname,Protocols.DNS.C_IN,Protocols.DNS.T_A,   dnsresponse);}
		if (prot!="4") {++pending; cli->do_query(hostname,Protocols.DNS.C_IN,Protocols.DNS.T_AAAA,dnsresponse);}
		//TODO: Should there be a timeout on these lookups? (Or is there one, and it's just way way long?)
	}
}

//Establish a socket connection to a specified host/port
//The callback will be called with either a socket object or 0.
//Connections will be attempted to all available IP addresses
//for the specified host, in sequence.
//The callback receives three possible first arguments: an open
//socket (indicating success), a string (indicating progress),
//or 0 (indicating failure). The strings are human-readable.
//Note that the zero indicates complete failure, rather than a
//single failed connection; if no A/AAAA records are returned,
//or if multiple are and they've all been tried, the result is
//the same as the "classic" case of one IP address and a failed
//connection.

//It's not currently possible to get information about _how_ a
//connection failed (refused, timed out, etc) as the socket's
//errno is not being retained properly. This may change in the
//future, but will depend on a Pike change. If that happens, a
//connection failure will be signalled by another callback call,
//possibly with an integer argument (errno). On a failed conn
//with no errno available, hack it to something nonzero - maybe
//a negative number, or maybe EOWNERDEAD (130). :)
class establish_connection(string hostname,int port,function callback)
{
	object sock;
	object dns;
	array cbargs;

	void cancel() {callback=0;} //Prevent further calls to the callback (eg if the user requests cancellation)
	void connected()
	{
		if (!sock->is_open() || !sock->query_address()) {sock=0; tryconn();}
		callback(sock, @cbargs);
		cancel();
	}

	void tryconn()
	{
		if (sock || !callback) return;
		if (!sizeof(dns->ips) && !dns->pending) {callback(0,@cbargs); return;} //We've run out of addresses to try. Connection failed.
		[string ip,dns->ips]=Array.shift(dns->ips);
		callback("Connecting to "+ip+"...", @cbargs); if (!callback) return;
		sock=Stdio.File(); sock->open_socket();
		sock->set_nonblocking(0,connected,tryconn);
		if (mixed ex=catch {sock->connect(ip,port);})
		{
			callback("Exception in connection: "+describe_error(ex), @cbargs);
			sock=0; tryconn(); //I doubt this will happen repeatedly (and definitely not infinitely), so just recurse. (TBH Pike probably recognizes this as a tail call anyway.)
		}
	}

	void create(mixed ... args) {cbargs=args; dns=DNS(hostname,tryconn);} //As above. Note that initializing dns at its declaration would do it before hostname is set.
}
