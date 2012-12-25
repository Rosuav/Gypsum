inherit command;

int process(string param,mapping(string:mixed) subw)
{
	if (param=="") {say("%% Update what?",subw); return 1;}
	if (has_prefix(param,"/") && !has_suffix(param,".pike"))
	{
		//Allow "update /blah" to update the file where /blah is coded
		//Normally this will be "plugins/blah.pike", which just means you can omit the path and extension, but it helps with aliasing.
		function f=G->G->commands[param[1..]];
		if (!f) {say("%% Command not found: "+param[1..]+"\n",subw); return 1;}
		string def=Program.defined(function_program(f)); //Don't just use Function.defined - sometimes process() is in an inherited parent.
		if (!def) {say("%% Function origin not found: "+param[1..]+"\n",subw); return 1;}
		param=def;
	}
	if (has_value(param,":")) sscanf(param,"%s:",param); //Turn "cmd/update.pike:4" into "cmd/update.pike". Also protects against "c:\blah".
	if (param[0]!='.') build(param); //"build ." to just rebuild what's already in queue
	//Check for anything that inherits what we just updated, and recurse.
	//The list will be built by the master object, we just need to process it (by recompiling things).
	//Note that I don't want to simply use foreach here, because the array may change.
	array(string) been_there_done_that=({param}); //Don't update any file more than once. (I'm not sure what should happen if there's circular references. Let's just hope there aren't any.)
	while (sizeof(G->needupdate))
	{
		string cur=G->needupdate[0]; G->needupdate-=({cur}); //Is there an easier way to take the first element off an array?
		if (!has_value(been_there_done_that,cur)) {been_there_done_that+=({cur}); build(cur);}
	}
	return 1;
}

void compile_error(string fn,int l,string msg) {say("Compilation error on line "+l+": "+msg+"\n");}
void compile_warning(string fn,int l,string msg) {say("Compilation warning on line "+l+": "+msg+"\n");}

void build(string param)
{
	string param2;
	if (has_prefix(param,"globals.pike")) sscanf(param,"%s %s",param,param2);
	if (!has_value(param,".") && !file_stat(param) && file_stat(param+".pike")) param+=".pike";
	if (!file_stat(param)) {say("File not found: "+param+"\n"); return;}
	say("%% Compiling "+param+"...");
	program compiled=compile_file(param,this);
	if (!compiled) {say("%% Compilation failed.\n"); return 0;}
	say("%% Compiled.");
	if (has_prefix(param,"globals.pike")) compiled(param,param2);
	else compiled(param);
}
