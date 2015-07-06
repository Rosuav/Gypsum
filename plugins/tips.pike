constant docstring=#"
Provide random help tips on request, via the Help|Tips menu.
";

constant tips=({
	//Tips will be reformatted: tabs and newlines converted to spaces, space-space to space, then wrapped.
	//Similar tips allow a minor form of emphasis - more probability of talking about that feature.
	#"Check the Plugins|Configure dialog for a list of all detected plugins.
	You never know what you'll find!",

	#"Quickly reconnect to the same world you were last connected to by
	entering /c or /connect - coupled with auto-login, this can rescue
	you from linkdeath or internet connection changes very efficiently.",

	#"Need to take notes about another character? Hold Ctrl while double
	clicking on his/her name to quickly bring up the Highlight Words config
	for that particular name.",

	#"Match Options|Channel Colors to the server's colors for each channel
	to instantly highlight what channel your text will be sent to.",

	#"If something doesn't behave the way you want it to, check out
	Options|Advanced. It's entirely possible the option you want is there!",

	#"To quickly look at the source code for a plugin, type '/edit pluginname'
	and a pop-out editor will be opened up.",

	#"Two characters on the same server? Create separate worlds for them, and
	distinguish between their auto-logins, aliases, and other configuration.",

	#"Type '/edit someplugin' to have a look at its source code. Some have
	obscure features that you might not have realized exist!",

	#"Use the /x command as a simple, but powerful, calculator - mathematical
	expressions will be evaluated and displayed.",

	#"The /x calculator can call on the previous result with the shorthand _
	(underscore) - for instance, _+1 will add one to the previous result.",

	#"Keep Gypsum up-to-date using Plugins|Update Gypsum; there are changes
	literally every day.",

	#"Non-English text is fully supported in Gypsum. As long as the server
	accepts and transmits UTF-8 text, all the world's languages can be
	properly displayed and entered. Check your system for a Unicode font
	for best results.",

	#"Keep an eye on a clock in your own or someone else's timezone with the
	zoneinfo plugin - you can select any timezone to show on the status bar.",

	#"Install GNU Aspell to enable a quick spell-checker for your input,
	the spellchk.pike plugin - hit (Shift-)F9 to quickly check spelling.",

	#"Some plugins are a bit underused, but if you like them, contact the
	author; ideas for improvements will be much welcomed.",

	#"While the core code of Gypsum is server-agnostic to the greatest extent
	possible, some plugins are specific to particular servers. They will be
	useless (though harmless) when other servers are used.",

	#"Got ideas for more tips? Submit them via github and get your name
	permanently recorded as a contributor!",
});

constant plugin_active_by_default=1;

inherit plugin_menu;
constant menu_parent="help";
constant menu_label="_Tips";

class menu_clicked
{
	inherit window;
	void create() {::create();}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Gypsum tips and tricks"]))->add(GTK2.Vbox(0,0)
			->add(GTK2.Frame("Tip:")->add(win->tip=GTK2.Label("Searching for tips...")->set_line_wrap(1)))
			->add(GTK2.HbuttonBox()
				->add(win->newtip=GTK2.Button("New tip"))
				->add(stock_close())
			)
		);
		sig_newtip_clicked();
		::makewindow();
	}

	void sig_newtip_clicked()
	{
		win->tip->set_text(replace(replace(random(tips),({"\n","\t"})," "),"  "," "));
	}
}
