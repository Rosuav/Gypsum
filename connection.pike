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
to all connection.pike code, and stash stuff directly in there? It's simple:
When a connection is reset, it's convenient and clean to completely replace the
connection mapping, thus guaranteeing that all state has been reset. Or, if you
look at it the other way around, stashing some piece of state in the connection
instead of the subw is the way to say "reset this when the connection closes".
Future policy: Ensure that everything retained is in subw[] not connection[].
Then it might be worth actually disposing of the connection mapping on close.
*/

//On first load, there won't be a global say, so any usage will bomb until
//window.pike gets loaded (trying to call the integer 0). It'll then be
//overwritten by the newly-loaded window.pike.
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
 * Naive byte-based servers, receiving UTF-8 from some clients and CP-1252 from
 * others, and emitting the exact byte-streams they receive, will "mostly work"
 * with this scheme. However, any time byte-streams from different clients get
 * combined into individual socket-read operations, there is a risk that both
 * encodings will be received simultaneously. Currently the failure case is to
 * split the line on "\n" and re-attempt decoding of each line, falling back on
 * CP-1252; this allows adjacent lines to be encoded differently, as long as
 * each line has one single encoding. This also means that occasional CP-1252
 * can potentially have a marked impact on performance.
 *
 * @param bytes Incoming 8-bit data
 * @return string Resulting Unicode text
 */
#if constant(Charset)
object cp1252=Charset.decoder("1252"); //Pike 8.0 and 8.1 have Charset at top-level; 8.1 has it nowhere else.
#else
object cp1252=Locale.Charset.decoder("1252"); //Pike 7.8 has Charset hidden behind Locale, but otherwise equivalently functional
#endif
protected string bytes_to_string(bytes data)
{
	catch {return utf8_to_string(data);}; //Normal case: Decode the whole string as UTF-8
	array(string) lines=data/"\n";
	foreach (lines;int i;string line)
		if (catch {lines[i]=utf8_to_string(line);})
			lines[i]=cp1252->feed(line)->drain(); //Failure case: Decode as CP-1252, line by line.
	return lines*"\n";
}

//Mark the current text as a prompt
//TODO: Should this become plugin-callable? Currently the only plugin that would use it
//is x.pike when it goes into "pike> " mode, and that needs to save the previous prompt,
//which brings with it all sorts of hairiness. Alternatively, should plugins get a way
//to say "shadow the prompt with this", which will override the *displayed* prompt until
//it's removed, without affecting prompt hooks etc?? That would push the complexity into
//core, which is a bad idea if only one plugin will ever use it. Leave this as a TODO
//until such time as another plugin needs the same kind of facility. Third-party reports
//welcomed on this point :)
void setprompt(mapping conn)
{
	if (G->G->window->runhooks("prompt",0,conn->display,conn->curline)) return;
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
 * @param end_of_block 1 if we're at the end of a socket-read block and might have a prompt
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
		if (conn->display->prompt==conn->curmsg) conn->display->prompt=old_prompt; //Note that this is an identity check, not an equality check. If anything disrupts this, it's not the same prompt.
		else if (!persist["prompt/retain_pseudo"]) conn->curmsg=({([]),conn->curcolor,conn->curline=""});
		//else we're retaining the pseudo-prompt as lines of text, and leaving no prompt because the user typed something, so do nothing
	}
	while (sscanf(data,"%s\n%s",string line,data))
	{
		conn->curmsg[-1]+=line;
		line=conn->curline+line;
		if (!G->G->window->runhooks("output",0,conn->display,line))
		{
			say(conn->display,conn->curmsg);
			if (conn->logfile) conn->logfile->write("%s\n",string_to_utf8(line));
		}
		conn->curmsg=({([]),conn->curcolor,conn->curline=""});
	}
	conn->curmsg[-1]+=data; conn->curline+=data;
	if (!end_of_block) return; //Check for prompts only at the end of a block of data from the socket. Note that properly-marked prompts (IAC GA) are handled in sockread(), so this is just for the ones that it can't detect.
	string prompt_suffix = persist["prompt/suffix"] || "==> "; //This may need to become conn->prompt_suffix and world-configurable. It's really a hack for Threshold RPG. Fortunately it's not TOO likely to have false positives.
	if (prompt_suffix!="" && has_suffix(conn->curline,prompt_suffix))
	{
		//Let's pretend this is a prompt. Unfortunately that's not guaranteed, but
		//since it ends with the designated prompt suffix AND it's the end of a
		//socket read, let's hope. This does produce some false positives, but it
		//also catches a lot of good prompts, on servers which don't mark them.
		setprompt(conn);
	}
	else if (conn->curline!="") switch (mixed pseudo=persist["prompt/pseudo"] || ":>")
	{
		case "": break; //No pseudo-prompt handling.
		default: //Only if the prompt ends with one of the specified characters (and maybe whitespace).
			string prompt=String.trim_all_whites(conn->curline);
			if (prompt=="" || !has_value(pseudo,prompt[-1])) break; //Not one of those characters. Not a pseudo-prompt.
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
		textread(conn,data,0); conn->ansibuffer="\x1b"+ansi;
		if (ansi[0]!='[') {textread(conn,"\\e",0); conn->ansibuffer=ansi; continue;} //Report an escape character as the literal string "\e" if it doesn't start an ANSI code
		array(int|string) params=({ }); int|string curparam=UNDEFINED;
		colorloop: for (int i=1;i<sizeof(ansi)+1;++i) switch (ansi[i]) //Deliberately go past where we can index - if we don't have the whole ANSI sequence, leave the unprocessed text and wait for more data from the socket.
		{
			case '0'..'9': curparam=curparam*10+ansi[i]-'0'; break;
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
						default: if (!conn["unknown_ansi_"+param+"m"]) {conn["unknown_ansi_"+param+"m"]=1; say(conn->display,"%%%% %O produced unknown ANSI code \\e[%dm\n",conn->worldname,param);}
					}
					conn->curmsg[-1]=conn->curmsg[-1];
					conn->curmsg+=({conn->curcolor=G->G->window->mkcolor(conn->fg+conn->bold,conn->bg),""});
					break;
					default: break; //Ignore unknowns without error
				}
				ansi=ansi[i+1..];
				break colorloop;
			}
			default: say(conn->display,"Unparseable ANSI sequence: %O\n",ansi[..i]); return;
		}
		conn->ansibuffer=ansi;
	}) {/*werror("ERROR in ansiread: %s\n",describe_backtrace(ex));*/ return;} //This will catch IndexError-ish from the deliberate over-indexing, if we don't have enough data yet.
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
					//case SUPPRESSGA: if (iac[0]==WONT) send_telnet(conn,(string(0..255))({DO,SUPPRESSGA})); break; //Possibly acknowledge WONT SUPPRESSGA?
					case NAWS: if (iac[0]==DO)
					{
						//Note that we don't re-send when wrap width changes. But we don't NAWS very strongly anyway, so
						//it's unlikely to be that great a concern. Wrap is a poor substitute for window size, really.
						int width=persist["window/wrap"] || 80; //If we're not wrapping, pretend screen width is 80, although that's a bit arbitrary
						send_telnet(conn,(string(0..255))({SB,NAWS,width>>8,width&255,0,0}));
					}
					break;
					case TERMTYPE: if (iac[0]==DO) send_telnet(conn,(string(0..255))({WILL,TERMTYPE})); break;
					default: break; //Should we explicitly reject (respond negatively to) unrecognized DO/WILL requests? Currently Gypsum doesn't seem to play nicely with some non-MUD servers (eg Debian telnetd).
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
				if (!subneg) return; //We don't have the complete subnegotiation. Wait till we do.
				subneg=replace(subneg,"\xFF\xFF","\xFF"); //Un-double IACs
				switch (subneg[1])
				{
					case TERMTYPE:
						//Note that this is slightly abusive of the "terminal type" concept - it's more like a user-agent string.
						//But it was already a bit stretched as soon as specific clients got mentioned - and everybody does that.
						//TODO: Track repeated requests and send fallbacks [cf RFC 1091].
						if (subneg[2]==SEND) send_telnet(conn,
							(string(0..255))({SB,TERMTYPE,IS})
							+[string(0..127)]sprintf("Gypsum %s (Pike %s)",gypsum_version(),pike_version())
						);
						break;
					default: break;
				}
				break;
			}
			case SE: break; //Shouldn't happen - it'll normally be consumed by IAC SB handling. An unmatched IAC SE is a server-side problem.
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

//Clean up the socket connection; it's assumed to have already been closed.
int sockclosed(mapping conn)
{
	values(G->G->tabstatuses)->connected(conn->display,0); //Note that subw->world is not currently cleared, but if it ever is, it must be AFTER this call.
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
 * @return 1 if the text was successfully queued for sending.
 */
int send(mapping conn,string text)
{
	if (!conn) return 0;
	if (conn->lines && !(conn=conn->connection)) return 0; //Allow sending to a subw (ignoring if it's not connected)
	if (conn->passive) return 0; //Ignore sent text on passive masters - or should the text be sent to _all_ connected clients? Could be convenient.
	if (text) conn->writeme+=string_to_utf8(text);
	sockwrite(conn);
	return 1;
}

//Send a TELNET sequence to the socket.
//The passed string should begin just after the IAC, so (string(0..255))({GA}) will send IAC GA.
//Subnegotiations will be automatically terminated; (string(0..255))({SB,.....}) will have IAC SE appended.
//IAC doubling is performed automatically. This is identical to the Hogan specification, fwiw.
void send_telnet(mapping conn,bytes data)
{
	data="\xFF"+replace(data,"\xFF","\xFF\xFF");
	if (data[1]==SB) data+=(string(0..255))({IAC,SE});
	conn->writeme+=data;
	sockwrite(conn);
}

//If a connection were an object (rather than a mapping), this would be create().
//But you don't ever call this directly; it's used internally.
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

//Callback for when a connection is successfully established. Not replaced in existing sockets when connection.pike is updated.
//Seems to be being called even when a connection fails. Pike bug? Investigate on multiple Pikes. Seems consistent on 8.1 on Linux, at least. Also seen on 8.0.97 on Linux.
//And sock->errno() is still zero, too, so we don't get a clue that way.
void connected(mapping conn)
{
	if (!conn->sock) return; //Connection must have failed eg in sock->connect() - sockclosed() has already happened. Shouldn't normally happen, I think, but let's be safe.
	if (!conn->sock->is_open() || !conn->sock->query_address()) {connfailed(conn); return;} //It actually failed to connect, despite coming through to this callback.
	say(conn->display,"%%% Connected to "+conn->worldname+".");
	//Note: In setting the callbacks, use G->G->connection->x instead of just x, in case this is the old callback.
	conn->sock->set_nonblocking(G->G->connection->sockread,G->G->connection->sockwrite,G->G->connection->sockclosed);
	G->G->sockets[conn->sock]=1;
	ka(conn);
}

//Callback for when the connection fails. Oddly, this appears not to be happening - it's coming through to connected() instead. Investigate.
//Despite the trap inside connected(), we're still worse off to the value of errno - so we have no idea _why_ the connection failed.
void connfailed(mapping conn)
{
	if (!conn->sock) return; //If the user disconnects and reattempts, this callback will eventually happen, pointing to an old conn mapping. Ignore it.
	say(conn->display,"%%%%%% Error connecting to %s: %s [%d]",conn->worldname,strerror(conn->sock->errno()),conn->sock->errno());
	conn->sock->close();
	sockclosed(conn);
}

//Periodic call_out for keep-alive - invoked separately for each connection
void ka(mapping conn)
{
	if (!conn->sock) return;
	send_telnet(conn,(string(0..255))({GA})); //(note, cannot use the typedef 'bytes' here due to a Pike parser limitation)
	conn->ka=conn->use_ka && call_out(ka,persist["ka/delay"] || 240,conn);
}

void dnsresponse(string domain,mapping resp,mapping conn,mapping info)
{
	if (!conn->dnspending) return; //Already got a positive response. (If we fire A and AAAA requests, and the first one to respond has an answer, we ignore the second.)
	array responses = (resp->an->a + resp->an->aaaa) - ({0});
	if (string ip = sizeof(responses) && responses[0])
	{
		conn->dnspending=0;
		complete_connection(ip, conn, info);
		return;
	}
	if (!--conn->dnspending) say(conn->display,"%%% Unable to resolve host.");
}

//Establish a connection - the sole constructor for conn mappings.
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
			//The socket accept callback is a bouncer - there's no documented way to
			//change the callback on a Stdio.Port(). Changing sock->_accept_callback
			//does work, but since it's undocumented (and since passive mode accept
			//is neither time-critical nor common), I'm sticking with the bouncer.
			conn->sock=Stdio.Port((int)info->port,bouncer("connection","sockaccept"),info->host);
			conn->sock->set_id(conn);
			if (!conn->sock->errno()) {say(conn->display,"%%% Bound to "+info->host+" : "+info->port); return conn;}
			say(conn->display,"%%% Error binding to "+info->host+" : "+info->port+" - "+strerror(conn->sock->errno()));
		}) say(conn->display,"%%% "+describe_error(ex));
		sockclosed(conn);
		return conn;
	}
	if (info->logfile && info->logfile!="")
	{
		string fn=strftime(info->logfile,localtime(time(1)));
		if (mixed ex=catch {conn->logfile=Stdio.File(fn,"wac");}) say(conn->display,"%%%% Unable to open log file %O\n%%%% %s",fn,describe_error(ex));
		else say(conn->display,"%%%% Logging to %O",fn);
	}
	string prot=persist["connection/protocol"];
	if (prot=="*" || sscanf(info->host,"%d.%d.%d.%d",int q,int w,int e,int r)==4 || Protocols.IPv6.parse_addr(info->host))
	{
		complete_connection(info->host, conn, info);
		return conn;
	}
	//Otherwise, resolve DNS asynchronously and then connect.
	//Ideally, a /dc should wipe the conn mapping altogether, but since that
	//isn't currently happening, the code (see window.pike) explicitly checks
	//for and cancels any pending DNS lookups.
	say(conn->display,"%%% Resolving "+info->host+"...");
	object cli=Protocols.DNS.async_client();
	conn->dnspending=0;
	if (prot!="6") {++conn->dnspending; cli->do_query(info->host,Protocols.DNS.C_IN,Protocols.DNS.T_A,   dnsresponse,conn,info);}
	if (prot!="4") {++conn->dnspending; cli->do_query(info->host,Protocols.DNS.C_IN,Protocols.DNS.T_AAAA,dnsresponse,conn,info);}
	return conn;
}

//Follow on from connect(), either immediately or after a DNS lookup
//Normally 'ip' will be, as the name suggests, an IP address; but if connection/protocol is "*", it can be a name.
void complete_connection(string ip, mapping conn, mapping info)
{
	say(conn->display,"%%% Connecting to "+ip+" : "+info->port+"...");
	conn->sock=Stdio.File(); conn->sock->set_id(conn); //Refloop
	conn->sock->open_socket();
	//Disable Nagling, if possible (requires Pike branch rosuav/naglingcontrol
	//which is not in trunk 8.0) - can improve latency, not critical
	if (conn->sock->nodelay) conn->sock->nodelay();
	//Request minimum latency, if possible (requires Pike branch rosuav/sockopt
	//which is not in trunk 8.0 or 8.1) - might improve latency if the uplink
	//is saturated
	#if constant(Stdio.IPTOS_LOWDELAY)
	conn->sock->setsockopt(Stdio.IPPROTO_IP,Stdio.IP_TOS,Stdio.IPTOS_LOWDELAY|Stdio.IPTOS_RELIABILITY);
	#endif
	conn->sock->set_nonblocking(0,connected,connfailed);
	if (mixed ex=catch {conn->sock->connect(ip,(int)info->port);}) //Should now be fast - DNS lookups should happen elsewhere.
	{
		say(conn->display,"%%% "+describe_error(ex));
		sockclosed(conn);
	}
}

void create(string name)
{
	G->G->connection=this;
	if (G->G->sockets) indices(G->G->sockets)->set_callbacks(sockread,sockwrite,sockclosed);
	else G->G->sockets=(<>);
	add_gypsum_constant("send",send); //Note that due to a Pike bug, having this reference higher in the file than the function definition will cause an undesirable self-retrieval from globals.
}
