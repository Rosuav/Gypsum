//Generic globally accessible data. Accessible everywhere as G->G->whatever.
mapping(string:mixed) G=([]); 

//G->globals->whatever is equivalent to the bare name whatever, and can be used
//in situations where it'd be awkward to use #if constant(whatever) or equiv.
mapping(string:mixed) globals=([]);
mapping(string:array(string)) globalusage=([]); //Every time a file looks for something that's in globals, its filename is added to here.
array(string) needupdate=({}); //Any time anything is found to be in need of updating, it'll be added to this array. Whatever triggered the update should then go through this list and process them all.

class mymaster /* Oh, my master! */
{
	inherit "/master";
	void create()
	{
		//Copy from normal master
		object old_master=master();
		foreach (indices(old_master),string cur) catch {this[cur]=old_master[cur];};
	}
	mixed resolv(string what,string where)
	{
		if (globals[what])
		{
			//werror("resolv(%O,%O)  --> globals\n",what,where);
			if (where && where!="" && where[0]!='.' && !has_value(globalusage[what],where)) globalusage[what]+=({where});
			return globals[what];
		}
		return ::resolv(what,where);
	}
}

/**
 * Compile one file into memory and permit it to register itself
 *
 * Errors are sent to stderr, unlike the similar global function.
 */
void bootstrap(string c)
{
	program compiled;
	mixed ex=catch {compiled=compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex=catch {compiled(c);}) werror(describe_backtrace(ex)+"\n");
	werror("Bootstrapped "+c+"\n");
}

/**
 * Adds a constant to the global constant list. Allows for inheritance checks.
 *
 * @param Name	Name of the constant
 * @param Val	Value of the contant
 */
void add_gypsum_constant(string name,mixed val)
{
	globals[name]=val;
	if (globalusage[name])
	{
		foreach (globalusage[name],string cur) if (!has_value(needupdate,cur)) needupdate+=({cur}); //Note: Does not use set operations; order is preserved.
	}
	globalusage[name]=({}); //Empty out the list, if there is one.
}

//Global so it can be queried by Advanced Options in window.pike
mapping(string:int) compat=([
	"signal":([7.8:734,8.0:0])[__REAL_VERSION__]>__REAL_BUILD__, //Inability to connect 'before' a signal
	"pausekey":0, //"Pause" key generates VoidSymbol 0xFFFFFF instead of Pause 0xFF13. No longer active by default as it causes problems on Windows 8.
	"boom2":([7.8:872,8.0:4])[__REAL_VERSION__]>__REAL_BUILD__, //Lacks the 'boom2' bugfix - see usage
	"msgdlg":([7.8:876,8.0:0])[__REAL_VERSION__]>__REAL_BUILD__, //MessageDialog parent bug
]);

void create(string|void name)
{
	if (name!="gypsum.pike") return; //Normal startup - do nothing. Do these checks only if we're '/update'd.
	object G=all_constants()["G"];
	//Update everything else (except persist). Note that the rules about what gets
	//updated are here in this file, and not in update.pike itself; this means that
	//it's the new version, not the old version, that defines it. Downloading (via
	//git or http) a new set of files and then updating gypsum.pike from that set
	//will be the standard way of grabbing new code from now on, I think.
	G->needupdate+=({"globals.pike"});
	//Add any new COMPAT options, based on their defaults
	foreach (indices(compat)-indices(G->compat),string kwd) if (compat[kwd]) add_constant("COMPAT_"+upper_case(kwd),1);
	G->compat=compat;
}

int main(int argc,array(string) argv)
{
	replace_master(mymaster());

	//Use the usual add_constant for these, not add_gypsum_constant(). They won't be replaced.
	add_constant("add_gypsum_constant",add_gypsum_constant);
	add_constant("G",this);
	add_constant("started",time());
	bootstrap("persist.pike");

	foreach (compat;string kwd;int dflt)
	{
		int config=globals->persist["compat/"+kwd];
		if (config==1 || (!config && dflt)) add_constant("COMPAT_"+upper_case(kwd),1);
	}

	GTK2.setup_gtk();
	//These are initialized in dependency order. Everyone uses globals, window uses connection::send (which is
	//actually circular, but connection has a patch hook for say), and plugins (loaded by window) depend on core.
	bootstrap("globals.pike");
	add_constant("INIT_GYPSUM_VERSION",globals->gypsum_version());
	bootstrap("connection.pike");
	bootstrap("window.pike");
	if (!globals->say) {GTK2.MessageDialog(0,0,GTK2.BUTTONS_OK,"Startup error - see log for details.")->show()->signal_connect("response",lambda() {exit(0);}); return -1;}
	if (sizeof(needupdate) && G->commands->update) G->commands->update(".",0); //Rebuild anything that needs it
	if (G->commands->connect) //Note that without this plugin, connecting sockets will be impossible. This MAY make Gypsum mostly useless.
	{
		array(string) worlds=argv[1..];
		if (!sizeof(worlds))
		{
			//TODO: Optionally grab the saved list.
			//For now, just ensure that it's not completely empty
			worlds=({""});
		}
		G->commands->connect(worlds[0],G->window->win->tabs[0]); //Connect to the first world, or give world list, in the initial tab.
		if (sizeof(worlds)>1) foreach (worlds[1..],string world) G->commands->connect(world,0); //Connect to the others with a null subw, which will create another tab.
	}
	return -1;
}
