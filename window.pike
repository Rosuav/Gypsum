//GUI handler.

//Each 'line' represents one line that came from the MUD. In theory, they might be wrapped for display, which would
//mean taking up more than one display line, though currently this is not implemented.
//Each entry must alternate between color and string, in that order.
array(array(GTK2.GdkColor|string)) lines=({ });
array(GTK2.GdkColor|string) prompt=({ });
GTK2.DrawingArea display;
GTK2.ScrolledWindow maindisplay;
GTK2.Adjustment scr;
GTK2.Entry ef;
GTK2.Button defbutton;
array signal;
array(string) cmdhist=({ });
int histpos=-1;
string defcolors="000000 00007F 007F00 007F7F 7F0000 7F007F 7F7F00 C0C0C0 7F7F7F 0000FF 00FF00 00FFFF FF0000 FF00FF FFFF00 FFFFFF"; //TODO: INI file this. (And stop reversing them.)
array(GTK2.GdkColor) colors;
array(string) colornames=({
	"black","dark red","dark green","#880","dark blue","dark magenta","dark cyan","grey",
	"dark grey","red","green","yellow","blue","magenta","cyan","white",
});
int passwordmode; //When 1, commands won't be saved.
int lineheight; //Pixel height of a line of text
int totheight; //Current height of the display

void saybouncer(string msg) {G->G->window->say(msg);} //Say, Bouncer, say!
void say(string|array msg)
{
	if (stringp(msg)) msg=({colors[7],msg});
	for (int i=0;i<sizeof(msg);i+=2) if (!msg[i]) msg[i]=colors[7];
	lines+=({msg});
	redraw();
}

void say_color(int col,string msg)
{
	lines+=({({colors[col],msg})});
	redraw();
}
void redraw()
{
	int height=(int)scr->get_property("page size")+lineheight*(sizeof(lines)+1);
	if (height!=totheight) display->set_size_request(-1,totheight=height);
}

object mkcolor(int fg,int bg)
{
	return colors[fg];
}

void calcheight()
{
	mapping sz=display->create_pango_layout("asdf")->index_to_pos(3);
	lineheight=sz->height/1024;
}

//Paint one line of text at the given 'y'.
int paintline(GTK2.GdkGC gc,array(GTK2.GdkColor|string) line,int y)
{
	int x=3;
	for (int i=0;i<sizeof(line);i+=2)
	{
		//display->create_pango_layout(""); //Without one of these calls for every draw_text, Pike 7.8.352 crashes.
		mapping sz; if (sizeof(line[i+1])) sz=display->create_pango_layout(line[i+1])->index_to_pos(sizeof(line[i+1])-1);
		else display->create_pango_layout("");
		gc->set_foreground(line[i] || colors[7]);
		display->draw_text(gc,x,y,line[i+1]);
		if (sz) x+=(sz->x+sz->width)/1024;
	}
}
int paint(object self)
{
	display->set_background(GTK2.GdkColor(0,0,0));
	GTK2.GdkGC gc=GTK2.GdkGC(display);
	int y=(int)scr->get_property("page size");
	foreach (lines,array(GTK2.GdkColor|string) line)
	{
		paintline(gc,line,y);
		y+=lineheight;
	}
	paintline(gc,prompt,y);
	display->set_size_request(-1,y+=lineheight);
	if (y!=totheight) display->set_size_request(-1,totheight=y);
}

void create(string name)
{
	if (!G->G->window)
	{
		add_constant("say",saybouncer);
		GTK2.setup_gtk();
		colors=({});
		foreach (defcolors/" ",string col) colors+=({GTK2.GdkColor(@reverse(array_sscanf(col,"%2x%2x%2x")))});
		object mainwindow=G->G->mainwindow=GTK2.Window(GTK2.WindowToplevel);
		mainwindow->set_title("Gypsum")->set_default_size(800,500)->signal_connect("destroy",window_destroy);
		mainwindow->signal_connect("delete_event",window_destroy);
		maindisplay=GTK2.ScrolledWindow((["hadjustment":GTK2.Adjustment(),"vadjustment":scr=GTK2.Adjustment(),"background":"black"]))
			->add(display=GTK2.DrawingArea())
			->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_ALWAYS)
			->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(0,0,0));
		defbutton=GTK2.Button()->set_size_request(0,0)->set_flags(GTK2.CAN_DEFAULT);
		mainwindow->add(GTK2.Vbox(0,0)
			->add(maindisplay)
			->pack_end(ef=GTK2.Entry(),0,0,0)
			->pack_end(defbutton,0,0,0)
		)->show_all();
		display->set_background(GTK2.GdkColor(0,0,0))->modify_font(GTK2.PangoFontDescription("Courier Bold 10"))->signal_connect("expose_event",paint);
		scr=GTK2.Adjustment();
		ef->grab_focus(); defbutton->grab_default(); ef->set_activates_default(1);
		mainwindow->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(0,0,0));
		scr=maindisplay->get_vadjustment();
		//maindisplay->get_child()->signal_connect("event",showev);
		scr->signal_connect("changed",lambda() {scr->set_value(scr->get_property("upper")-scr->get_property("page size"));});
		//scr->signal_connect("value_changed",lambda(mixed ... args) {write("value_changed: %O %O\n",scr->get_value(),scr->get_property("upper")-scr->get_property("page size"));});
		calcheight();
	}
	else
	{
		object other=G->G->window;
		display=other->display; scr=other->scr; ef=other->ef; defbutton=other->defbutton; lines=other->lines; colors=other->colors;
		cmdhist=other->cmdhist; histpos=other->histpos;
		prompt=other->prompt;
		if (other->signal)
		{
			ef->signal_disconnect(other->signal[0]);
			if (sizeof(other->signal)>1) defbutton->signal_disconnect(other->signal[1]);
		}
	}
	signal=({ef->signal_connect("key_press_event",keypress),
		//ef->signal_connect("activate",enterpressed), //Crashes Pike!
		defbutton->signal_connect("clicked",enterpressed),
	});
	G->G->window=this;
}
int window_destroy(object self)
{
	exit(0);
}

int showev(object self,array ev,int dummy) {werror("%O->%O\n",self,ev[0]);}

void settext(string text)
{
	ef->set_text(text);
	ef->set_position(sizeof(text));
}

int keypress(object self,array|object ev)
{
	if (arrayp(ev)) ev=ev[0];
	switch (ev->keyval)
	{
		case 0xFFC1: enterpressed(self); return 1; //F4 - hack.
		case 0xFF52: //Up arrow
		{
			if (histpos==-1) histpos=sizeof(cmdhist);
			if (histpos) settext(cmdhist[--histpos]);
			return 1;
		}
		case 0xFF54: //Down arrow
		{
			if (histpos==-1)
			{
				//Optionally clear the EF
			}
			else if (histpos<sizeof(cmdhist)-1) settext(cmdhist[++histpos]);
			else {ef->set_text(""); histpos=-1;}
			return 1;
		}
		case 0xFF1B: ef->set_text(""); return 1; //Esc
		case 0xFF09: //Tab
		{
			ef->set_position(ef->insert_text("\t",1,ef->get_position()));
			return 1;
		}
		case 0xFFE1: case 0xFFE2: //Shift
		case 0xFFE3: case 0xFFE4: //Ctrl
		case 0xFFE7: case 0xFFE8: //Windows keys
		case 0xFFE9: case 0xFFEA: //Alt
			break;
		default: say(sprintf("%%%% keypress: %X",ev[0]->keyval)); break;
	}
}
int enterpressed(object self)
{
	string cmd=ef->get_text(); ef->set_text("");
	histpos=-1;
	if (!passwordmode)
	{
		if (!sizeof(cmdhist) || cmd!=cmdhist[-1]) cmdhist+=({cmd});
		lines+=({prompt+({colors[6],cmd})});
	}
	else lines+=({prompt});
	if (sizeof(cmd)>1 && cmd[0]=='/' && cmd[1]!='/')
	{
		redraw();
		sscanf(cmd,"/%[^ ] %s",cmd,string args);
		if (G->G->commands[cmd] && G->G->commands[cmd](args||"")) return 0;
		say("%% Unknown command.");
		return 0;
	}
	prompt=({ }); redraw();
	if (!passwordmode)
	{
		array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks); //Sort by name for consistency
		foreach (hooks,object h) if (h->inputhook(cmd)) return 1;
	}
	G->G->sock->write(cmd+"\r\n");
	return 1;
}
void   password() {passwordmode=1; ef->set_visibility(0);}
void unpassword() {passwordmode=0; ef->set_visibility(1);}
