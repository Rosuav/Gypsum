inherit command;
inherit hook;

constant plugin_active_by_default = 1;

/* Command executor and expression evaluator

Has two distinct modes, similar but with a few different operations. In the future one of them may be deprecated in favour of the other, but for now I'm undecided.

Classic mode is convenient as a calculator and so on; it is primarily designed for a simple expression, and must handle but a single line of input. It is accessed by the "/x" command.

Hilfe mode calls on Tools.Hilfe (the same as Pike's inbuilt interactive mode), and can handle multi-line expressions/commands, but is less convenient for simple actions as it requires
the input to be properly terminated (usually that means adding a semicolon). It is accessed by the "pike" command, eg "pike 1+1;", and will consume all input if it believes that more is
needed to complete the current command.
*/

string calculate(mapping(string:mixed) subw,string expr)
{
	catch
	{
		int explain=has_prefix(expr,"#");
		mixed prev=subw->last_calc_result;
		if (intp(prev) || floatp(prev)) prev=sprintf("int|float _=%O;\n",prev);
		else prev="";
		int|float|string val=compile_string(prev+"int|float calc() {return "+expr[explain..]+";}",0,this)()->calc();
		subw->last_calc_result=val;
		if (explain) val=expr[1..]+" = "+val;
		return val;
	};
	return expr;
}

int inputhook(string line,mapping(string:mixed) subw)
{
	if (!subw->hilfe_saved_prompt)
	{
		if (!has_prefix(line,"pike ")) //Normal input
		{
			//Check for the special "calculator notation"
			if (sscanf(line,"calc %s",string expr)) {say(subw,"%% "+calculate(subw,expr)); return 1;}
			string newcmd="";
			while (sscanf(line,"%s$[%s]%s",string before,string expr,string after)) {newcmd+=before+calculate(subw,expr); line=after||"";}
			if (newcmd!="") {nexthook(subw,newcmd+line); return 1;}
			return 0;
		}
		line=line[5..]; //Command starting "pike " - skip the prefix.
	}
	//else this is a continuation; the whole line goes to Hilfe.
	if (!subw->hilfe) (subw->hilfe=Tools.Hilfe.Evaluator())->write=lambda(string l) {say(subw,l);}; //Note that this is a refloop. :(
	int wasfinished=subw->hilfe->state->finishedp();
	mapping vars=subw->hilfe->variables; vars->subw=subw; vars->mw=(vars->window=G->G->window)->mainwindow;
	subw->hilfe->add_input_line(line);
	int nowfinished=subw->hilfe->state->finishedp();
	if (wasfinished==nowfinished) return 1;
	if (nowfinished) subw->prompt=m_delete(subw,"hilfe_saved_prompt");
	else {subw->hilfe_saved_prompt=subw->prompt; subw->prompt=({([]),G->G->window->mkcolor(7,0),"hilfe> "});}
	return 1;
}

//Direct compilation mode - the original. Convenient for single expressions.
/**
 * Catch compilation errors and warnings and send them to the current subwindow
 *
 * @param fn 	unused
 * @param l		the line which caused the compile error.
 * @param msg	the compile error
 */
void compile_error(string fn,int l,string msg) {say(0,"Compilation error on line "+l+": "+msg+"\n");}
void compile_warning(string fn,int l,string msg) {say(0,"Compilation warning on line "+l+": "+msg+"\n");}

int process(string param,mapping(string:mixed) subw)
{
	program tmp; mixed err;
	err=catch {tmp=compile_string(#"
	GTK2.Window mw=G->G->window->mainwindow;
	object window=G->G->window;
	//Add any other 'convenience names' here

	mixed foo(mapping(string:mixed) subw,mixed _)
	{
		mixed ret="+param+#";
		return ret;
	}",".exec",this);};
	
	if (err) {say(subw,"Error in compilation: %O\n",err); return 1;}
	err=catch {G->G->last_x_result=tmp()->foo(subw,G->G->last_x_result);};
	if (err) {say(subw,"Error in execution: %O\n",err); return 1;}
	say(subw,"%O\n",G->G->last_x_result);
	return 1;
}

void create(string name) {::create(name);}
