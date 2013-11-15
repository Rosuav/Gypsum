//Keep-alive: sends IAC GA every four minutes (time-delay configurable).
//Does not reset a MUD's idea of your idle time (confirmed with Threshold RPG and Minstrel Hall).
inherit command;

/**
 * Instantiates the ka class.
 *
 * @param name Name of the class instance.
 */
void create(string name)
{
	if (!G->G->commands->ka) process(0,0);
	::create(name);
}

/**
 * Updates the keep alive time.
 *
 * @param param The time to which to update the keep alive time value
 * @param subw 	The subwindow whose keepalive time is being updated and the window which all statues messages are displayed
 * @return int 	1 if the value was successfully updated, zero if it wasn't and instead set back to the default value of 240. 
 */
int process(string|void param,mapping(string:mixed) subw)
{
	if (!param)
	{
		//Call-out
		//TODO: Currently broken, fix it to actually work. And drop the 'command' status now that it can be controlled through Options|Advanced.
		if (G->G->sock && G->G->sock->is_open()) G->G->sock->write("\xFF\xF9");
		call_out(G->G->commands->ka,persist["ka/delay"] || 240);
		return 0;
	}
	//Command
	int delay=(int)param;
	if (delay<=0) {say("%% After how many seconds should keepalive be retriggered?",subw); return 1;}
	persist["ka/delay"]=delay;
	say("%% Will send keep-alive every "+delay+" seconds.",subw);
	return 1;
}
