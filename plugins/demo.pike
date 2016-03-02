inherit command;
inherit hook;
inherit movablewindow; //Replace this with window if you don't care about window position saving
inherit statusevent; //Replace with statustext if you don't need the EventBox
inherit plugin_menu;
//inherit tabstatus; //Not yet supported and thus not yet in the demo

//Uncomment this to have the plugin auto-activated on discovery.
//This should generally be reserved for core plugins, as it may be surprising
//to an end user.
//constant plugin_active_by_default = 1;

constant docstring=#"
Demo plugin inheriting everything and announcing as much as possible.

This is not intended to be used as it is, but referred to by plugin
developers. It forms 'executable documentation'.
";

constant config_persist_key="plugins/demo";
constant config_description="Demo config value";

// ----------------- inherit command ----------------- //

int process(string param,mapping(string:mixed) subw)
{
	say(subw, "%% This is invoked as '/demo'.");
	say(subw, "%% Normally this should return 1. There are very few reasons");
	say(subw, "%% for a slash command to return 0, but for consistency, the");
	say(subw, "%% protocol is the same as for hooks etc.");
	if (persist[config_persist_key]) say(subw, "%% My config value is: "+persist[config_persist_key]);
	return 1;
}

// ----------------- inherit hook ----------------- //

int input(mapping(string:mixed) subw,string line)
{
	say(subw, "%%%% Command input: %O", line);
	say(subw, "%% If this function returns 1, the line will be suppressed.");
	return 0;
}

int output(mapping(string:mixed) subw,string line)
{
	say(subw, "%%%% Text from the server: %O", line);
	say(subw, "%% If this function returns 1, the line will be suppressed.");
	return 0;
}

int prompt(mapping(string:mixed) subw,string prompt)
{
	say(subw, "%%%% New prompt: %O", prompt);
	say(subw, "%% If this function returns 1, the change will be ignored.");
	return 0;
}

int closetab(mapping(string:mixed) subw,int index)
{
	say(subw, "%% Closing a tab... you probably won't see this text.");
	say(subw, "%% Returning 1 from this function will disallow the closing.");
	return 0;
}

int switchtabs(mapping(string:mixed) subw)
{
	say(subw, "%% This tab has just been switched to.");
	say(subw, "%% Note that there's no notification of which tab has just");
	say(subw, "%% been switched away from, nor can you (currently) discover");
	say(subw, "%% a subw's position across the list, short of poking around.");
}

// ----------------- inherit movablewindow ----------------- //
constant pos_key="plugins/demo/winpos";
constant load_size=1; //To resize on startup to the last saved size
//The following are also valid for 'inherit window'.
void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Demo Plugin"]))
		->add(GTK2.Frame("Stuff goes here")->add(win->clickme=GTK2.Button("Click me!")));
	::makewindow();
}

void sig_clickme_clicked()
{
	say(0, "%% You clicked me!");
}

// ----------------- inherit statusevent ----------------- //
void statusbar_double_click()
{
	setstatus("Clicks: " + (++statustxt->clickcnt));
}

// ----------------- inherit plugin_menu ----------------- //

//It's common for a menu item to call up a configdlg.
//If this is the sole purpose of the menu item, this can be simplified
//to "class menu_clicked" and everything will work.
class config
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Demo configuration"]);
	constant persist_key="plugins/demo";
	constant elements=({"kwd:Thing", "Meaning", "#Value", "?Useful or not"});

	void save_content(mapping(string:mixed) info)
	{
		say(0, "Saving a configdlg slot");
	}

	void load_content(mapping(string:mixed) info)
	{
		say(0, "Loading configdlg data");
	}

	void delete_content(string kwd,mapping(string:mixed) info)
	{
		say(0, "Deleting a config slot");
	}
}

constant menu_label="Demo menu item";
constant menu_accel_key='z';
constant menu_accel_mods=GTK2.GDK_CONTROL_MASK;
void menu_clicked()
{
	say(0, "You clicked my menu item!");
	config(); //Invoke the config dialog
}

//Always provide this function if you inherit more than one mode.
void create(string name)
{
	statustxt->tooltip = "See demo.pike for more information";
	::create(name);
	setstatus("Dblclick me!");
}
