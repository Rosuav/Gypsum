/** 
 * Global collection of commands. 
 * Used to store plugin commands, and allows for dynamic loading.
 * Access: G->G-><command>
 */
mapping(string:mixed) G=([]); 

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
 * Compiles provided pike modules thereby loading them into memory.
 *
 * @param c   File name of the pick file to be compiled.
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
 * Searches a provided directory and sub directories for pike files to be compiled.
 *
 * @param dir Name of directory to be searched.
 */
void bootstrap_all(string dir) //Recursively bootstrap all .pike files in dir and its subdirectories
{
	foreach (sort(get_dir(dir)),string cur) if (mixed ex=catch
	{
		string c=dir+"/"+cur;
		if (file_stat(c)->isdir) bootstrap_all(c);
		else if (has_suffix(c,".pike")) bootstrap(c);
	}) werror("Error bootstrapping %s: %s\n",cur,describe_backtrace(ex)); //If error, report it and move on - plugins can happily be reloaded later.
}

/**
 * Adds a constant to the global constant list. Allows for inheritance checks.
 *
 * @param Name	Name of the constant
 * @param Val	Value of the contant
 */
void add_gypsum_constant(string name,mixed val) //Adds a constant, similar to add_constant, but allows for inheritance checks.
{
	globals[name]=val;
	if (globalusage[name])
	{
		foreach (globalusage[name],string cur) if (!has_value(needupdate,cur)) needupdate+=({cur});
	}
	globalusage[name]=({}); //Empty out the list, if there is one.
}


/**
 * Driver function for the Gypsum application
 *
 * @param Argc	number of @paramuments passed in from the command line
 * @param Argv array of @paramuments passed in from the commadnd line
 */
int main(int @paramc,array(string) @paramv)
{
	replace_master(mymaster());
	
	add_constant("add_gypsum_constant",add_gypsum_constant);
	add_constant("G",this); //Let this one go with the usual add_constant.
	add_constant("started",time());
	bootstrap("globals.pike"); //Note that compat options are NOT set when globals is loaded. If this is a problem, break out persist into its own file.
	add_constant("INIT_GYPSUM_VERSION",globals->gypsum_version());
	
	mapping(string:int) compat=([
		"scroll":(string)GTK2.version()<"\2\26", //Scroll bug - seems to have been fixed somewhere between 2.12 and 2.22 (\2\26 being octal for 2.22)
		"signal":__REAL_VERSION__<7.9 || __REAL_BUILD__<=5, //Inability to connect 'before' a signal (fixed by Pike commit b29c8c so some 7.9.5 builds will have it and others won't)
	]);
	
	foreach (compat;string kwd;int dflt)
	{
		int config=globals->persist["compat/"+kwd];
		if (config==1 || (!config && dflt)) add_constant("COMPAT_"+upper_case(kwd),1);
	}

	//Be careful of the order of these. There may be dependencies.
	bootstrap("connection.pike");
	bootstrap("window.pike");
	if (!globals->say) return 1;
	bootstrap_all("plugins");
	if (sizeof(needupdate) && G->commands->update) G->commands->update(".",0); //Rebuild anything that needs it
	if (G->commands->connect)
	{
		G->commands->connect((Argv+({""}))[1],G->window->tabs[0]); //Connect to the first world, or give world list, in the initial tab.
		if (Argc>2) foreach (Argv[2..],string world) G->commands->connect(world,0); //Connect to the others with a null subw, which will create another tab.
	}
	return -1;
}
