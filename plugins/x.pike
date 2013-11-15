inherit command;
inherit hook;

/* Command executor and expression evaluator

Has two distinct modes, similar but with a few different operations. In the future one of them may be deprecated in favour of the other, but for now I'm undecided.

Classic mode is convenient as a calculator and so on; it is primarily designed for a simple expression, and must handle but a single line of input. It is accessed by the "/x" command.

Hilfe mode calls on Tools.Hilfe (the same as Pike's inbuilt interactive mode), and can handle multi-line expressions/commands, but is less convenient for simple actions as it requires
the input to be properly terminated (usually that means adding a semicolon). It is accessed by the "pike" command, eg "pike 1+1;", and will consume all input if it believes that more is
needed to complete the current command.
*/


/**
 * parses the input line from a sub window and passes it to the pike Hilfe
 *
 * Hilfe mode: "pike 1+1;" - allows full Pike syntax under Hilfe rules.
 *
 * @param 	line 	The line to be processed
 * @param 	subw	The sub window from which the line was collected a where to direct all output.
 * @return	int		Always returns 1
 */
int inputhook(string line,mapping(string:mixed) subw)
{
	if (!subw->hilfe_saved_prompt)
	{
		if (!has_prefix(line,"pike ")) //Normal input
		{
			//Check for the special "calculator notation"
			if (sscanf(line,"calc %s",string expr) || sscanf(line,"%s$[%s]%s",string before,expr,string after)) catch
			{
				int val=compile_string("int _() {return "+expr+";}")()->_();
				if (before) G->G->connection->write(subw->connection,before+val+(after||"")+"\r\n"); //Command with embedded expression
				else say("%% "+val,subw); //"calc" command
				return 1;
			};
			return 0;
		}
		line=line[5..]; //Command starting "pike " - skip the prefix.
	}
	//else this is a continuation; the whole line goes to Hilfe.
	if (!subw->hilfe) (subw->hilfe=Tools.Hilfe.Evaluator())->write=lambda(string l) {G->G->window->say(l,subw);};
	int wasfinished=subw->hilfe->state->finishedp();
	mapping vars=subw->hilfe->variables; vars->subw=subw; vars->mw=(vars->window=G->G->window)->mainwindow;
	subw->hilfe->add_input_line(line);
	int nowfinished=subw->hilfe->state->finishedp();
	if (wasfinished==nowfinished) return 1;
	if (nowfinished) subw->prompt=m_delete(subw,"hilfe_saved_prompt");
	else {subw->hilfe_saved_prompt=subw->prompt; subw->prompt=({G->G->window->colors[7],"hilfe> "});}
	return 1;
}

//Direct compilation mode - the original. Convenient for single expressions.
/**
 * Displays all errors created during compile
 *
 * @param fn 	unused
 * @param l		the line which caused the compile error.
 * @param msg	the compile error
 */
void compile_error(string fn,int l,string msg) {say("Compilation error on line "+l+": "+msg+"\n");}

/**
 * Displays all warnings created during compile
 *
 * @param fn 	unused
 * @param l		the line which caused the compile warning.
 * @param msg	the compile warning
 */
void compile_warning(string fn,int l,string msg) {say("Compilation warning on line "+l+": "+msg+"\n");}

/**
 * Processes the string and displays the resulting output to the sub window provided.
 *
 * @param 	param	unused
 * @param 	subw	the sub window which to send all output
 * @return 	int		always returns 1
 */
int process(string param,mapping(string:mixed) subw)
{
	program tmp; mixed err,ret;
	err=catch {tmp=compile_string(#"
	GTK2.Window mw=G->G->window->mainwindow;
	object window=G->G->window;
	//Add any other 'convenience names' here

	mixed foo(mapping(string:mixed) subw)
	{
		mixed ret="+param+#";
		return ret;
	}",".exec",this);};
	
	if (err) {say(sprintf("Error in compilation: %O\n",err),subw); return 1;}
	err=catch {ret=tmp()->foo(subw);};
	if (err) {say(sprintf("Error in execution: %O\n",err),subw); return 1;}
	say(sprintf("%O\n",ret),subw);
	return 1;
}

/**
 * Creates an instance of this class.
 *
 * @param name	The name of the instance of this class.
 */	
void create(string name) {::create(name);}
