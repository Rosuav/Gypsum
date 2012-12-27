mapping(string:mixed) G=([]); //Stuff stuff in here. It'll be available as G->G->blah globally.

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

void bootstrap(string c)
{
	program compiled;
	mixed ex=catch {compiled=compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	compiled(c); //Trigger a create() or create(string) function
	werror("Bootstrapped "+c+"\n");
}

void my_add_constant(string name,mixed val) //Hooks all add_constant calls and allows for inheritance checks.
{
	globals[name]=val;
	if (globalusage[name])
	{
		foreach (globalusage[name],string cur) if (!has_value(needupdate,cur)) needupdate+=({cur});
	}
	globalusage[name]=({}); //Empty out the list, if there is one.
}

void tell(string msg) {werror(msg);}

void bootstrap_all(string dir) //Recursively bootstrap all .pike files in dir and its subdirectories
{
	foreach (sort(get_dir(dir)),string cur) catch
	{
		string c=dir+"/"+cur;
		if (file_stat(c)->isdir) bootstrap_all(c);
		else if (c[strlen(c)-5..]==".pike") bootstrap(c);
	};
}

int main(int argc,array(string) argv)
{
	replace_master(mymaster());
	add_constant("add_constant",my_add_constant); //Wheee! Override add_constant.
	add_constant("G",this); //Let this one go with the usual add_constant.
	my_add_constant("started",time());
	if ((string)GTK2.version()<"\2\26") add_constant("GTK_BUGGY",1);

	//Be careful of the order of these. There may be dependancies.
	bootstrap("globals.pike");
	bootstrap("connection.pike");
	bootstrap("window.pike");
	if (!globals->say) return 1;
	bootstrap("commands.pike");
	bootstrap_all("plugins");
	if (sizeof(needupdate) && G->commands->update) G->commands->update(".",0); //Rebuild anything that needs it
	if (G->commands->connect)
	{
		G->commands->connect((argv+({""}))[1],G->window->tabs[0]); //Connect to the first world, or give world list, in the initial tab.
		foreach (argv[2..],string world) G->commands->connect(world,0); //Connect to the others with a null subw, which will create another tab.
	}
	return -1;
}
