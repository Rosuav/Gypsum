inherit command;
inherit plugin_menu;

constant plugin_active_by_default = 1;

string origin(function|object func)
{
	//Always go via the program, in case the function actually comes from an inherited parent.
	program pgm=functionp(func)?function_program(func):object_program(func);
	string def=Program.defined(pgm);
	return def && (def/":")[0]; //Assume we don't have absolute Windows paths here, which this would break
}

//Figure out an actual file name based on the input
//Returns the input unchanged if nothing is found, but tries hard to find something.
//The provided subw is just for error messages. Will return 0 if there's an error.
string fn(mapping subw,string param)
{
	if (has_prefix(param,"/") && !has_suffix(param,".pike"))
	{
		//Allow "update /blah" to update the file where /blah is coded
		//Normally this will be "plugins/blah.pike", which just means you can omit the path and extension, but it helps with aliasing.
		function f=G->G->commands[param[1..]];
		if (!f) {say(subw,"%% Command not found: "+param[1..]+"\n"); return 0;}
		string def=origin(f);
		if (!def) {say(subw,"%% Function origin not found: "+param[1..]+"\n"); return 0;}
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

//Callbacks for 'update zip'
void data_available(object q,mapping(string:mixed) subw)
{
	if (mixed err=catch {unzip(q->data(),lambda(string fn,string data)
	{
		fn=fn[14..]; //14 == sizeof("Gypsum-master/")
		if (fn=="") return; //Ignore the first-level directory entry
		if (fn[-1]=='/') mkdir(fn); else Stdio.write_file(fn,data);
	});}) {say(subw,"%% "+describe_error(err)); return;}
	process("all",subw);
}
void request_ok(object q,mapping(string:mixed) subw) {q->async_fetch(data_available,subw);}
void request_fail(object q,mapping(string:mixed) subw) {say(subw,"%% Failed to download latest Gypsum");}

/**
 * Recompiles the provided plugin
 *
 * @param param The plugin to be updated
 * @param subw	The sub window which is updating the plugin
 * @return int	always returns 1
 */
int process(string param,mapping(string:mixed) subw)
{
	if (param=="") {say(subw,"%% Update what?"); return 1;}
	int cleanup=sscanf(param,"force %s",param); //Use "/update force some-file.pike" to clean up after building
	if (param=="git")
	{
		say(subw,"%% Attempting git-based update...");
		Stdio.File stdout=Stdio.File(),stderr=Stdio.File();
		int start_time=time(1)-60;
		Process.create_process(({"git","pull","--rebase"}),(["stdout":stdout->pipe(Stdio.PROP_IPC),"stderr":stderr->pipe(Stdio.PROP_IPC),"callback":lambda()
		{
			say(subw,"git-> "+replace(String.trim_all_whites(stdout->read()),"\n","\ngit-> "));
			say(subw,"git-> "+replace(String.trim_all_whites(stderr->read()),"\n","\ngit-> "));
			process("all",subw); //TODO: Update only those that have file_stat(f)->mtime>start_time
		}]));
		return 1;
	}
	if (param=="zip")
	{
		#if Protocols.HTTP.do_async_method
		//Note that the canonical URL is the one in the message, but Pike 7.8 doesn't follow redirects.
		Protocols.HTTP.do_async_method("GET","https://codeload.github.com/Rosuav/Gypsum/zip/master",0,0,
			Protocols.HTTP.Query()->set_callbacks(request_ok,request_fail,subw));
		say(subw,"%% Downloading https://github.com/Rosuav/Gypsum/archive/master.zip ...");
		#else
		say(subw,"%% Pike lacks HTTP engine, unable to download updates");
		#endif
		return 1;
	}
	//Update everything by updating globals; everything's bound to use at least something.
	//NOTE: Does NOT update persist.pike, deliberately.
	if (param=="all") param="globals.pike";
	if (!(param=fn(subw,param))) return 1;
	object self=(param[0]!='.') && build(param); //"build ." to just rebuild what's already in queue
	//Check for anything that inherits what we just updated, and recurse.
	//The list will be built by the master object, we just need to process it (by recompiling things).
	//Note that I don't want to simply use foreach here, because the array may change.
	array(string) been_there_done_that=({param}); //Don't update any file more than once. (I'm not sure what should happen if there's circular references. Let's just hope there aren't any.)
	while (sizeof(G->needupdate))
	{
		string cur=G->needupdate[0]; G->needupdate-=({cur}); //Is there an easier way to take the first element off an array?
		if (!has_value(been_there_done_that,cur)) {been_there_done_that+=({cur}); build(cur);}
	}
	if (cleanup && self) call_out(unload,.01,param,subw,self); //An update-force should do a cleanup, but let any waiting call_outs happen first.
	return 1;
}

//Attempt to unload a plugin completely, or do the cleanup after a force update.
int unload(string param,mapping(string:mixed) subw,object|void keepme)
{
	int confirm=sscanf(param,"confirm %s",param);
	if (keepme) confirm=1; //When we're doing a clean-up, always do the removal
	if (!(param=fn(subw,param))) return 1;
	say(subw,"%% "+param+" provides:");
	multiset(object) selfs=(<>); //Might have multiple, if there've been several versions.

	//Broken out in a vain attempt to bring some clarity to this pile of differences.
	//It might be worth unifying some of these things - for instance, always having a
	//mapping, rather than storing the object or function directly. But that would be
	//overkill in other areas... warping other code for the sake of this is backward,
	//so make changes ONLY if it's an improvement elsewhere.
	int reallydelete(object self,string desc)
	{
		if (self==keepme) say(subw,"%% (current) "+desc);
		else if (keepme) say(subw,"%% (old) "+desc);
		else say(subw,"%% "+desc);
		if (confirm && self!=keepme) return selfs[self]=1;
	};

	foreach (G->G->commands;string name;function func) if (origin(func)==param)
	{
		if (reallydelete(function_object(func),"Command: /"+name)) m_delete(G->G->commands,name);
	}
	foreach (G->G->hooks;string name;object obj) if (origin(obj)==param)
	{
		if (reallydelete(obj,"Hook: "+name)) m_delete(G->G->hooks,name);
	}
	foreach (G->G->plugin_menu;string name;mapping data) if (name && origin(data->self)==param) //Special: G->G->plugin_menu[0] is not a mapping.
	{
		if (reallydelete(data->self,"Menu item: "+data->menuitem->get_child()->get_text()))
			({m_delete(G->G->plugin_menu,name)->menuitem})->destroy();
	}
	foreach (G->G->windows;string name;mapping data) if (origin(data->self)==param)
	{
		//Try to show the caption of the window, if it exists.
		string desc="["+name+"]"; //Note that this also covers movablewindow and configdlg, which are special cases of window.
		if (data->mainwindow) desc=data->mainwindow->get_title(); 
		if (reallydelete(data->self,"Window: "+desc))
			if (object win=m_delete(G->G->windows,name)->mainwindow) win->destroy();
	}
	foreach (G->G->statustexts;string name;mapping data) if (origin(data->self)==param)
	{
		//Try to show the current contents (may not make sense for non-text statusbar entries)
		string desc="["+name+"]";
		catch {desc=data->lbl->get_text();};
		if (reallydelete(data->self,"Status bar: "+desc))
		{
			//Scan upward from lbl until we find the Hbox that statusbar entries get packed into.
			//If we don't find one, well, don't do anything. That shouldn't happen though.
			GTK2.Widget cur=m_delete(G->G->statustexts,name)->lbl;
			while (GTK2.Widget parent=cur->get_parent())
			{
				if (parent==G->G->window->statusbar) {cur->destroy(); break;}
				cur=parent;
			}
		}
	}
	if (!keepme) foreach (G->globalusage;string globl;array(string) usages) if (has_value(usages,param))
	{
		//Doesn't use reallydelete() as it can't distinguish current from old (hence this whole block
		//is done only if (!keepme) ie if it's a full unload).
		say(subw,"%% Global usage: "+globl);
		if (confirm) G->globalusage[globl]-=({param});
	}
	#if constant(COMPAT_SIGNAL)
	foreach (G->G->enterpress;object focus;function callback) if (origin(callback)==param)
		if (reallydelete(function_object(callback),sprintf("Enter-press: %O -> %s",focus,function_name(callback))))
			m_delete(G->G->enterpress,focus);
	#endif
	if (confirm)
	{
		foreach (selfs;object self;) destruct(self);
		if (keepme) say(subw,"%% All old removed."); else say(subw,"%% All above removed.");
	}
	else say(subw,"%% To remove the above, type: /unload confirm "+param);
	return 1;
}

/**
 * Catch compilation errors and warnings and send them to the current subwindow
 *
 * @param fn 	unused
 * @param l	the line which caused the compile error.
 * @param msg	the compile error
 */
void compile_error(string fn,int l,string msg) {say(0,"Compilation error on line "+l+": "+msg+"\n");}
void compile_warning(string fn,int l,string msg) {say(0,"Compilation warning on line "+l+": "+msg+"\n");}

/**
 * Compile one pike file and let it initialize itself, similar to bootstrap()
 *
 * Unlike bootstrap(), sends errors to a local subw.
 */
object build(string param)
{
	if (!(param=fn(0,param))) return 0;
	if (!file_stat(param)) {say(0,"File not found: "+param+"\n"); return 0;}
	say(0,"%% Compiling "+param+"...");
	program compiled; catch {compiled=compile_file(param,this);};
	if (!compiled) {say(0,"%% Compilation failed.\n"); return 0;}
	say(0,"%% Compiled.");
	return compiled(param);
}

string mode = file_stat(".git") ? "git" : "zip";
constant menu_label="Update Gypsum";
void menu_clicked() {process(mode,G->G->window->current_subw());}

void create(string name)
{
	::create(name);
	set_menu_text(menu_label+" ("+mode+")");
	G->G->commands->unload=unload;
}
