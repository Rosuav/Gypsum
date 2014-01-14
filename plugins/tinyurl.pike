/*
Monitor OOC channels for a long URL, and pass it direct to TinyUrl.com

Thanks Thierran for helping me test the original RosMud version, of which this is a port.
*/

inherit hook;
inherit plugin_menu;

/* persist["tinyurl/*"] contains the following:
proxy_host/proxy_port - if 0, goes direct to Tiny, else goes via the specified HTTP proxy
maxlen=64 - maximum length of a URL that gets passed through unchanged
announce=0 - if 1, will announce incoming URLs with an explanatory line (was "quietmode=1")
defaultaction="b" - default to (b)rowse or (c)opy

G->G->lasturl=0 - last-received URL, index into recvurl[] (not saved across shutdown, no point)
*/

//Options: Retain URL array across reloads of the plugin, or across shutdown? If using persist[], also uncomment the assignment inside outputhook().
//Note that this isn't actually working (since array append overwrites, and nothing ever sets it in G->G-> anyway), so it doesn't retain at all.
array(string) recvurl=G->G->tinyurl_recvurl || ({ });
//array(string) recvurl=persist["tinyurl/recvurl"];

Regexp.PCRE.StudiedWidestring longurl; //Cached regexp object. I'm not 100% happy with this, but am toying with using a regex rather than manually coding it. NOTE: Clear this any time maxlen changes.
int maxlen=persist["tinyurl/maxlen"]||63;

int outputhook(string line,mapping(string:mixed) conn)
{
	string url; int https;
	if (sscanf(line,"%*shttp://%[^ ]",url)<2 && (https=sscanf(line,"%*shttps://%[^ ]",url))<2) return 0;
	if (https) url="https://"+url; else url="http://"+url;
	int i=search(recvurl,url);
	if (i==-1) {i=sizeof(recvurl+=({url}))-1; /* persist["tinyurl/recvurl"]=recvurl; */ }
	G->G->lasturl=i+1; //Which means that if a duplicate URL is received, it'll still become the one accessed by "url" on its own.
	if (persist["tinyurl/announce"]) say(conn->display,"%%%% URL saved - type 'url %d' to browse ('url help' for help)",i+1);
}

int inputhook(string line,mapping(string:mixed) subw)
{
	if (line=="url" || sscanf(line,"url %s",string param))
	{
		if (param=="list")
		{
			say(subw,"%% URLs received this session:");
			int lasturl=G->G->lasturl;
			foreach (recvurl;int i;string url) say(subw,"%%%% %d: %s%s",i+1,url,(i+1==lasturl)?" <== latest":"");
			say(subw,"%%%% Total URLs saved: %d",sizeof(recvurl));
			return 1;
		}
		int i;
		if (!param) i=G->G->lasturl; else sscanf(param,"%d %s",i,param);
		if (!param || param=="") param=persist["tinyurl/defaultaction"]||"b";
		if (param[0]=='h')
		{
			say(subw,"%% Monitored URLs are given sequential numbers starting from 1.");
			say(subw,"%% Type 'url 42 (action)' to use a URL. Only the first letter is significant:");
			say(subw,"%%   >> 'url 42 b(rowse)' to invoke your default browser.");
			say(subw,"%%   >> 'url 42 c(opy)' to copy the URL to the clipboard.");
			say(subw,"%%   >> 'url 42 r(ender)' to render a redirection URL (works with TinyURLs and some others).");
			if (persist["tinyurl/defaultaction"]=="c") say(subw,"%% Omit the action ('url 42') to execute the default action, currently to put it on the clipboard.");
			else say(subw,"%% Omit the action ('url 42') to execute the default action, currently to invoke your browser.");
			say(subw,"%% Omit the index ('url c/b/r' or just 'url') to use the most recently received URL.");
			say(subw,"%% Type 'url list' to generate a full list of this session's URLs.");
			return 1;
		}
		if (i<=0)
		{
			i=G->G->lasturl;
			if (!i) {say(subw,"%% No URLs received this session."); return 1;}
		}
		--i; //We're 0-based, the user is 1-based :)
		if (i>=sizeof(recvurl))
		{
			say(subw,"%% URL index invalid - we haven't received that many URLs this session.");
			say(subw,"%% Type 'url list' to get a full list.");
			return 1;
		}
		string url=recvurl[i];
		switch (lower_case(param[0]))
		{
			case 'c': case 'C':
			{
				subw->display->get_clipboard(GTK2.Gdk_Atom("CLIPBOARD"))->set_text(url,sizeof(url));
				say(subw,"%% Copied to clipboard.");
				break;
			}
			case 'b': case 'B':
			{
				if (invoke_browser(url)) say(subw,"%% Browser invoked.");
				else say(subw,"%% Unable to invoke browser on this platform - try the clipboard instead.");
				break;
			}
			case 'r': case 'R':
			{
				say(subw,"%% Rendering URL...");
				//TODO: Proxy
				Protocols.HTTP.do_async_method("GET",url,0,0,Protocols.HTTP.Query()->set_callbacks(lambda(Protocols.HTTP.Query q)
				{
					if (q->status<300 || q->status>=400 || !q->headers->location) say(subw,"%% Cannot render URL - server returned a non-redirection response");
					else say(subw,"%%%% Rendered URL %s: actual location is %s",url,q->headers->location);
				},lambda()
				{
					say(subw,"%% Unable to render URL - HTTP query failed"); //TODO: Give more info
				}));
				break;
			}
			default:
			{
				say(subw,"%% Unknown URL action - 'url help' for help");
				break;
			}
		}
		return 1;
	}
	if (has_prefix(line,"/tiny ") && sizeof(line)<maxlen+5) outputhook(line,(["display":subw])); //NOTE: Don't use subw->conn for the last arg; if there's no connection, it should still be safe to use /tiny.
	if (!longurl) longurl=Regexp.PCRE.StudiedWidestring("^(.*?)http(s?)://([^ ]{"+(maxlen-7)+",})(.*)$"); //Find a URL, space-terminated, that's more than maxlen characters long. Note that HTTPS consumes one character more than allowed for.
	array parts=longurl->split(line);
	if (!parts) return 0; //No match? Nothing needing tinification.
	object dlg=GTK2.MessageDialog(0,GTK2.MESSAGE_QUESTION,GTK2.BUTTONS_NONE,"You're posting a long URL - shorten it?");
	dlg->signal_connect("response",tinify,parts+({subw}));
	dlg->add_button(GTK2.STOCK_YES,GTK2.RESPONSE_YES);
	dlg->add_button(GTK2.STOCK_NO,GTK2.RESPONSE_NO);
	dlg->add_button(GTK2.STOCK_CANCEL,GTK2.RESPONSE_CANCEL);
	dlg->show();
	return 1; //Suppress the line (for now)
}

/**
 * Takes a url and processes it through tinyurl, then saves and displays the tiny url.
 *
 * @param self		The dialog window
 * @param response	The user's response to whether the url should be converted
 * @param args		Input components and current subwindow
 */
void tinify(object self,int response,array args)
{
	[string before,string protocol,string url,string after,mapping(string:mixed) subw]=args;
	self->destroy();
	if (response==GTK2.RESPONSE_CANCEL) return; //Suppress the line completely.
	if (response!=GTK2.RESPONSE_YES) //Clicking No, or closing the dialog, will transmit the line as-is.
	{
		nexthook(subw,sprintf("%shttp%s://%s%s",before,protocol,url,after));
		return;
	}
	//Tinify it!
	array(string|int) lineparts=({ });
	while (1) //Look for multiple URLs (and shorten them all - one prompt is enough).
	{
		lineparts+=({before});
		url=sprintf("http%s://%s",protocol,url);
		say(subw,"%% Shortening URL:");
		say(subw,url);
		//CJA 20110302: Attempt some other forms of shortening first. (Ported to Pike with the original date-of-implementation.)
		//   http://www.thinkgeek.com/gadgets/watches/e6be/  -->  http://www.thinkgeek.com/e6be
		//   http://notalwaysright.com/not-the-only-thing-in-need-of-maintenance/8820 --> http://notalwaysright.com/not-the-only-thing-in-need-of-maint/8820
		//   http://www.youtube.com/watch?v=RwBA_tNaItg&feature=related --> http://www.youtube.com/watch?v=RwBA_tNaItg
		if (has_prefix(url,"http://www.thinkgeek.com/"))
		{
			//Take the tail end (the hex ID) and discard the rest.
			url="http://www.thinkgeek.com/"+((url/"?")[0]/"/"-({""}))[-1]; //Pick the last non-empty path component, ignoring any querystring
		}
		else if (has_prefix(url,"http://notalwaysright.com/") || has_prefix(url,"http://notalwaysrelated.com/") || has_prefix(url,"http://notalwaysromantic.com/") || has_prefix(url,"http://notalwaysworking.com/") || has_prefix(url,"http://notalwayslearning.com/"))
		{
			//Trim the middle section by taking the last path component (which should be the numeric part) and taking the first part and that, up to maxlen characters.
			sscanf(url,"%s?%*s",url); //Dispose of any querystring, eg RSS feed source info
			string tail=(url/"/")[-1];
			if (sizeof(tail)<maxlen-30) url=url[..maxlen-sizeof(tail)-2]+"/"+tail;
		}
		else if (has_prefix(url,"http://www.youtube.com/watch?v="))
		{
			//Cut it down to just "v=" and no parameters
			url=(url/"&")[0]; //Simple! Cheats a bit, but seems to work - v= is always the first part of the URL.
		}
		if (sizeof(url)<=maxlen) lineparts+=({url}); //We've managed a "simple shortening"!
		else
		{
			lineparts+=({0}); //Add a spot for the shorter URL.
			Protocols.HTTP.do_async_method("GET","http://tinyurl.com/create.php",(["url":url]),0,
				Protocols.HTTP.Query()->set_callbacks(lambda(object query,int pos) {query->async_fetch(lambda()
				{
					sscanf(query->unicode_data(),"%*shttp://preview.%s<",string url);
					//We have a response!
					lineparts[pos]="http://"+url;
					if (!has_value(lineparts,0)) nexthook(subw,lineparts*"");
				});},lambda(object query)
				{
					say(subw,"%%%% Error connecting to %s: %s (%d)",/*proxy_host?"proxy":*/"TinyURL",strerror(query->errno),query->errno);
				},sizeof(lineparts)-1)
			);
		}
		array parts=longurl->split(after);
		if (!parts) {lineparts+=({after}); break;} //No more long URLs to shorten.
		[before,protocol,url,after]=parts;
	}
	if (!has_value(lineparts,0)) nexthook(subw,lineparts*"");
}

constant menu_label="TinyURL";
class menu_clicked
{
	inherit window;
	void create() {::create();} //No args passed on
	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Configure URL shortener","transient-for":G->G->window->mainwindow]))
			->add(GTK2.Vbox(0,10)
				->add(GTK2.Frame("Proxy server")->set_sensitive(0)->add(GTK2.Hbox(0,10) //TODO: Proxy
					->add(win->proxy_use=GTK2.CheckButton("Use"))
					->add(GTK2.Label("Address:"))->add(win->proxy_addr=GTK2.Entry()->set_text(persist["tinyurl/proxy_host"]||""))
					->add(GTK2.Label("Port:"))->add(win->proxy_port=GTK2.Entry()->set_text(persist["tinyurl/proxy_port"]||""))
				))
				->add(win->announce=GTK2.CheckButton("Announce incoming URLs with an explanatory note"))
				->add(GTK2.Frame("Default action")->add(GTK2.Hbox(0,10)
					->add(win->default_browse=GTK2.RadioButton("Browse"))
					->add(win->default_copy=GTK2.RadioButton("Copy to clipboard",win->default_browse))
				))
				->pack_end(win->pb_close=GTK2.Button((["label":"_Close","use-underline":1])),0,0,0)
			);
		::makewindow();
	}

	void pb_close_click() {win->mainwindow->destroy();}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_close,"clicked",pb_close_click),
		});
	}
}

void create(string name) {::create(name);}
