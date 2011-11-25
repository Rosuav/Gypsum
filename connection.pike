//Connection handler.

Stdio.File sock;
string curmsg="";

void create(string name)
{
	sock=G->G->sock;
	G->G->connect=connect;
	//Note: Doesn't copy in curmsg.
}
int sockconnected(int success)
{
	if (success) say("%%% Connected to Threshold RPG.");
	else say("%%% Error connecting to Threshold RPG: "+sock->errno());
	sock->set_nonblocking(sockread,0,sockclose);
}

string readbuffer="";
string getchr()
{
	//return sock->read(1);
	if (readbuffer=="") readbuffer=sock->read(1024,1);
	string c=readbuffer[0..0]; readbuffer=readbuffer[1..]; return c;
}
int getc() {return getchr()[0];}
void sockread(string|void starting)
{
	if (!starting)
	{
		if (!sock->connect(G->G->conn_host,G->G->conn_port)) {say("%%% Error connecting to Threshold RPG: "+sock->errno()); sock->close(); return;}
		say("%%% Connected to Threshold RPG.");
	}
	else readbuffer=starting;
	enum {IS=0x00,ECHO=0x01,SEND=0x01,SUPPRESSGA=0x03,TERMTYPE=0x18,NAWS=0x1F,SE=0xF0,GA=0xF9,SB,WILL,WONT,DO=0xFD,DONT,IAC=0xFF};
	int bold=0;
	string ungetc;
	while (1)
	{
		string chr;
		if (ungetc) {chr=ungetc; ungetc=0;}
		else {chr=getchr(); if (chr=="") break;}
		if (G->G->connect!=connect) {G->G->sockthrd=thread_create(function_object(G->G->connect)->sockread,chr+readbuffer); return;} //Code's been updated. (Is this check too expensive?)
		switch (chr[0])
		{
			case 7: break; //Beep
			//case 255: say(sprintf("%%%% IAC %02X %02X",getc(),getc())); break;
			case 255: //IAC
			{
				//switch (int iaccode=getc())
				int iaccode=getc();
				//say(sprintf("%%%% IAC %02X",iaccode));
				switch (iaccode)
				{
					case IAC: curmsg+="\xFF"; break;
					case DO: case DONT: case WILL: case WONT:
					{
						switch (getc())
						{
							case ECHO: if (iaccode==WILL) ; else ; break; //Password mode on/off
							case NAWS: if (iaccode==DO) sock->write((string)({IAC,SB,NAWS,0,80,0,0,IAC,SE})); break;
							case TERMTYPE: if (iaccode==DO) sock->write((string)({IAC,WILL,TERMTYPE})); break;
							case SUPPRESSGA: break; //Do we need this?
							default: break;
						}
						break;
					}
					case SB:
					{
						string subneg="";
						while (1)
						{
							string c=getchr();
							subneg+=c;
							if (c[0]==IAC && getc()==SE) break; //Any other TELNET commands inside subneg will be buggy unless they're IAC IAC doubling (which this handles correctly)
						}
						switch (subneg[0])
						{
							case TERMTYPE: if (subneg[1]==SEND) sock->write((string)({IAC,SB,TERMTYPE,IS})+"Gypsum"+(string)({IAC,SE})); break;
							default: break;
						}
					}
					case SE: break;
					case GA:
					{
						//Prompt! Woot!
						G->G->window->prompt=curmsg; G->G->window->redraw();
						curmsg="";
						break;
					}
					default: break;
				}
				break;
			}
			case 27:
			{
				//ANSI sequence.
				if (getchr()!="[") break;
				int fg=-1,bg=-1;
				while (has_value("0123456789;",chr=getchr())) switch (chr)
				{
					case "3": fg=(int)getchr(); break;
					case "4": bg=(int)getchr(); break;
					case "0": bold=0; fg=7; bg=0; break;
					case "1": bold=8; break;
					case "2": bold=0; break;
					default: break;
				}
				if (fg!=-1) fg+=bold;
				curmsg+=G->G->window->mkcolor(fg,bg);
				break;
			}
			case '\r': if ((readbuffer!="" || sock->peek()) && (ungetc=getchr())=="\n") ungetc=0;
			case '\n':
			{
				//say("line");
				G->G->window->say_raw(curmsg);
				curmsg="";
				break;
			}
			case '<': curmsg+="&lt;"; break;
			default: curmsg+=chr;
		}
	}
}
int sockclose(Stdio.File socket)
{
	say("%%% Disconnected from server.");
	sock=0;
}
void connect()
{
	if (sock) sock->close();
	say("Connecting to "+G->G->conn_host+" : "+G->G->conn_port+"...");
	sock=Stdio.File(); sock->open_socket(); //Odd Pike bug? 7.8.352 on Windows fails on the async_connect if this has been done.
	G->G->sock=sock;
	G->G->sockthrd=thread_create(sockread);
}
