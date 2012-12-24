//GUI handler.

//First color must be black.
string defcolors="000000 00007F 007F00 007F7F 7F0000 7F007F 7F7F00 C0C0C0 7F7F7F 0000FF 00FF00 00FFFF FF0000 FF00FF FFFF00 FFFFFF"; //TODO: INI file this. (And stop reversing them.)
array(GTK2.GdkColor) colors;

array(mapping(string:mixed)) tabs=({ }); //In the same order as the notebook's internal tab objects
GTK2.Window mainwindow;
GTK2.Notebook notebook;
mapping signal;
GTK2.Button defbutton;

/* Each subwindow is defined with a mapping(string:mixed) - some useful elements are:

	//Each 'line' represents one line that came from the MUD. In theory, they might be wrapped for display, which would
	//mean taking up more than one display line, though currently this is not implemented.
	//Each entry must alternate between color and string, in that order.
	array(array(GTK2.GdkColor|string)) lines=({ });
	array(GTK2.GdkColor|string) prompt=({ });
	GTK2.DrawingArea display;
	GTK2.ScrolledWindow maindisplay;
	GTK2.Adjustment scr;
	GTK2.Entry ef;
	GTK2.Widget page;
	array(string) cmdhist=({ });
	int histpos=-1;
	int passwordmode; //When 1, commands won't be saved.
	int lineheight; //Pixel height of a line of text
	int totheight; //Current height of the display
	mapping connection;
	string tabtext;
	int activity=0; //Set to 1 when there's activity, set to 0 when focus is on this tab
*/
mapping(string:mixed) subwindow(string txt)
{
	mapping(string:mixed) subw=(["lines":({ }),"prompt":({ }),"cmdhist":({ }),"histpos":-1]);
	//Build the window
	notebook->append_page(subw->page=GTK2.Vbox(0,0)
		->add(subw->maindisplay=GTK2.ScrolledWindow((["hadjustment":GTK2.Adjustment(),"vadjustment":subw->scr=GTK2.Adjustment(),"background":"black"]))
			->add(subw->display=GTK2.DrawingArea())
			->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_ALWAYS)
			->modify_bg(GTK2.STATE_NORMAL,colors[0])
		)
		->pack_end(subw->ef=GTK2.Entry(),0,0,0)
	->show_all(),GTK2.Label(subw->tabtext=txt));
	subw->display->set_background(colors[0])->modify_font(GTK2.PangoFontDescription("Courier Bold 10"))->signal_connect("expose_event",paint,subw);
	subw->ef->grab_focus(); subw->ef->set_activates_default(1);
	subw->scr=subw->maindisplay->get_vadjustment();
	subw->scr->signal_connect("changed",scrchange,subw);
	//subw->scr->signal_connect("value_changed",lambda(mixed ... args) {write("value_changed: %O %O\n",subw->scr->get_value(),subw->scr->get_property("upper")-subw->scr->get_property("page size"));});
	subw->ef->signal_connect("key_press_event",keypress,subw);
	subw->lineheight=subw->display->create_pango_layout("asdf")->index_to_pos(3)->height/1024; //Nice little one-liner, that! :)
	tabs+=({subw});
	return subw;
}

void scrchange(object self,mapping subw) {subw->scr->set_value(subw->scr->get_property("upper")-subw->scr->get_property("page size"));}
void say(string|array msg,mapping|void subw)
{
	if (!subw) subw=tabs[notebook->get_current_page()];
	if (stringp(msg))
	{
		if (msg[-1]=='\n') msg=msg[..<1];
		foreach (msg/"\n",string line) subw->lines+=({({colors[7],line})});
	}
	else
	{
		for (int i=0;i<sizeof(msg);i+=2) if (!msg[i]) msg[i]=colors[7];
		subw->lines+=({msg});
	}
	subw->activity=1;
	redraw(subw);
}
void say_color(mapping subw,int col,string msg)
{
	subw->lines+=({({colors[col],msg})});
	subw->activity=1;
	redraw(subw);
}
void connect(mapping info,mapping|void subw)
{
	if (!subw) subw=tabs[notebook->get_current_page()];
	if (!info)
	{
		//Disconnect
		if (!subw->connection || !subw->connection->sock) return; //Silent if nothing to dc
		subw->connection->sock->close(); G->G->connection->sockclosed(subw->connection);
		return;
	}
	if (subw->connection && subw->connection->sock) {say("%% Already connected."); return;}
	subw->connection=G->G->connection->connect(subw,info);
	subw->tabtext=info->tabtext || info->name || "(unnamed)";
}

void redraw(mapping subw)
{
	int height=(int)subw->scr->get_property("page size")+subw->lineheight*(sizeof(subw->lines)+1);
	if (height!=subw->totheight) subw->display->set_size_request(-1,subw->totheight=height);
	if (tabs[notebook->get_current_page()]==subw) subw->activity=0;
	notebook->set_tab_label_text(subw->page,"* "*subw->activity+subw->tabtext);
	subw->maindisplay->queue_draw();
}

object mkcolor(int fg,int bg)
{
	return colors[fg];
}

//Paint one line of text at the given 'y'.
int paintline(GTK2.DrawingArea display,GTK2.GdkGC gc,array(GTK2.GdkColor|string) line,int y)
{
	int x=3;
	for (int i=0;i<sizeof(line);i+=2)
	{
		object killme;
		mapping sz; if (sizeof(line[i+1])) sz=(killme=display->create_pango_layout(line[i+1]))->index_to_pos(sizeof(line[i+1])-1);
		//else killme=display->create_pango_layout(""); //Without one of these calls for every draw_text, Pike 7.8.352 crashes.
		gc->set_foreground(line[i] || colors[7]);
		display->draw_text(gc,x,y,line[i+1]);
		if (sz) x+=(sz->x+sz->width)/1024;
		if (killme) destruct(killme);
	}
}
int paint(object self,object ev,mapping subw)
{
	GTK2.DrawingArea display=subw->display; //Cache, we'll use it a lot
	display->set_background(colors[0]); //TODO: Leak??
	GTK2.GdkGC gc=GTK2.GdkGC(display);
	int y=(int)subw->scr->get_property("page size");
	foreach (subw->lines,array(GTK2.GdkColor|string) line)
	{
		paintline(display,gc,line,y);
		y+=subw->lineheight;
	}
	paintline(display,gc,subw->prompt,y);
	display->set_size_request(-1,y+=subw->lineheight);
	if (y!=subw->totheight) display->set_size_request(-1,subw->totheight=y);
}

void settext(mapping subw,string text)
{
	subw->ef->set_text(text);
	subw->ef->set_position(sizeof(text));
}

int keypress(object self,array|object ev,mapping subw)
{
	if (arrayp(ev)) ev=ev[0];
	switch (ev->keyval)
	{
		case 0xFFC1: enterpressed(subw); return 1; //F4 - hack.
		case 0xFF52: //Up arrow
		{
			if (subw->histpos==-1) subw->histpos=sizeof(subw->cmdhist);
			if (subw->histpos) settext(subw,subw->cmdhist[--subw->histpos]);
			return 1;
		}
		case 0xFF54: //Down arrow
		{
			if (subw->histpos==-1)
			{
				//Optionally clear the EF
			}
			else if (subw->histpos<sizeof(subw->cmdhist)-1) settext(subw,subw->cmdhist[++subw->histpos]);
			else {subw->ef->set_text(""); subw->histpos=-1;}
			return 1;
		}
		case 0xFF1B: subw->ef->set_text(""); return 1; //Esc
		case 0xFF09: case 0xFE20: //Tab and shift-tab
		{
			if (ev->state&GTK2.GDK_CONTROL_MASK)
			{
				//Note: Not using notebook->{next|prev}_page() as they don't cycle.
				int page=notebook->get_current_page();
				if (ev->state&GTK2.GDK_SHIFT_MASK) {if (--page<0) page=notebook->get_n_pages()-1;}
				else {if (++page>=notebook->get_n_pages()) page=0;}
				notebook->set_current_page(page);
				return 1;
			}
			subw->ef->set_position(subw->ef->insert_text("\t",1,subw->ef->get_position()));
			return 1;
		}
		case 0xFFE1: case 0xFFE2: //Shift
		case 0xFFE3: case 0xFFE4: //Ctrl
		case 0xFFE7: case 0xFFE8: //Windows keys
		case 0xFFE9: case 0xFFEA: //Alt
			break;
		default: say(sprintf("%%%% keypress: %X",ev->keyval),subw); break;
	}
}
int enterpressed(mapping subw)
{
	string cmd=subw->ef->get_text(); subw->ef->set_text("");
	subw->histpos=-1;
	if (!subw->passwordmode)
	{
		if (!sizeof(subw->cmdhist) || cmd!=subw->cmdhist[-1]) subw->cmdhist+=({cmd});
		subw->lines+=({subw->prompt+({colors[6],cmd})});
	}
	else subw->lines+=({subw->prompt});
	if (sizeof(cmd)>1 && cmd[0]=='/' && cmd[1]!='/')
	{
		redraw(subw);
		sscanf(cmd,"/%[^ ] %s",cmd,string args);
		if (G->G->commands[cmd] && G->G->commands[cmd](args||"")) return 0;
		say("%% Unknown command.",subw);
		return 0;
	}
	subw->prompt=({ }); redraw(subw);
	if (!subw->passwordmode)
	{
		array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks); //Sort by name for consistency
		foreach (hooks,object h) if (h->inputhook(cmd)) return 1;
	}
	if (subw->connection) G->G->connection->write(subw->connection,cmd+"\r\n");
	return 1;
}
void   password(mapping subw) {subw->passwordmode=1; subw->ef->set_visibility(0);}
void unpassword(mapping subw) {subw->passwordmode=0; subw->ef->set_visibility(1);}

void saybouncer(string msg) {G->G->window->say(msg);} //Say, Bouncer, say!
string recon() {return (tabs[notebook->get_current_page()]->connection||([]))->recon;}

void create(string name)
{
	if (!G->G->window)
	{
		add_constant("say",saybouncer);
		GTK2.setup_gtk();
		colors=({});
		foreach (defcolors/" ",string col) colors+=({GTK2.GdkColor(@reverse(array_sscanf(col,"%2x%2x%2x")))});
		mainwindow=GTK2.Window(GTK2.WindowToplevel);
		mainwindow->set_title("Gypsum")->set_default_size(800,500)->signal_connect("destroy",window_destroy);
		mainwindow->signal_connect("delete_event",window_destroy);
		mainwindow->add(GTK2.Vbox(0,0)
			->pack_start(GTK2.MenuBar()
				->add(GTK2.MenuItem("_File")->set_submenu(GTK2.Menu()
					->add(menuitem("_New Tab",addtab))
					->add(menuitem("E_xit",window_destroy))
				))
			,0,0,0)
			->add(notebook=GTK2.Notebook())
			->pack_end(defbutton=GTK2.Button()->set_size_request(0,0)->set_flags(GTK2.CAN_DEFAULT),0,0,0)
		)->show_all();
		defbutton->grab_default();
		addtab();
		//mainwindow->modify_bg(GTK2.STATE_NORMAL,colors[0]);
	}
	else
	{
		object other=G->G->window;
		colors=other->colors; notebook=other->notebook; defbutton=other->defbutton; mainwindow=other->mainwindow;
		tabs=other->tabs;
		if (other->signal)
		{
			defbutton->signal_disconnect(other->signal->enter);
		}
	}
	signal=([
		"enter":defbutton->signal_connect("clicked",enterpressed_glo),
	]);
	G->G->window=this;
}
void addtab() {subwindow("Tab "+(1+sizeof(tabs)));}
int window_destroy(object self)
{
	exit(0);
}

//Helper function to create a menu item and give it an event. Useful because signal_connect doesn't return self.
GTK2.MenuItem menuitem(mixed content,function event)
{
	GTK2.MenuItem ret=GTK2.MenuItem(content);
	ret->signal_connect("activate",event);
	return ret;
}

int showev(object self,array ev,int dummy) {werror("%O->%O\n",self,(mapping)ev[0]);}

int enterpressed_glo(object self)
{
	object focus=mainwindow->get_focus();
	object parent=focus->get_parent();
	while (parent->get_name()!="GtkNotebook") parent=(focus=parent)->get_parent();
	return enterpressed(tabs[parent->page_num(focus)]);
}
