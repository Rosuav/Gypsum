/* 
 * Generic globally accessible data
 * Accessible everywhere as G->G->whatever.
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
 * Compile one file into memory and permit it to register itself
 *
 * @param c   File name of the pike file to be compiled.
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
 * Searches a provided directory and subdirectories for pike files to be compiled.
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
void add_gypsum_constant(string name,mixed val)
{
	globals[name]=val;
	if (globalusage[name])
	{
		foreach (globalusage[name],string cur) if (!has_value(needupdate,cur)) needupdate+=({cur}); //Note: Does not use set operations; order is preserved.
	}
	globalusage[name]=({}); //Empty out the list, if there is one.
}


/**
 * Driver function for the Gypsum application
 *
 * @param argc number of arguments passed in from the command line
 * @param argv array of arguments passed in from the commadnd line
 */
int main(int argc,array(string) argv)
{
	replace_master(mymaster());

	//Use the usual add_constant for these, not add_gypsum_constant(). They won't be replaced.
	add_constant("add_gypsum_constant",add_gypsum_constant);
	add_constant("G",this);
	add_constant("started",time());
	bootstrap("persist.pike");
	
	mapping(string:int) compat=([
		"scroll":(string)GTK2.version()<"\2\26", //Scroll bug - seems to have been fixed somewhere between 2.12 and 2.22 (\2\26 being octal for 2.22)
		"signal":([7.8:734,7.9:6,8.0:0])[__REAL_VERSION__]>__REAL_BUILD__, //Inability to connect 'before' a signal
		"boom2":1, //Lacks the 'boom2' bugfix - see usage
	]);
	
	foreach (compat;string kwd;int dflt)
	{
		int config=globals->persist["compat/"+kwd];
		if (config==1 || (!config && dflt)) add_constant("COMPAT_"+upper_case(kwd),1);
	}

	//Be careful of the order of these. There may be dependencies.
	bootstrap("globals.pike");
	add_constant("INIT_GYPSUM_VERSION",globals->gypsum_version());
	bootstrap("connection.pike");
	bootstrap("window.pike");
	if (!globals->say) return 1;
	bootstrap_all("plugins");
	if (sizeof(needupdate) && G->commands->update) G->commands->update(".",0); //Rebuild anything that needs it
	if (G->commands->connect)
	{
		G->commands->connect((argv+({""}))[1],G->window->tabs[0]); //Connect to the first world, or give world list, in the initial tab.
		if (argc>2) foreach (argv[2..],string world) G->commands->connect(world,0); //Connect to the others with a null subw, which will create another tab.
	}
	return -1;
}
