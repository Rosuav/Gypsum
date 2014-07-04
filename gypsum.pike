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
 * Errors are sent to stderr, unlike the similar function in update.pike.
 */
void bootstrap(string c)
{
	program compiled;
	mixed ex=catch {compiled=compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	compiled(c); //Trigger a create() or create(string) function
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

//Global so that (in theory) it can be used elsewhere
mapping(string:int) compat=([
	"scroll":(string)GTK2.version()<"\2\26", //Scroll bug - seems to have been fixed somewhere between 2.12 and 2.22 (\2\26 being octal for 2.22)
	"signal":([7.8:734,7.9:6,8.0:0])[__REAL_VERSION__]>__REAL_BUILD__, //Inability to connect 'before' a signal
	"pausekey":0, //"Pause" key generates VoidSymbol 0xFFFFFF instead of Pause 0xFF13. No longer active by default as it causes problems on Windows 8.
	"boom2":1, //Lacks the 'boom2' bugfix - see usage
]);

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

	//These are initialized in dependency order. Everyone uses globals, window uses connection::send (that's
	//actually circular, but connection has a patch hook for say), and plugins (loaded by window) depend on core.
	bootstrap("globals.pike");
	add_constant("INIT_GYPSUM_VERSION",globals->gypsum_version());
	bootstrap("connection.pike");
	bootstrap("window.pike");
	if (!globals->say) return 1;
	if (sizeof(needupdate) && G->commands->update) G->commands->update(".",0); //Rebuild anything that needs it
	if (G->commands->connect) //TODO: Don't have this depend on a plugin, move the relevant code into core
	{
		G->commands->connect((argv+({""}))[1],G->window->tabs[0]); //Connect to the first world, or give world list, in the initial tab.
		if (argc>2) foreach (argv[2..],string world) G->commands->connect(world,0); //Connect to the others with a null subw, which will create another tab.
	}
	return -1;
}
