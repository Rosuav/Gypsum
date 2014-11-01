//Connection handler.

/*
 * Everything works with a mapping(string:mixed) conn; some of its handy elements include:
 * 
 * Stdio.File sock;
 * object sockthrd;
 * array curmsg;
 * int fg,bg,bold; //Current color, in original ANSI form
 * mixed curcolor;
 * string worldname;
 * mapping display; //References the subwindow data (see window.pike)
 * string conn_host;
 * int conn_port;
 * bytes readbuffer=""; //Raw socket read buffer - normally empty except during input processing, but will retain data if there's an incomplete TELNET sequence
 * string ansibuffer="",curline=""; //Read buffers at other levels - ditto (will retain if incomplete ANSI sequence, or partial line).
 * int lastcr; //Set to 1 if the last textread ended with \r - if the next one starts \n, the extra blank line is suppressed (it's a \r\n sequence broken over two socket reads)
 * bytes writeme=""; //Write buffer
 * Stdio.File logfile; //If non-zero, all text will be logged to this file, after TELNET/ANSI codes and prompts are removed.
 * 
 */

/*
Note that a subwindow (see window.pike and its mappings) has a maximum of one
connection, and the "maximum of" part is fairly optional (could be replaced by
"exactly" if desired). Why is it a separate mapping? Why not just pass the subw
to all connection.pike code, and stash stuff directly in there?

When a connection is reset, it's convenient and clean to completely replace the
connection mapping, thus guaranteeing that all state has been reset. Or, if you
look at it the other way around, stashing some piece of state in the connection
instead of the subw is the way to say "reset this when the connection closes".
Future policy: Ensure that everything retained is in subw[] not connection[].
Then it might be worth actually disposing of the connection mapping on close.
*/

void create(string name)
{
	G->G->connection=this;
	if (G->G->sockets) indices(G->G->sockets)->set_callbacks(sockread,sockwrite,sockclosed);
	else G->G->sockets=(<>);
	add_gypsum_constant("send",send);
}

//On first load, there won't be a global say, so any usage will bomb until
//window.pike gets loaded (trying to call the integer 0).
function say=G->globals->say;

/**
 * Convert a stream of 8-bit data into Unicode
 * May eventually need to be given the conn, and thus be able to negotiate an
 * encoding with the server; currently tries UTF-8 first, and if that fails,
 * falls back on CP-1252, statelessly. Note that this means that a mix of
 * UTF-8 and CP-1252 data will all be decoded as CP-1252, which may result in
 * some mojibake and even invalid characters (continuation bytes 81, 8D, 8F,
 * 90, and 9D are not defined in CP-1252, and will be replaced by U+FFFD).
 *
 * @param bytes Incoming 8-bit data
 * @return string Resulting Unicode text
 */
//object cp1252=Charset.decoder("1252");
object cp1252=Locale.Charset.decoder("1252"); //For compat with Pike 7.8, look it up from inside Locale.
protected string bytes_to_string(bytes data)
{
	catch {return utf8_to_string(data);}; //Normal case: Decode as UTF-8
	return cp1252->feed(data)->drain(); //Failure case: Decode as CP-1252.
}

//Mark the current text as a prompt
void setprompt(mapping conn)
{
	array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks);
	hooks->outputprompt(conn,conn->curline); //Call any that exist, ignore the others
	conn->curmsg[0]->timestamp=time(1);
	conn->display->prompt=conn->curmsg; G->G->window->redraw(conn->display);
	conn->curmsg=({([]),conn->curcolor,conn->curline=""});
	G->G->window->redraw(conn->display);
}

/**
 * Handles a block of text after ANSI processing.
 *
 * @param conn Current connection
 * @param data Text from socket, with newlines separating lines
 * @param end_of_block 1 if we're at the very end of a block of reading
 */
void textread(mapping conn,string data,int end_of_block)
{
	if (conn->debug_textread) say(conn->display,"textread [%d]: %O\n",end_of_block,data);
	if (sizeof(data) && data[0]=='\n' && conn->lastcr) data=data[1..];
	conn->lastcr=sizeof(data) && data[-1]=='\r';
	data=replace(data,({"\r\n","\n\r","\r"}),"\n");
	if (has_value(data,7))
	{
		string newdata=data-"\7";
		beep(sizeof(data)-sizeof(newdata)); //ie the number of \7 in the string
		data=newdata;
	}
	if (array old_prompt=m_delete(conn,"real_prompt"))
	{
		//There was a pseudo-prompt. If the user entered a non-local command,
		//optionally clear it out; otherwise, reinstate the real prompt and
		//let this go back to being part of a line of text. Note that the
		//real_prompt stashed prompt will be removed regardless.
		if (conn->display->prompt==conn->curmsg) conn->display->prompt=old_prompt;
		else if (!persist["prompt/retain_pseudo"]) conn->curmsg=({([]),conn->curcolor,conn->curline=""});
		//else we're retaining the pseudo-prompt as lines of text, and leaving no prompt because the user typed something, so do nothing
	}
	while (sscanf(data,"%s\n%s",string line,data))
	{
		conn->curmsg[-1]+=line;
		line=conn->curline+line;
		if (!dohooks(conn,line))
		{
			say(conn->display,conn->curmsg);
			if (conn->logfile) conn->logfile->write("%s\n",string_to_utf8(line));
		}
		conn->curmsg=({([]),conn->curcolor,conn->curline=""});
	}
	conn->curmsg[-1]+=data; conn->curline+=data;
	if (!end_of_block) return; //Check for prompts only at the end of a block of data from the socket
	string prompt_suffix = persist["prompt/suffix"] || "==> "; //This may become conn->prompt_suffix and world-configurable.
	if (prompt_suffix!="" && has_suffix(conn->curline,prompt_suffix))
	{
		//Let's pretend this is a prompt. Unfortunately that's not guaranteed, but
		//since it ends with the designated prompt suffix AND it's the end of a
		//socket read, let's hope.
		setprompt(conn);
	}
	else if (conn->curline!="") switch (persist["prompt/pseudo"] || ":>")
	{
		case "": break; //No pseudo-prompt handling.
		default: //Only if the prompt ends with one of the specified characters (and maybe spaces).
			string prompt=String.trim_all_whites(conn->curline);
			if (prompt=="" || !has_value(persist["prompt/pseudo"]||":>",prompt[-1])) break; //Not one of those characters. Not a pseudo-prompt.
			//But if it is, then fall through.
		case 1.0: //Treat everything as a pseudo-prompt.
			conn->real_prompt=conn->display->prompt;
			conn->display->prompt=conn->curmsg;
			G->G->window->redraw(conn->display);
			//Since this is a pseudo-prompt, don't clear anything out - just shadow the real prompt with this.
	}
}

/**
 * Handles a block of text after TELNET processing.
 *
 * @param conn Current connection
 * @param data Text from socket, with ANSI codes marking colors
 * @param end_of_block 1 if we're at the very end of a block of reading
 */
void ansiread(mapping conn,string data,int end_of_block)
{
	if (conn->debug_ansiread) say(conn->display,"ansiread: %O\n",data);
	conn->ansibuffer+=data;
	while (sscanf(conn->ansibuffer,"%s\x1b%s",string data,string ansi)) if (mixed ex=catch
	{
		//werror("HAVE ANSI CODE\nPreceding data: %O\nANSI code and subsequent: %O\n",data,ansi);
		textread(conn,data,0); conn->ansibuffer="\x1b"+ansi;
		//werror("ANSI code: %O\n",(ansi/"m")[0]);
		if (ansi[0]!='[') {textread(conn,"\\e",0); conn->ansibuffer=ansi; continue;} //Report an escape character as the literal string "\e" if it doesn't start an ANSI code
		array(int|string) params=({ }); int|string curparam=UNDEFINED;
		colorloop: for (int i=1;i<sizeof(ansi)+1;++i) switch (ansi[i]) //Deliberately go past where we can index - if we don't have the whole ANSI sequence, leave the unprocessed text and wait for more data from the socket.
		{
			case '0'..'9':
				if (undefinedp(curparam)) curparam=ansi[i]-'0';
				else curparam=curparam*10+ansi[i]-'0';
				break;
			case ';': params+=({curparam}); curparam=UNDEFINED; break;
			//case '"': //Read a string (not supported or needed, but if this were a generic parser, it would be)
			case 'A'..'Z': case 'a'..'z':
			{
				//We have a complete sequence now.
				if (!undefinedp(curparam)) params+=({curparam});
				switch (ansi[i]) //See if we understand the command.
				{
					case 'm': foreach (params,int|string param) if (intp(param)) switch (param)
					{
						case 0: conn->bold=0; conn->bg=0; conn->fg=7; break;
						case 1: conn->bold=8; break;
						case 2: conn->bold=0; break;
						case 30..37: conn->fg=param-30; break;
						case 40..47: conn->bg=param-40; break;
						default: break; //Ignore unknowns (currently without error)
					}
					conn->curmsg[-1]=conn->curmsg[-1];
					conn->curmsg+=({conn->curcolor=G->G->window->mkcolor(conn->fg+conn->bold,conn->bg),""});
					break;
					default: break; //Ignore unknowns without error
				}
				ansi=ansi[i+1..];
				break colorloop;
			}
			default: werror("Unparseable ANSI sequence: %O\n",ansi[..i]); return;
		}
		conn->ansibuffer=ansi;
	}) {/*werror("ERROR in ansiread: %s\n",describe_backtrace(ex));*/ return;}
	textread(conn,conn->ansibuffer,end_of_block); conn->ansibuffer="";
}

enum {IS=0x00,ECHO=0x01,SEND=0x01,SUPPRESSGA=0x03,TERMTYPE=0x18,NAWS=0x1F,SE=0xF0,GA=0xF9,SB,WILL,WONT,DO=0xFD,DONT,IAC=0xFF};

/**
 * Socket read callback. Handles TELNET protocol, then passes actual socket text along to ansiread().
 *
 * @param conn Current connection
 * @param data Raw bytes received from the socket (encoded text with embedded TELNET codes)
 */
void sockread(mapping conn,bytes data)
{
	if (conn->debug_sockread) say(conn->display,"sockread: %O\n",data);
	conn->readbuffer+=data;
	while (sscanf(conn->readbuffer,"%s\xff%s",string data,string iac)) if (mixed ex=catch
	{
		ansiread(conn,bytes_to_string(data),0); conn->readbuffer="\xff"+iac;
		switch (iac[0])
		{
			case IAC: ansiread(conn,"\xFF",0); conn->readbuffer=conn->readbuffer[2..]; break;
			case DO: case DONT: case WILL: case WONT:
			{
				switch (iac[1])
				{
					case ECHO: if (iac[0]==WILL) G->G->window->password(conn->display); else G->G->window->unpassword(conn->display); break; //Password mode on/off
					case NAWS: if (iac[0]==DO)
					{
						//TODO: Resend any time wrap width changes
						int width=persist["window/wrap"] || 80; //If we're not wrapping, pretend screen width is 80, although that's a bit arbitrary
						send_telnet(conn,(string(0..255))({SB,NAWS,width>>8,width&255,0,0}));
					}
					break;
					case TERMTYPE: if (iac[0]==DO) send_telnet(conn,(string(0..255))({WILL,TERMTYPE})); break;
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
					if (iac[i]==IAC && iac[++i]==SE) {subneg=iac[..i]; iac=iac[i+1..]; break;} //Any other TELNET commands inside subneg will be buggy unless they're IAC IAC doubling
				}
				if (!subneg) return; //We don't have the complete subnegotiation. Wait till we do. (Actually, omitting this line will have the same effect, because the subscripting will throw an exception. So this is optional, and redundant, just like this sentence is redundant.)
				subneg=replace(subneg,"\xFF\xFF","\xFF"); //Un-double IACs
				switch (subneg[1])
				{
					case TERMTYPE:
						//Note that this is slightly abusive of the "terminal type" concept - it's more like a user-agent string.
						//But it's already a bit stretched, as soon as specific clients get mentioned. And everybody does that.
						if (subneg[2]==SEND) send_telnet(conn,
							(string(0..255))({SB,TERMTYPE,IS})
							+[string(0..127)]sprintf("Gypsum %s (Pike %s)",gypsum_version(),pike_version())
						);
						break;
					default: break;
				}
				break;
			}
			case SE: break; //Shouldn't happen.
			case GA:
			{
				//Prompt! Woot!
				setprompt(conn);
				iac=iac[1..];
				break;
			}
			default: break;
		}
		conn->readbuffer=iac;
	}) {/*werror("ERROR in sockread: %s\n",describe_backtrace(ex));*/ return;} //On error, just go back and wait for more data. Really, this ought to just catch IndexError in the event of trying to read too far into iac[], but I can't be bothered checking at the moment.
	ansiread(conn,bytes_to_string(conn->readbuffer),1); conn->readbuffer="";
}

/**
 * Execute all registered plugin outputhooks
 */
int dohooks(mapping conn,string line)
{
	array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks); //Sort by name for consistency. May be worth keeping them sorted somewhere, but I'm not seeing performance problems.
	foreach (hooks,object h) if (mixed ex=catch {if (h->outputhook(line,conn)) return 1;}) say(conn->display,"Error in hook: "+describe_backtrace(ex));
}

//Closes the socket connection for the provided connection.
int sockclosed(mapping conn)
{
	say(conn->display,"%%% Disconnected from server.");
	G->G->window->unpassword(conn->display);
	conn->display->prompt=({([])});
	G->G->sockets[conn->sock]=0;
	conn->sock=0; //Break refloop
	if (conn->ka) remove_call_out(conn->ka);
	m_delete(conn,"logfile");
}

//Write as much buffered socket data as possible
void sockwrite(mapping conn)
{
	if (conn->sock && conn->writeme!="") conn->writeme=conn->writeme[conn->sock->write(conn->writeme)..];
}

/**
 * Buffered write to socket
 *
 * @param conn Current connection
 * @param text Text to be written to the socket - will be encoded UTF-8.
 */
void send(mapping conn,string text)
{
	if (!conn) return;
	if (conn->lines && !(conn=conn->connection)) return; //Allow sending to a subw (quietly ignoring if it's not connected)
	if (conn->passive) return; //Ignore sent text on passive masters
	if (text) conn->writeme+=string_to_utf8(text);
	sockwrite(conn);
}

//Send a TELNET sequence to the socket.
//The passed string should begin just after the IAC, so (string)({GA}) will send IAC GA.
//Subnegotiations will be implicitly terminated; (string)({SB,.....}) will have IAC SE appended.
//IAC doubling is performed automatically.
void send_telnet(mapping conn,bytes data)
{
	data="\xFF"+replace(data,"\xFF","\xFF\xFF");
	if (data[1]==SB) data+=(string(0..255))({IAC,SE});
	conn->writeme+=data;
	sockwrite(conn);
}

mapping(string:mixed) makeconn(object display,mapping info)
{
	mixed col=G->G->window->mkcolor(7,0);
	string writeme=string_to_utf8(info->writeme||"");
	if (writeme!="" && writeme[-1]!='\n') writeme+="\n"; //Ensure that the initial text ends with at least one newline
	writeme=replace(replace(writeme,"\n","\r\n"),"\r\r","\r"); //Clean up newlines just to be sure
	return ([
		"display":display,"worldname":info->name||"",
		"use_ka":info->use_ka || undefinedp(info->use_ka),
		"writeme":writeme,"readbuffer":"","ansibuffer":"","curline":"",
		"curcolor":col,"curmsg":({([]),col,""})
	]);
}

//Socket accept callback bouncer, because there's no documented way to
//change the callback on a Stdio.Port(). Changing sock->_accept_callback
//does work, but since it's undocumented (and since passive mode accept
//is neither time-critical nor common), I'm sticking with the bouncer.
void sockacceptb(mapping conn) {G->G->connection->sockaccept(conn);}

//Socket accept callback - creates a new subw with the connected socket.
//Note that this has some hacks. Changes to other parts of Gypsum (eg in
//window.pike) may break it. Be careful. (Last checked 20141004.)
void sockaccept(mapping conn)
{
	while (object sock=conn->sock->accept())
	{
		mapping newconn=makeconn(G->G->window->subwindow(conn->display->tabtext+" #"+(++conn->conncount)),conn);
		newconn->sock=sock; newconn->display->connection=newconn;
		sock->set_id(newconn);
		say(conn->display,"%%% Connection from "+sock->query_address()+" at "+ctime(time()));
		sock->set_nonblocking(sockread,sockwrite,sockclosed);
	}
}

//Callback for when a connection is successfully established.
void connected(mapping conn)
{
	if (!conn->sock) return; //Connection must have failed eg in sock->connect() - sockclosed() has already happened.
	say(conn->display,"%%% Connected to "+conn->worldname+".");
	//Note: In setting the callbacks, use G->G->connection->x instead of just x, in case this is the old callback.
	conn->sock->set_nonblocking(G->G->connection->sockread,G->G->connection->sockwrite,G->G->connection->sockclosed);
	G->G->sockets[conn->sock]=1;
	ka(conn);
}

//Callback for when the connection fails.
void connfailed(mapping conn)
{
	if (!conn->sock) return; //If the user disconnects and reattempts, don't wipe stuff out unnecessarily
	say(conn->display,"%%%%%% Error connecting to %s: %s [%d]",conn->worldname,strerror(conn->sock->errno()),conn->sock->errno());
	conn->sock->close();
	sockclosed(conn);
}

/**
 * Repeater for telnet keep-alive packets.
 *
 * @param conn Current connection
 */
void ka(mapping conn)
{
	if (!conn->sock) return;
	send_telnet(conn,(string(0..255))({GA}));
	conn->ka=conn->use_ka && call_out(ka,persist["ka/delay"] || 240,conn);
}

/**
 * Establish a connection with with the provided world and link it to a display
 *
 * @param display 	The display (subwindow) to which the connection should be linked
 * @param info	  	The information about the world to which the connection should be established
 * @return mapping	Returns a mapping detailing the connection
 */
mapping connect(object display,mapping info)
{
	mapping(string:mixed) conn=makeconn(display,info);
	if (display->conn_debug) conn->debug_textread=conn->debug_ansiread=conn->debug_sockread=1;
	if ((<"0.0.0.0","::">)[info->host])
	{
		//Passive mode. (Currently hacked in by the specific IPs; may
		//later make a flag but that means people need to know about it.)
		//Note: Does not currently respect autolog. Should it? It would have to interleave all connections.
		conn->passive=1;
		if (mixed ex=catch
		{
			conn->sock=Stdio.Port((int)info->port,sockacceptb,info->host);
			conn->sock->set_id(conn);
			if (!conn->sock->errno()) {say(conn->display,"%%% Bound to "+info->host+" : "+info->port); return conn;}
			say(conn->display,"%%% Error binding to "+info->host+" : "+info->port+" - "+strerror(conn->sock->errno()));
		}) say(conn->display,"%%% "+describe_error(ex));
		sockclosed(conn);
		return conn;
	}
	say(conn->display,"%%% Connecting to "+info->host+" : "+info->port+"...");
	conn->sock=Stdio.File(); conn->sock->set_id(conn); //Refloop
	conn->sock->open_socket();
	//Disable Nagling, if possible (requires Pike branch rosuav/naglingcontrol
	//which is not in trunk 8.0) - can improve latency, not critical
	if (conn->sock->nodelay) conn->sock->nodelay();
	conn->sock->set_nonblocking(0,connected,connfailed);
	if (mixed ex=catch {conn->sock->connect(info->host,(int)info->port);})
	{
		say(conn->display,"%%% "+describe_error(ex));
		sockclosed(conn);
		return conn;
	}
	if (info->logfile && info->logfile!="")
	{
		string fn=strftime(info->logfile,localtime(time(1)));
		if (mixed ex=catch {conn->logfile=Stdio.File(fn,"wac");}) say(conn->display,"%%%% Unable to open log file %O\n%%%% %s",fn,describe_error(ex));
		else say(conn->display,"%%%% Logging to %O",fn);
	}
	return conn;
}
