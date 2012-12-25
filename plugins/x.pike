inherit command;

void compile_error(string fn,int l,string msg) {say("Compilation error on line "+l+": "+msg+"\n");}
void compile_warning(string fn,int l,string msg) {say("Compilation warning on line "+l+": "+msg+"\n");}
int process(string param,mapping(string:mixed) subw)
{
	program tmp; mixed err,ret;
	err=catch {tmp=compile_string(#"
GTK2.Window mw=G->G->window->mainwindow;
object window=G->G->window;
//Add any other 'convenience names' here

mixed foo()
{
	mixed ret="+param+#";
	return ret;
}",".exec",this);};
	if (err) {say(sprintf("Error in compilation: %O\n",err),subw); return 1;}
	err=catch {ret=tmp()->foo();};
	if (err) {say(sprintf("Error in execution: %O\n",err),subw); return 1;}
	say(sprintf("%O\n",ret),subw);
	return 1;
}
