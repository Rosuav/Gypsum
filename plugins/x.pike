#charset utf8
inherit command;
inherit hook;

constant plugin_active_by_default = 1;

constant docstring=#"
Command executor and expression evaluator

Has two distinct modes, similar but with a few different operations. One is
simpler, the other more flexible, and it's worth keeping both.

Classic mode is convenient as a calculator and so on; it is primarily designed
for a simple expression, and must handle but a single line of input. It is
accessed by the \"/x\" command. It's the best way to manipulate the internals of
Gypsum, and it has some convenience shorthands which can be seen by looking at
the source; also, it's a powerful Unicode text manipulator, with slicing, joining,
and NFC/NFD transformations easily available. (Use '/x' on its own to quickly see
the last result as text, rather than in the normal disambiguation display.)

Hilfe mode calls on Tools.Hilfe (the same as Pike's inbuilt interactive mode),
and can handle multi-line expressions/commands, but is less convenient for
simple actions as it requires the input to be properly terminated (usually that
means adding a semicolon). It is accessed by the \"pike\" command, eg \"pike 1+1;\",
and will consume all input if it believes that more is needed to complete the
current command.

Note that typing \"pike\" on its own does not enter you into a different-prompt
mode. This has sometimes surprised me, but I don't think it's really worth the
trouble of fixing; for one thing, it'd require some means of knowing when to
revert to MUD mode. Leave this as an unresolved issue unless some superb
solution can be found.
";

string calculate(mapping(string:mixed) subw,string expr)
{
	catch
	{
		int explain=sscanf(expr,"#%s",expr);
		sscanf(expr,"%s:%s",expr,string fmt);
		mixed prev=subw->last_calc_result;
		if (intp(prev) || floatp(prev)) prev=sprintf("int|float _=%O;\n",prev);
		else prev="";
		int|float val=compile_string(prev+"int|float calc() {return "+expr+";}",0,G->G->window)()->calc();
		subw->last_calc_result=val;
		if (fmt) fmt=sprintf("%"+(fmt-"%"),val); else fmt=(string)val;
		if (explain) fmt=expr+" = "+fmt;
		return (string)fmt;
	};
	return expr;
}

int input(mapping(string:mixed) subw,string line)
{
	if (!subw->hilfe_saved_prompt)
	{
		if (line=="pike")
		{
			say(subw,"%% Due to parser limitations, you can't simply 'enter Pike mode'.");
			say(subw,"%% Put the beginning of your command on the same line as 'pike'.");
			return 1;
		}
		if (!has_prefix(line,"pike ")) //Normal input
		{
			//Check for the special "calculator notation". Note that inline calculation should avoid
			//subscripting, as it can't handle nested square brackets. The first ']' in the string
			//ends the expression. (You could use "calc expr" followed by "$[_]" to get past that,
			//but there are other limitations, eg the :fmt notation, so this shouldn't be treated as
			//a fully-general expression evaluator. Use "/x" or "pike" for that.)
			if (sscanf(line,"calc %s",string expr)) {say(subw,"%% "+calculate(subw,expr)); return 1;}
			string newcmd="";
			while (sscanf(line,"%s$[%s]%s",string before,string expr,string after)) {newcmd+=before+calculate(subw,expr); line=after||"";}
			if (newcmd!="") {nexthook(subw,newcmd+line); return 1;}
			return 0;
		}
		line=line[5..]; //Command starting "pike " - skip the prefix.
	}
	//else this is a continuation; the whole line goes to Hilfe.
	if (!subw->hilfe) (subw->hilfe=Tools.Hilfe.Evaluator())->write=lambda(string l) {say(subw,l);}; //Refloop - broken in closetab()
	int wasfinished=subw->hilfe->state->finishedp();
	//Reinstate certain expected variables every command
	mapping vars=subw->hilfe->variables; vars->subw=subw; vars->window=G->G->window;
	subw->hilfe->add_input_line(line);
	int nowfinished=subw->hilfe->state->finishedp();
	if (wasfinished==nowfinished) return 1;
	//NOTE: This is a bit hacky, and reaches into internals a bit. This should not be taken as
	//an example of best-practice. I may at some point create a documented way to do this.
	if (nowfinished) subw->prompt=m_delete(subw,"hilfe_saved_prompt");
	else {subw->hilfe_saved_prompt=subw->prompt; subw->prompt=({([]),G->G->window->mkcolor(7,0),"hilfe> "});}
	return 1;
}

int closetab(mapping(string:mixed) subw,int index) {m_delete(subw,"hilfe");} //Break the refloop

//Direct compilation mode - the normal usage. Convenient for single expressions.
int process(string param,mapping(string:mixed) subw)
{
	if (param=="")
	{
		//Hack: Type "/x" on its own to say() the last result - strings only.
		//Very handy if it was a non-ASCII string and you want to see it as
		//characters rather than codepoints (the default %O is designed so you
		//can unambiguously identify codepoints, but it doesn't let you see
		//what the characters themselves look like, nor usefully copy/paste).
		if (stringp(G->G->last_x_result)) say(subw,G->G->last_x_result);
		else say(subw,"%% Type '/x some_expression' to calculate something.");
		return 1;
	}
	program tmp; mixed err;
	err=catch {tmp=compile_string(#"
	object window=G->G->window;
	mixed x=Hex;
	float pi=3.141592653589793; float π=pi;
	float tau=pi*2, τ=π*2;
	Time tm(string|int t,int ... parts) {if (stringp(t)) {parts=(array(int))(t/\":\"); t=0;} foreach (parts,int p) t=(t*60)+p; return Time(t);}
	//Allow say(str) without extra boilerplate (declared int rather than void so it quietly returns zero - no warning about void expressions)
	int say(mixed ... args) {if (sizeof(args)==1 || stringp(args[0])) window->say(0,@args); else window->say(@args);}
	string nfc(string txt) {return Unicode.normalize(txt,\"NFC\");} function NFC=nfc;
	string nfd(string txt) {return Unicode.normalize(txt,\"NFD\");} function NFD=nfd;
	string nfkc(string txt) {return Unicode.normalize(txt,\"NFKC\");} function NFKC=nfkc;
	string nfkd(string txt) {return Unicode.normalize(txt,\"NFKD\");} function NFKD=nfkd;
	//Add any other 'convenience names' here

	mixed foo(mapping(string:mixed) subw,mixed _)
	{
		mixed ret="+param+#";
		return ret;
	}",".exec",G->G->window);};
	
	if (err) {say(subw,"Error in compilation: %O\n",err); return 1;}
	err=catch {G->G->last_x_result=tmp()->foo(subw,G->G->last_x_result);};
	if (err) {say(subw,"Error in execution: "+describe_backtrace(err)); return 1;}
	say(subw,"%O\n",G->G->last_x_result);
	return 1;
}

void create(string name) {::create(name);}
