//Connection handler.

Stdio.File sock;
object sockthrd;
array curmsg=({0,""});
object curcolor;
string curline="";
string worldname;
object display; //References the subwindow object (see window.pike)
string conn_host;
int conn_port;

void create(string|object uplink)
{
	if (stringp(uplink))
	{
		//Code's been updated.
		G->G->connection=this_program;
		return;
	}
	//If we get here, we're a real connection - either snagging an old one or creating a new one.
	if (uplink->readbuffer)
	{
		//Snag info from the other one, we're taking over from it.
		sock=uplink->sock; display=uplink->display;
		//Note: Doesn't copy in curmsg/curline.
		return;
	}
	//Otherwise, we're a new connection.
	display=uplink;
}

string readbuffer="";
string getchr()
{
	//return sock->read(1); //This is what getchr() effectively does. Do a little buffering, though, for performance's sake.
	if (readbuffer=="")
	{
		readbuffer=sock->read(1024,1) || "";
		if (readbuffer=="") return "";
	}
	string c=readbuffer[0..0]; readbuffer=readbuffer[1..]; return c;
}
int getc() {return getchr()[0];}
void sockread(string|void starting)
{
	if (!starting)
	{
		if (!sock->connect(conn_host,conn_port)) {display->say("%%% Error connecting to "+worldname+": "+sock->errno()); sock->close(); return;}
		display->say("%%% Connected to "+worldname+".");
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
		if (G->G->connection!=this_program)
		{
			//Code's been updated.
			thread_create((display->connection=G->G->connection(this))->sockread,chr+readbuffer);
			destruct(); //Just in case.
			return;
		}
		switch (chr[0])
		{
			case 7: break; //Beep
			//case 255: display->say(sprintf("%%%% IAC %02X %02X",getc(),getc())); break;
			case 255: //IAC
			{
				//switch (int iaccode=getc())
				int iaccode=getc();
				//display->say(sprintf("%%%% IAC %02X",iaccode));
				switch (iaccode)
				{
					case IAC: curmsg[-1]+="\xFF"; curline+="\xFF"; break;
					case DO: case DONT: case WILL: case WONT:
					{
						switch (getc())
						{
							case ECHO: if (iaccode==WILL) display->password(); else display->unpassword(); break; //Password mode on/off
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
						curmsg[-1]=utf8_to_string(curmsg[-1]);
						display->prompt=curmsg; display->redraw();
						curmsg=({curcolor,curline=""});
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
				curmsg[-1]=utf8_to_string(curmsg[-1]);
				curmsg+=({curcolor=display->mkcolor(fg,bg),""});
				break;
			}
			case '\r': if ((readbuffer!="" || sock->peek()) && (ungetc=getchr())=="\n") ungetc=0;
			case '\n':
			{
				curmsg[-1]=utf8_to_string(curmsg[-1]);
				if (!dohooks(utf8_to_string(curline))) display->say(curmsg);
				curmsg=({curcolor,curline=""});
				break;
			}
			default: curmsg[-1]+=chr; curline+=chr;
		}
	}
	display->say("%%% Disconnected from server.");
	display->prompt=({ });
	destruct(); //Clean up this object and zero out its entry in the corresponding window object
}
int dohooks(string line)
{
	array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks); //Sort by name for consistency
	foreach (hooks,object h) if (mixed ex=catch {if (h->outputhook(line)) return 1;}) display->say("Error in hook: "+describe_error(ex));
}
int sockclose(Stdio.File socket)
{
	display->say("%%% Disconnected from server.");
	sock=0;
}
void connect(mapping info)
{
	if (sock) sock->close();
	display->say("Connecting to "+(conn_host=info->host)+" : "+(conn_port=(int)info->port)+"...");
	worldname=info->name;
	sock=Stdio.File(); sock->open_socket(); //Odd Pike bug? 7.8.352 on Windows fails on the async_connect if this has been done.
	sockthrd=thread_create(sockread);
}
