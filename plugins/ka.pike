//Keep-alive: sends IAC GA every four minutes (time-delay configurable).
//Does not reset a MUD's idea of your idle time (confirmed with Threshold RPG and Minstrel Hall).
inherit command;

void create(string name)
{
	if (!G->G->commands->ka) process(0);
	::create(name);
}

int process(string|void param)
{
	if (!param)
	{
		//Call-out
		if (G->G->sock && G->G->sock->is_open()) G->G->sock->write("\xFF\xF9");
		call_out(G->G->commands->ka,persist["ka/delay"] || 240);
		return 0;
	}
	//Command
	int delay=(int)param;
	if (delay<=0) {say("%% After how many seconds should keepalive be retriggered?"); return 1;}
	persist["ka/delay"]=delay;
	say("%% Will send keep-alive every "+delay+" seconds");
	return 1;
}
