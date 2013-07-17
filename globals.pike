void create(string n,string which)
{
	array(string) arr=indices(this);
	if (which && which!="") arr=which/" ";
	foreach (arr,string f) if (f!="create") add_constant(f,this[f]);
	if (!G->G->commands) G->G->commands=([]);
	if (!G->G->hooks) G->G->hooks=([]);
	if (!G->G->windows) G->G->windows=([]);
}

//Usage: Instead of G->G->asdf->qwer(), use bouncer("asdf","qwer") and it'll late-bind.
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

object persist=class(string savefn)
{
	//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
	//It's also undying storage. When it dies, bring it back one way or the other. :)
	/* Usage:
	 * persist["some/string/identifier"]=any_value;
	 * retrieved_value=persist["some/string/identifier"];
	 * old_value=m_delete(persist,"some/string/identifier");
	 * Saves to disk after every change. Loads from disk only on initialization - /update this file to reload.
	 * Note that saving is done with a call_out(0), so you can freely batch your modifications without grinding the disk too much - especially if your code is itself happening on the backend thread.
	 **/

	/* Idea: Encrypt the file with a password.
	string pwd;
	string key=Crypto.SHA256.hash("Gypsum"+string_to_utf8(pwd)+"Gypsum");
	string content=encode_value(data);
	int pad=16-sizeof(content)%16; //Will always add at least 1 byte of padding; if the data happens to be a multiple of 16 bytes, will add an entire leading block of padding.
	content=(string)allocate(pad,pad)+content;
	string enc=Crypto.AES.encrypt(key,content);

	if (catch {
		string dec=Crypto.AES.decrypt(key,enc);
		if (dec[0]>16) throw(1); //Must be incorrect password - the padding signature is damaged.
		dec=dec[dec[0]..]; //Trim off the padding
		data=decode_value(dec);
	}) error("Incorrect password.");
	*/

	mapping(string:mixed) data=([]);
	int saving;

	void create()
	{
		catch //Ignore any errors, just have no saved data.
		{
			Stdio.File f=Stdio.File(savefn);
			if (!f) return;
			string raw=f->read();
			if (!raw) return;
			mixed decode=decode_value(raw);
			if (mappingp(decode)) data=decode;
		};
	}
	mixed `[](string idx) {return data[idx];}
	mixed `[]=(string idx,mixed val)
	{
		if (!saving) {saving=1; call_out(save,0);}
		return data[idx]=val;
	}
	mixed _m_delete(string idx)
	{
		if (!saving) {saving=1; call_out(save,0);}
		return m_delete(data,idx);
	}
	void save()
	{
		saving=0;
		Stdio.write_file(savefn,encode_value(data));
	}
}(".gypsumrc"); //Save file name. TODO: Make this configurable somewhere.

//Something like strftime(3). If passed an int, is equivalent to strftime(format,gmtime(tm)).
//Recognizes a subset of strftime(3)'s formatting codes - notably not the locale-based ones.
//Month/day names are not localized.
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
		win->mainwindow->set_skip_taskbar_hint(1)->set_skip_pager_hint(1)->show_all();
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
	//Create and return a widget (most likely a layout widget) representing all the custom content.
	//If allow_rename (see below), this must assign to win->kwd a GTK2.Entry for editing the keyword;
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or it may be a GTK2.Label, or it may be omitted altogether).
	GTK2.Widget make_content() { }
	mapping(string:mapping(string:mixed)) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping.
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping. The mapping is already inside items[], so this is also a good place to trigger a persist[] save.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
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
	}

	void dosignals()
	{
		win->signals=({
			actionbtn && gtksignal(win->pb_action,"clicked",action_callback),
			gtksignal(win->pb_save,"clicked",pb_save),
			gtksignal(win->pb_close,"clicked",lambda() {win->mainwindow->destroy();}), //Has to be done with a lambda, I think to dispose of the args
			gtksignal(win->sel,"changed",selchanged),
		});
	}
}
