inherit cmdbase;

void compile_error(string fn,int l,string msg) {say("Compilation error on line "+l+": "+msg+"\n");}
void compile_warning(string fn,int l,string msg) {say("Compilation warning on line "+l+": "+msg+"\n");}
int process(string param)
{
	program tmp; mixed err,ret;
	err=catch {tmp=compile_string("mixed foo()\n{mixed ret="+param+"; return ret;}",".exec",this);};
	if (err) {say(sprintf("Error in compilation: %O\n",err)); return 1;}
	err=catch {ret=tmp()->foo();};
	if (err) {say(sprintf("Error in execution: %O\n",err)); return 1;}
	say(sprintf("%O\n",ret));
	return 1;
}
