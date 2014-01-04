//Connection handler.

/**
 * Everything works with a mapping(string:mixed) conn; some of its handy elements include:
 * 
 * Stdio.File sock;
 * object sockthrd;
 * array curmsg=({0,""});
 * int fg,bg,bold; //Current color, in original ANSI form
 * object curcolor;
 * string worldname;
 * object display; //References the subwindow object (see window.pike)
 * string conn_host;
 * int conn_port;
 * string readbuffer="",ansibuffer="",curline=""; //Read buffers, at various levels - normally empty except during input processing, but will retain data if there's an incomplete TELNET or ANSI sequence
 * int lastcr; //Set to 1 if the last textread ended with \r - if the next one starts \n, the extra blank line is suppressed (it's a \r\n sequence broken over two socket reads)
 * string writeme=""; //Write buffer
 * Stdio.File logfile; //If non-zero, all text will be logged to this file, after TELNET/ANSI codes and prompts are removed.
 * 
 */

void create(string name)
{
	G->G->connection=this;
}

/**
 * Convert a stream of 8-bit data into Unicode
 * May eventually need to be given the conn, and thus be able to negotiate an
 * encoding with the server; currently tries UTF-8 first, and if that fails,
 * falls back on Latin-1, statelessly.
 *
 * @param bytes Incoming data, 8-bit string
 * @return string Resulting data, now to be treated as Unicode
 */
protected string bytes_to_string(string bytes)
{
	catch {return utf8_to_string(bytes);}; //Normal case: Decode as UTF-8
	//Failure case: Decode as Latin-1 with a bit of CP-1252.
	//Use Latin-1 (the decoder for which in Pike is the identity function), but
	//replace a handful of byte values that have no meaning in Unicode anyway.
	//Seems to work well for Threshold RPG, and isn't incompatible with the
	//normal handling of UTF-8.
	return replace(bytes,({"\x91","\x92","\x93","\x94"}),({"\u2018","\u2019","\u201c","\u201d"}));
}

/**
 * Handles a block of text after ANSI processing.
 *
 * @param conn Current connection
 * @param data Bytes from socket, with newlines separating lines
 */
void textread(mapping conn,string data)
{
	//werror("textread: %O\n",data);
	if (sizeof(data) && data[0]=='\n' && conn->lastcr) data=data[1..];
	conn->lastcr=sizeof(data) && data[-1]=='\r';
	data=replace(data,({"\r\n","\n\r","\r"}),"\n");
	if (has_value(data,7))
	{
		//TODO: Beep. (Maybe once for each \7 in the text; maybe not.)
		data-="\7";
	}
	while (sscanf(data,"%s\n%s",string line,data))
	{
		conn->curmsg[-1]+=line;
		line=conn->curline+line;
		if (!dohooks(conn,line))
		{
			G->G->window->say(conn->curmsg,conn->display);
			if (conn->logfile) conn->logfile->write("%s\n",line);
		}
		conn->curmsg=({([]),conn->curcolor,conn->curline=""});
	}
	conn->curmsg[-1]+=data; conn->curline+=data;
}

/**
 * Handles a block of text after TELNET processing.
 *
 * @param conn Current connection
 * @param data Unicode data from socket, with ANSI codes marking colors
 */
void ansiread(mapping conn,string data)
{
	//werror("ansiread: %O\n",data);
	conn->ansibuffer+=data;
	while (sscanf(conn->ansibuffer,"%s\x1b%s",string data,string ansi)) if (mixed ex=catch
	{
		//werror("HAVE ANSI CODE\nPreceding data: %O\nANSI code and subsequent: %O\n",data,ansi);
		textread(conn,data); conn->ansibuffer="\x1b"+ansi;
		//werror("ANSI code: %O\n",(ansi/"m")[0]);
		if (ansi[0]!='[') {textread(conn,"\\e"); conn->ansibuffer=ansi; continue;} //Report an escape character as the literal string "\e" if it doesn't start an ANSI code
		colorloop: for (int i=1;i<sizeof(ansi)+1;++i) switch (ansi[i]) //Deliberately go past where we can index - if we don't have the whole ANSI sequence, leave the unprocessed text and wait for more data from the socket.
		{
			case '3': conn->fg=ansi[++i]-'0'; break;
			case '4': conn->bg=ansi[++i]-'0'; break;
			case '0': conn->bold=0; conn->fg=7; conn->bg=0; break;
			case '1': conn->bold=8; break;
			case '2': conn->bold=0; break;
			case ';': break;
			case 'm':
				conn->curmsg[-1]=conn->curmsg[-1];
				conn->curmsg+=({conn->curcolor=G->G->window->mkcolor(conn->fg+conn->bold,conn->bg),""});
				ansi=ansi[i+1..];
				break colorloop;
			default: werror("Unparseable ANSI sequence: %O\n",ansi); return;
		}
		conn->ansibuffer=ansi;
	}) {/*werror("ERROR in ansiread: %s\n",describe_backtrace(ex));*/ return;}
	textread(conn,conn->ansibuffer); conn->ansibuffer="";
}

enum {IS=0x00,ECHO=0x01,SEND=0x01,SUPPRESSGA=0x03,TERMTYPE=0x18,NAWS=0x1F,SE=0xF0,GA=0xF9,SB,WILL,WONT,DO=0xFD,DONT,IAC=0xFF};

/**
 * Socket read callback. Handles TELNET protocol, then passes actual socket text along to ansiread().
 *
 * @param conn Current connection
 * @param data Raw bytes received from the socket (note, assumed to be UTF-8 encoded except for TELNET codes)
 */
void sockread(mapping conn,string data)
{
	//werror("sockread: %O\n",data);
	conn->readbuffer+=data;
	while (sscanf(conn->readbuffer,"%s\xff%s",string data,string iac)) if (mixed ex=catch
	{
		ansiread(conn,bytes_to_string(data)); conn->readbuffer="\xff"+iac;
		switch (iac[0])
		{
			case IAC: data+="\xFF"; iac=iac[1..]; break;
			case DO: case DONT: case WILL: case WONT:
			{
				switch (iac[1])
				{
					case ECHO: if (iac[0]==WILL) G->G->window->password(conn->display); else G->G->window->unpassword(conn->display); break; //Password mode on/off
					case NAWS: if (iac[0]==DO) write(conn,(string)({IAC,SB,NAWS,0,80,0,0,IAC,SE})); break;
					case TERMTYPE: if (iac[0]==DO) write(conn,(string)({IAC,WILL,TERMTYPE})); break;
					case SUPPRESSGA: break; //Do we need this?
					default: break;
				}
				iac=iac[2..];
				break;
			}
			case SB:
			{
				string subneg;
				for (int i=1;i<sizeof(iac);++i)
				{
					if (iac[i]==IAC && iac[++i]==SE) {subneg=iac[..i]; iac=iac[i+1..]; break;} //Any other TELNET commands inside subneg will be buggy unless they're IAC IAC doubling (which this handles correctly)
				}
				if (!subneg) return; //We don't have the complete subnegotiation. Wait till we do. (Actually, omitting this line will have the same effect, because the subscripting will throw an exception. So this is optional, and redundant, just like this sentence is redundant.)
				switch (subneg[1])
				{
					case TERMTYPE: if (subneg[2]==SEND) write(conn,(string)({IAC,SB,TERMTYPE,IS})+"Gypsum"+(string)({IAC,SE})); break;
					default: break;
				}
			}
			case SE: break; //Shouldn't happen.
			case GA:
			{
				//Prompt! Woot!
				conn->curmsg[-1]=bytes_to_string(conn->curmsg[-1]);
				conn->curmsg[0]->timestamp=time(1);
				conn->display->prompt=conn->curmsg; G->G->window->redraw(conn->display);
				conn->curmsg=({([]),conn->curcolor,conn->curline=""});
				iac=iac[1..];
				break;
			}
			default: break;
		}
		conn->readbuffer=iac;
	}) {/*werror("ERROR in sockread: %s\n",describe_backtrace(ex));*/ return;} //On error, just go back and wait for more data. Really, this ought to just catch IndexError in the event of trying to read too far into iac[], but I can't be bothered checking at the moment.
	ansiread(conn,bytes_to_string(conn->readbuffer)); conn->readbuffer="";
}

/**
 * Execute all registered plugin outputhooks
 */
int dohooks(mapping conn,string line)
{
	array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks); //Sort by name for consistency
	foreach (hooks,object h) if (mixed ex=catch {if (h->outputhook(line,conn)) return 1;}) G->G->window->say("Error in hook: "+describe_backtrace(ex),conn->display);
}

/**
 * Closes the socket connection for the provided connection.
 *
 * @param conn Current connection
 */
int sockclosed(mapping conn)
{
	G->G->window->say("%%% Disconnected from server.",conn->display);
	conn->display->prompt=({([])});
	conn->sock=0; //Break refloop
	if (conn->ka) remove_call_out(conn->ka);
	m_delete(conn,"logfile");
}

/**
 * Write buffered socket text as much as possible
 *
 * @param conn Current connection
 */
void sockwrite(mapping conn)
{
	if (!conn->sock) return;
	if (conn->writeme!="") conn->writeme=conn->writeme[conn->sock->write(conn->writeme)..];
}

/**
 * Buffered write to socket
 *
 * @param conn Current connection
 * @param data The data to be written to the socket.
 */
void write(mapping conn,string data)
{
	if (data) conn->writeme+=data;
	sockwrite(conn);
}

//Callback bouncers. TODO: Replace the callbacks rather than using these
void sockreadb(mapping conn,string data) {G->G->connection->sockread(conn,data);}
void sockwriteb(mapping conn) {G->G->connection->sockwrite(conn);}
void sockclosedb(mapping conn) {G->G->connection->sockclosed(conn);}

/**
 * Callback for when a connection is successfully established.
 *
 * @param conn Current connection
 */
void connected(mapping conn)
{
	G->G->window->say("%%% Connected to "+conn->worldname+".",conn->display);
	conn->curmsg=({([]),0,""}); conn->readbuffer=conn->ansibuffer=conn->curline="";
	conn->sock->set_nonblocking(sockreadb,sockwriteb,sockclosedb);
	if (conn->use_ka) conn->ka=call_out(ka,persist["ka/delay"] || 240,conn);
}

/**
 * Callback for when the connection fails. Displays the disconnection error details.
 *
 * @param conn Current connection
 */
void connfailed(mapping conn)
{
	G->G->window->say(sprintf("%%%%%% Error connecting to %s: %s [%d]",conn->worldname,strerror(conn->sock->errno()),conn->sock->errno()),conn->display);
	conn->sock->close();
	sockclosed(conn);
	return;
}

/**
 * Sends a telnet keep alive packet.
 *
 * @param conn Current connection
 */
void ka(mapping conn)
{
	write(conn,"\xFF\xF9");
	conn->ka=conn->use_ka && call_out(ka,persist["ka/delay"] || 240,conn);
}

/**
 * Establishes a connection with with the provided world and links it to a display
 *
 * @param display 	The display (subwindow) to which the connection should be linked
 * @param info	  	The information about the world to which the connection should be established
 * @return mapping	Returns a mapping detailing the connection
 */
mapping connect(object display,mapping info)
{
	mapping(string:mixed) conn=(["display":display,"recon":info->recon,"use_ka":info->use_ka || zero_type(info->use_ka),"writeme":info->writeme||""]);
	G->G->window->say("%%% Connecting to "+(conn->host=info->host)+" : "+(conn->port=(int)info->port)+"...",conn->display);
	conn->worldname=info->name;
	conn->sock=Stdio.File(); conn->sock->set_id(conn); //Refloop
	conn->sock->open_socket();
	if (conn->sock->nodelay) conn->sock->nodelay(); //Disable Nagling, if possible (requires Pike patch not in trunk as of 20131206)
	conn->sock->set_nonblocking(0,connected,connfailed);
	conn->sock->connect(conn->host,conn->port);
	string fn=info->logfile && strftime(info->logfile,localtime(time(1)));
	if (info->logfile && info->logfile!="")
	{
		if (mixed ex=catch {conn->logfile=Stdio.File(fn,"wac");}) G->G->window->say(sprintf("%%%% Unable to open log file %O\n%%%% %s",fn,describe_error(ex)));
		else G->G->window->say(sprintf("%%%% Logging to %O",fn));
	}
	return conn;
}
