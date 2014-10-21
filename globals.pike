/**
 * Load up the globals and apply those which need changing
 */
void create(string n)
{
	foreach (indices(this),string f) if (f!="create") add_gypsum_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
	if (!G->G->windows) G->G->windows=([]);
	if (!G->G->statustexts) G->G->statustexts=([]);
	#if constant(COMPAT_SIGNAL)
	if (!G->G->enterpress) G->G->enterpress=([]);
	#endif
}

//In any place where binary data is used, use the type name "bytes" rather than "string"
//for clarity. In all cases, "string" means "string(0..1114111)" aka Unicode; anything
//binary should be clearly marked.
typedef string(0..255) bytes;
//Something that's ASCII-only can be trivially treated as either bytes or text (assuming
//a UTF-8 transmission stream).
typedef string(0..127) ascii;

//Usage: Instead of G->G->asdf->qwer(), use bouncer("asdf","qwer") and it'll late-bind.
//Note that this is relatively slow (a run-time lookup every time), and should normally
//be avoided in favour of a reload-time replacement.
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
//Month/day names are not localized. Unrecognized percent codes are copied through unchanged.
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

class MessageBox
{
	inherit GTK2.MessageDialog;
	function callback;

	void create(int flags,int type,int buttons,string message,GTK2.Window parent,function|void cb,mixed|void cb_arg)
	{
		if (!parent) parent=G->G->window->mainwindow;
		callback=cb;
		#if constant(COMPAT_MSGDLG)
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
	string get_text() //Like get_active_text() but will return 0 (not "") if nothing's selected (may not be necessary???)
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
	constant provides="slash command";
	int process(string param,mapping(string:mixed) subw) {}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) G->G->commands[name]=process;
	}
}

//Plugin that hooks input and/or output
class hook
{
	constant provides="input/output hook";
	int inputhook(string line,mapping(string:mixed) subw) {}
	int outputhook(string line,mapping(string:mixed) conn) {}
	string hookname;
	void create(string name)
	{
		//Slightly different from the others in that it needs to retain its hookname
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
	constant provides="Plugins menu entry";
	//Provide:
	constant menu_label=0; //(string) The initial label for your menu item. If not provided, will use the plugin name.
	constant menu_accel_key=0; //(int) Accelerator key. Provide if you want an accelerator.
	constant menu_accel_mods=0; //(int) Modifier keys, eg GTK2.GDK_CONTROL_MASK. Ignored if !menu_accel_key.
	void menu_clicked() { }
	//End provide.

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
			mi->signals=({gtksignal(mi->menuitem,"activate",menu_clicked)});
		}
		else make_menuitem(name);
	}

	void set_menu_text(string text) {mi->menuitem->get_child()->set_text_with_mnemonic(text);}

	void make_menuitem(string name)
	{
		mi->menuitem=GTK2.MenuItem(menu_label||name);
		if (menu_accel_key) mi->menuitem->add_accelerator("activate",G->G->accel,menu_accel_key,menu_accel_mods,GTK2.ACCEL_VISIBLE);
		G->G->plugin_menu[0]->add(mi->menuitem->show());
		mi->signals=({gtksignal(mi->menuitem,"activate",menu_clicked)});
	}
}

//Generic window handler. If a plugin inherits this, it will normally show the window on startup and keep it there, though other patterns are available.
class window
{
	constant provides="window";
	mapping(string:mixed) win=([]);
	constant is_subwindow=1; //Set to 0 to disable the taskbar/pager hinting

	//Replace this and call the original after assigning to win->mainwindow.
	void makewindow() { }

	//Stock item creation: Close button. Calls closewindow(), same as clicking the cross does.
	GTK2.Button stock_close() {return win->stock_close=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_CLOSE]));}

	//Subclasses should call ::dosignals() and then append to to win->signals. This is the
	//only place where win->signals is reset. Note that it's perfectly legitimate to have
	//non-signals in the array; for future compatibility, ensure that everything is either
	//a gtksignal object or the integer 0, though currently nothing depends on this.
	void dosignals()
	{
		win->signals=({
			gtksignal(win->mainwindow,"delete_event",closewindow),
			win->stock_close && gtksignal(win->stock_close,"clicked",closewindow),
		});
		foreach (indices(this),string key) if (has_prefix(key,"sig_") && callablep(this[key]))
		{
			//Function names of format sig_x_y become a signal handler for win->x signal y.
			//(Note that classes are callable, so they can be used as signal handlers too.)
			//This may pose problems, as it's possible for x and y to have underscores in
			//them, so we scan along and find the shortest such name that exists in win[].
			//If there's none, ignore it. This can create ambiguities, but only in really
			//contrived situations, so I'm deciding not to care. :)
			array parts=(key/"_")[1..];
			for (int i=0;i<sizeof(parts)-1;++i) if (mixed obj=win[parts[..i]*"_"])
			{
				if (objectp(obj) && callablep(obj->signal_connect))
				{
					win->signals+=({gtksignal(obj,parts[i+1..]*"_",this[key])});
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
		if (is_subwindow) win->mainwindow->set_transient_for(G->G->window->mainwindow);
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
		return 1; //Allow this to be used as a delete_event (suppressing window destruction)
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

	void windowmoved()
	{
		if (!has_index(win,"x")) call_out(savepos,0.1);
		mapping pos=win->mainwindow->get_position(); win->x=pos->x; win->y=pos->y;
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
			#if !constant(COMPAT_SIGNAL)
			gtksignal(win->mainwindow,"configure_event",windowmoved,0,UNDEFINED,1),
			#endif
		});
		#if constant(COMPAT_SIGNAL)
		win->save_position_hook=windowmoved;
		#endif
	}
}

//Base class for a configuration dialog. Permits the setup of anything where you have a list of keyworded items, can create/retrieve/update/delete them by keyword.
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
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword.
	string actionbtn; //(DEPRECATED) If set, a special "action button" will be included, otherwise not. This is its caption.
	void action_callback() { } //(DEPRECATED) Callback when the action button is clicked (provide if actionbtn is set)
	constant allow_new=1; //Set to 0 to remove the -- New -- entry; if omitted, -- New -- will be present and entries can be created.
	constant allow_delete=1; //Set to 0 to disable the Delete button (it'll always be present)
	constant allow_rename=1; //Set to 0 to ignore changes to keywords
	constant strings=({ }); //Simple string bindings - see plugins/README
	constant ints=({ }); //Simple integer bindings, ditto
	constant bools=({ }); //Simple boolean bindings (to CheckButtons), ditto
	constant persist_key=0; //(string) Set this to the persist[] key to load items[] from; if set, persist will be saved after edits.
	//... end provide me.

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
		if (newkwd=="") return; //TODO: Be a tad more courteous.
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
		object ls=GTK2.ListStore(({"string"}));
		if (persist_key && !items) items=persist[persist_key];
		foreach (sort(indices(items)),string kwd) ls->set_value(ls->append(),0,kwd); //Is there no simpler way to pre-fill the liststore?
		object new; if (allow_new) ls->set_value(new=ls->append(),0,"-- New --");
		win->mainwindow=GTK2.Window(windowprops)
			->add(GTK2.Vbox(0,10)
				->add(GTK2.Hbox(0,5)
					->add(win->list=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
						->append_column(GTK2.TreeViewColumn("Item",GTK2.CellRendererText(),"text",0))
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
		win->sel=win->list->get_selection(); win->sel->select_iter(new||ls->get_iter_first()); sig_sel_changed();
		::makewindow();
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
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			actionbtn && gtksignal(win->pb_action,"clicked",action_callback),
			allow_delete && gtksignal(win->pb_delete,"clicked",pb_delete),
		});
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

ascii gypsum_version()
{
	return String.trim_all_whites(Stdio.read_file("VERSION"));
}

ascii pike_version()
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

//Redirect a stream to a specified file
//Undoes the redirect on destruction automatically.
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

//Unzip the specified data (should be exactly what could be read from/written to a .zip file)
//and call the callback for each file, with the file name, contents, and the provided arg.
//Note that content errors will be thrown, but previously-parsed content has already been
//passed to the callback. This may be considered a feature.
//Note that this can't cope with prefixed zip data (eg a self-extracting executable).
//Should this be shifted to update.pike? Nothing else uses it, currently, and it would
//allow stand-alone updates to ignore all of globals.pike.
void unzip(string data,function callback,mixed|void callback_arg)
{
	if (has_prefix(data,"PK\5\6")) return; //File begins with EOCD marker, must be empty.
	//NOTE: The CRC must be parsed as %+-4c, as Gz.crc32() returns a *signed* integer.
	while (sscanf(data,"PK\3\4%-2c%-2c%-2c%-2c%-2c%+-4c%-4c%-4c%-2c%-2c%s",
		int minver,int flags,int method,int modtime,int moddate,int crc32,
		int compsize,int uncompsize,int fnlen,int extralen,data))
	{
		string fn=data[..fnlen-1]; data=data[fnlen..]; //I can't use %-2H for these, because the two lengths come first and then the two strings. :(
		string extra=data[..extralen-1]; data=data[extralen..];
		string zip=data[..compsize-1]; data=data[compsize..];
		if (flags&8) {zip=data; data=0;} //compsize will be 0 in this case.
		string result,eos;
		switch (method)
		{
			case 0: result=zip; eos=""; break; //Stored (incompatible with flags&8 mode)
			case 8:
				#if constant(Gz)
				object infl=Gz.inflate(-15);
				result=infl->inflate(zip);
				eos=infl->end_of_stream();
				#else
				error("Gz module unavailable, cannot decompress");
				#endif
				break;
			default: error("Unknown compression method %d (%s)",method,fn); 
		}
		if (flags&8)
		{
			//The next block should be the CRC and size marker, optionally prefixed with "PK\7\b". Not sure
			//what happens if the crc32 happens to be exactly those four bytes and the header's omitted...
			if (eos[..3]=="PK\7\b") eos=eos[4..]; //Trim off the marker
			sscanf(eos,"%-4c%-4c%-4c%s",crc32,compsize,uncompsize,data);
		}
		#if __REAL__VERSION__<8.0
		//There seems to be a weird bug with Pike 7.8.866 on Windows which means that a correctly-formed ZIP
		//file will have end_of_stream() return 0 instead of "". No idea why. This is resulting in spurious
		//errors, For the moment, I'm just suppressing this error in that case.
		else if (!eos) ;
		#endif
		else if (eos!="") error("Malformed ZIP file (bad end-of-stream on %s)",fn);
		if (sizeof(result)!=uncompsize) error("Malformed ZIP file (bad file size on %s)",fn);
		#if constant(Gz)
		if (Gz.crc32(result)!=crc32) error("Malformed ZIP file (bad CRC on %s)",fn);
		#endif
		callback(fn,result,callback_arg);
	}
	if (data[..3]!="PK\1\2") error("Malformed ZIP file (bad signature)");
	//At this point, 'data' contains the central directory and the end-of-central-directory marker.
	//The EOCD contains the file comment, which may be of interest, but beyond that, we don't much care.
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
//Basic operations on it will continue to return hex integers.
//Note that it may be possible to simply subclass Gmp.mpz - test this, esp on
//older Pikes. Or just wait for 8.0 stable, then drop 7.8 support, then do it.
class Hex(int num)
{
	mixed cast(string type) {if (type=="int") return num;}
	int(0..1) is_type(string type) {if (type=="int") return 1;}
	#define lhs(x) mixed `##x(mixed ... others) {return this_program(`##x(num,@others));}
	#define lhsrhs(x) mixed `##x(mixed other) {return this_program(num x other);} mixed ``##x(mixed other) {return this_program(other x num);}
	lhs(!) lhs(~) lhs(<) lhs(>)
	lhsrhs(%) lhsrhs(&) lhsrhs(*) lhsrhs(+) lhsrhs(-) lhsrhs(/) lhsrhs(<<) lhsrhs(>>) lhsrhs(^) lhsrhs(|)
	#undef lhs
	#undef lhsrhs
	string _sprintf(int type,mapping|void params) {return sprintf(type=='O'?"0x%*x":(string)({'%','*',type}),params||([]),num);}
}

//Similarly, show a time value.
class Time
{
	inherit Hex;
	string _sprintf(int type,mapping|void params) {return type=='O'?format_time(num):sprintf((string)({'%','*',type}),params||([]),num);}
}

//Probe a plugin and return a program usable for retrieving constants, but not
//for instantiation. This should be used any time the program won't be cloned,
//as it avoids creating log entries under that file name, and also permits the
//plugin to avoid loading itself completely. If there's any sort of exception,
//UNDEFINED will be returned; compilation errors are silenced.
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
