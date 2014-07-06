/* Attempt to import settings from RosMud's .ini files

Note that this will work across platforms. Mount your RM directory from a
remote system, or archive it and copy it across, or whatever you like.

Note also that the set of importables may expand. This is why it's kept
carefully configurable; it'll never import more stuff than you tell it to.
Window positions will never be imported, though - due to structural
differences between RM and Gypsum, plus platform differences, screen size
issues, etc, etc, etc, it's not worth hoping that the numbers have the
same meaning on both. So we just let the human deal with that. Same with
things like font. Sorry, folks. Not really a lot to do about that.

In an inversion of the usual rules, this plugin is allowed to "reach in"
to any other plugin's memory space. Otherwise, all other plugins would be
forced to go to extra effort somewhere (the simplest would be to demand
that they place an empty mapping back into persist[], but there may be
other considerations too), which is backwards. It's the importer that has
the complexity, not everything else. Of course, this may mean that changes
to other plugins might precipitate changes here, which is a cost, but even
if that's missed somewhere, it means only that the importer is broken.
*/
inherit plugin_menu;

constant plugin_active_by_default = 1;

constant menu_label="Import RosMud settings";
class menu_clicked
{
	inherit window;

	void create() {::create("rmimport");}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Import settings from RosMud","transient-for":G->G->window->mainwindow]))->add(GTK2.Vbox(0,0)
			->add(win->notebook=GTK2.Notebook()->append_page(GTK2.Vbox(0,0)
				->pack_start(GTK2.Label("First step: Choose a directory to import settings from."),0,0,0)
				->pack_start(GTK2.Frame("Import directory")->add(GTK2.Hbox(0,0)
					->pack_start(win->pb_find=GTK2.Button("Open"),0,0,0)
					->add(win->import_dir=GTK2.Label(""))
				),0,0,0)
				->add(win->status=GTK2.Label("")) //Expansion can happen here.
				->pack_start(GTK2.Frame("Global control")->add(GTK2.HbuttonBox()
					->add(win->pb_selectall=GTK2.Button("Select all"))
					->add(win->pb_selectnone=GTK2.Button("Select none"))
				),0,0,0)
			,GTK2.Label("Start")))
			->pack_start(GTK2.HbuttonBox()
				->add(win->pb_import=GTK2.Button("Import!"))
				->add(stock_close())
			,0,0,0)
		);
		win->checkboxes=([]);
		::makewindow();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_selectall,"clicked",pb_select_click,1), //Same handler for these, just an arg
			gtksignal(win->pb_selectnone,"clicked",pb_select_click,0),
			win->filedlg && gtksignal(win->filedlg,"response",filedlg_response),
		});
	}

	void sig_pb_import_clicked()
	{
		multiset(function) funcs=(<>);
		foreach (win->checkboxes;GTK2.CheckButton cb;[array(string) path,mixed value,function callme]) if (cb->get_active())
		{
			mixed cur=persist;
			foreach (path[..<1],string part)
			{
				mixed next=cur[part];
				if (!next) cur[part]=next=([]);
				cur=next;
			}
			cur[path[-1]]=value;
			persist->save();
			funcs[callme]=1;
		}
		indices(funcs)(); //Call all the associated call-me functions (once each, even if specified multiple times)
		win->mainwindow->destroy();
	}

	void sig_pb_find_clicked()
	{
		win->filedlg=GTK2.FileChooserDialog("Locate RosMud directory to import from",win->mainwindow,
			GTK2.FILE_CHOOSER_ACTION_SELECT_FOLDER,({(["text":"Import","id":GTK2.RESPONSE_OK]),(["text":"Cancel","id":GTK2.RESPONSE_CANCEL])})
		)->show_all();
		win->filedlg->set_filename("."); //This doesn't chain. What's the integer it returns? Meh.
		dosignals();
	}

	void pb_select_click(object self,int state)
	{
		indices(win->checkboxes)->set_active(state);
	}

	void filedlg_response(object self,int response)
	{
		if (response==GTK2.RESPONSE_OK)
		{
			win->import_dir->set_text(win->dir=self->get_filename());
			for (int i=win->notebook->get_n_pages()-1;i>1;--i) win->notebook->remove_page(i);
			foreach (sort(indices(this)),string func) if (sscanf(func,"import_%s",string inifile) && inifile)
			{
				string data=Stdio.read_file(sprintf("%s/%s.ini",win->dir,inifile)); //TODO: Detect files case insensitively, even on a case sensitive file system
				if (!data || data=="") continue;
				data-="\r";
				this[func](data);
			}
		}
		m_delete(win,"filedlg")->destroy();
		dosignals();
	}

	GTK2.CheckButton cb(string label,array(string) path,mixed value,function|void callme)
	{
		GTK2.CheckButton ret=GTK2.CheckButton(label);
		win->checkboxes[ret]=({path,value,callme});
		return ret;
	}

	// ---- Importers ---- //

	void import_Alias(string data)
	{
		if (!persist["aliases/simple"]) persist["aliases/simple"]=function_object(G->G->commands->alias)->aliases||([]);
		GTK2.Vbox box=GTK2.Vbox(0,0)->pack_start(GTK2.Label("Import aliases:"),0,0,0);
		foreach (data/"\n",string line) if (sscanf(line,"/alias %s %s",string kw,string expan) && expan)
			box->pack_start(cb(kw+" -> "+expan,({"aliases/simple",kw,"expansion"}),expan),0,0,0);
		win->notebook->append_page(box->show_all(),GTK2.Label("Aliases"));
	}

	void import_Timer(string data)
	{
		object timer=function_object(G->G->commands->timer);
		if (!persist["timer/timers"]) persist["timer/timers"]=timer->timers||([]);
		sscanf(data,"%*d %*d %d %d %d%*s\n%s",int hpregen,int spregen,int epregen,data);
		GTK2.Vbox box=GTK2.Vbox(0,0)->pack_start(GTK2.Label("Import timers:"),0,0,0);
		function format_time=timer->format_time,makelabels=timer->makelabels;
		function maketimer=lambda(string kw,int interval,string trigger)
		{
			box->pack_start(cb(
				kw+" - "+format_time(interval,interval),
				({"timer/timers",kw}),(["time":interval,"trigger":trigger]),
				makelabels,
			),0,0,0);
		};
		if (hpregen) maketimer(" HP",hpregen,"");
		if (spregen) maketimer(" SP",spregen,"");
		if (epregen) maketimer(".EP",epregen,"");
		foreach (data/"\n",string line) if (sscanf(line,"|%s|%d|%s",string kw,int interval,string trigger) && trigger)
			maketimer(kw,interval,trigger);
		win->notebook->append_page(box->show_all(),GTK2.Label("Timers"));
	}

	void import_Rosmud(string data) //Oddly named, but it reads general settings from Rosmud.ini
	{
		if (!persist["color/channels"]) persist["color/channels"]=G->G->window->channels||([]);
		GTK2.Vbox box=GTK2.Vbox(0,0)->pack_start(GTK2.Label("Import general settings:"),0,0,0);
		GTK2.Vbox channels;
		int ignore_numpad; //If set to 1 because numpadnav is disabled, will prevent the importing of numpad nav
		foreach (data/"\n",string line) if (sscanf(line,"%s: %s",string type,string args) && args) switch (type)
		{
			case "Font": break; //No point trying to import font config, Win32 vs GTK (esp Windows vs Linux) will likely have different fonts available anyway
			case "Color":
			{
				//Note that, for reasons which presently escape me (something to do with 0 being a problem?), the
				//colors are in reverse order, starting with bold white and going down to black as the last entry.
				sscanf(args,"%d %d%{ %d%}",int FGCol,int BGCol,array(array(int)) colors);
				//FGCol, BGCol not supported (currently Gypsum doesn't allow those to be configured)
				//TODO: Import colors into persist["colors/sixteen"], but don't import them if they're the defaults
				break;
			}
			case "Sound": break; //Maybe want to import this later. Can't be bothered for now.
			case "Window":
			{
				//Copied straight from rosmud.cpp with barely any change, woot!
				sscanf(args,"%d %d %d %d %d %d %d %[^\xFE\n]\xFE%d",int wrapwidth,int wrapindent,int wraptochar,int promptonclose,int activityflash,int idletimeout,int inputlines,string htf,int hovertimesz);
				box->pack_start(cb("Wrap width: "+wrapwidth,({"window/wrap"}),wrapwidth),0,0,0);
				box->pack_start(cb("Wrap indent: "+wrapindent+" spaces",({"window/wrapindent"})," "*wrapindent),0,0,0);
				box->pack_start(cb("Wrap to: "+({"words","chars"})[wraptochar],({"window/wraptochar"}),wraptochar),0,0,0);
				//promptonclose: 0 = never, 1 = if activity, 2 = always. confirmclose: -1 = never, 0 = default (ie if activity), 1 = always.
				box->pack_start(cb("Confirm on close: "+promptonclose,({"window/confirmclose"}),promptonclose-1),0,0,0);
				box->pack_start(cb("Activity alert: "+activityflash,({"notif/activity"}),activityflash),0,0,0);
				int ka=idletimeout*60-10; //RosMud records an idle timeout in minutes, and backs off by 10 seconds (so "4" means it sends a KA every four minutes minus a bit).
				box->pack_start(cb(sprintf("Keep-alive: %ds (approx %d minute(s))",ka,idletimeout),({"ka/delay"}),ka),0,0,0);
				//inputlines not supported (Gypsum always uses a one-line EF; multi-line input is better served by the pop-out editor)
				box->pack_start(cb("Hover time format: "+htf,({"window/timestamp"}),htf),0,0,0);
				//hovertimesz is the size in pixels of htf - unnecessary, let GTK work that out
				break;
			}
			case "Display":
			{
				//Again, copied straight in, just changing the ampersands into 'int' declarations and declaring the string :)
				sscanf(args,"%d %d %d %d %d %d %d \xFE%[^\n]",int AnsiCol,int LocalEcho,int showtoolbar,int showstatusbar,int boxsel,int inputcol,int wipepseudo,string promptchars);
				//AnsiCol not applicable (Gypsum's monochrome mode is transient)
				//showtoolbar, showstatusbar not supported - Gypsum never has the former and always has the latter, and there's no real reason to do otherwise
				//boxsel not supported (Gypsum always defaults to stream, use Shift-drag for box)
				//inputcol not supported (Gypsum always colors the input box appropriately)
				//RosMud has "wipepseudo" but Gypsum has "retain_pseudo". Same functionality, different name, negated condition.
				box->pack_start(cb("Retain pseudo-prompts: "+({"Yes","No"})[wipepseudo],({"prompt/retain_pseudo"}),!wipepseudo),0,0,0);
				box->pack_start(cb(sprintf("Pseudo-prompt markers: %O",promptchars),({"prompt/pseudo"}),promptchars),0,0,0);
				//RosMud has "local echo" but Gypsum has "hide input". As above, negated condition.
				box->pack_start(cb("Hide input: "+({"Yes","No"})[LocalEcho],({"window/hideinput"}),!LocalEcho),0,0,0);
				break;
			}
			case "Keys":
			{
				//As above, straight from rosmud.cpp
				sscanf(args,"%d %d %d %d %d %d %d",int hotkey_use,int hotkey_hide,int hotkey_show,int numpadnav,int cursoratend,int downarr,int cpgup);
				//hotkey_* not supported
				//numpadnav as a single flag doesn't exist; it's a feature that's always active and
				//will have specific keys assigned or not assigned. But hold onto the flag; if it's
				//zero, ignore the Numpad line (which, in a normal Rosmud.ini file, will come after
				//this one).
				if (!numpadnav) ignore_numpad=1;
				//cursoratend not supported (Gypsum always puts it at the end if you don't use Ctrl-Up/Dn)
				box->pack_start(cb("Down arrow on no history: "+({"Lock","Clear","Save & clear"})[downarr],({"window/downarr"}),downarr),0,0,0);
				//cpgup not supported (Gypsum always pauses, which is the sanest mode anyway)
				break;
			}
			case "MRU": break; //Ignore window positions. Also, Gypsum doesn't have a single "last used world" marker.
			case "Numpad":
			{
				if (ignore_numpad) break; //Numpad Nav is disabled in the Keys section, so don't offer any to import
				GTK2.Vbox box=GTK2.Vbox(0,0)->pack_start(GTK2.Label("Import numpad nav:"),0,0,0);
				foreach (args/"\xFE";int i;string cmd) if (cmd!="" && cmd!=" ")
				{
					string key;
					if (i<10) key="ffb"+i; else key="ffa"+(i-10); //Windows's VK_ constants and GDK keysyms put these in a different order, but still in blocks.
					box->pack_start(cb(sprintf("Key %s [%c]: %O",key,"0123456789*+ -./"[i],cmd),({"window/numpadnav",key,"cmd"}),cmd),0,0,0);
				}
				win->notebook->append_page(box->show_all(),GTK2.Label("Numpad"));
				break;
			}
			case "Hilight":
			{
				//Note that Gypsum and RosMud have subtly different behaviour. RosMud insists there
				//be a space following the word, but Gypsum simply looks at the first blank-delimited
				//word on the line. The functionality is effectively identical, though.
				if (!channels) channels=GTK2.Vbox(0,0)->pack_start(GTK2.Label("Import channel colors:"),0,0,0);
				sscanf(args,"%d %[^ ]",int col,string word);
				int r=col&255,g=(col>>8)&255,b=(col>>16)&255;
				channels->pack_start(cb(sprintf("Channel %O: (%d,%d,%d)",word,r,g,b),({"color/channels",word}),(["r":r,"g":g,"b":b])),0,0,0);
				break;
			}
			case "Logging": break; //Gypsum does logging per-world rather than globally.
			default: win->status->set_text(win->status->get_text()+"** Unexpected keyword in Rosmud.ini: "+type+" **\n"); break; //Shouldn't happen unless the ini file is corrupted
		}
		if (channels) win->notebook->append_page(channels->show_all(),GTK2.Label("Channels"));
		win->notebook->append_page(box->show_all(),GTK2.Label("General"));
	}
}
