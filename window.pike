//GUI handler.

//First color must be black.
string defcolors="000000 00007F 007F00 007F7F 7F0000 7F007F 7F7F00 C0C0C0 7F7F7F 0000FF 00FF00 00FFFF FF0000 FF00FF FFFF00 FFFFFF"; //TODO: INI file this. (And stop reversing them.)
array(GTK2.GdkColor) colors;

array(mapping(string:mixed)) tabs=({ }); //In the same order as the notebook's internal tab objects
GTK2.Window mainwindow;
GTK2.Notebook notebook;
GTK2.Button defbutton;
GTK2.Label statusbar;
array(object) signals;

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
	array(object) signals; //Collection of gtksignal objects - replaced after code reload
*/
mapping(string:mixed) subwindow(string txt)
{
	mapping(string:mixed) subw=(["lines":({ }),"prompt":({ }),"cmdhist":({ }),"histpos":-1]);
	//Build the window
	notebook->append_page(subw->page=GTK2.Vbox(0,0)
		->add(subw->maindisplay=GTK2.ScrolledWindow((["hadjustment":GTK2.Adjustment(),"vadjustment":subw->scr=GTK2.Adjustment(),"background":"black"]))
			->add(subw->display=GTK2.DrawingArea())
			->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_ALWAYS)
		)
		->pack_end(subw->ef=GTK2.Entry(),0,0,0)
	->show_all(),GTK2.Label(subw->tabtext=txt));
	object font=GTK2.PangoFontDescription("Courier Bold 10");
	subw->display->modify_font(font);
	subw->ef->modify_font(font);
	subw->ef->grab_focus(); subw->ef->set_activates_default(1);
	subwsignals(subw);
	mapping dimensions=subw->display->create_pango_layout("asdf")->index_to_pos(3);
	subw->lineheight=dimensions->height/1024; subw->charwidth=dimensions->width/1024;
	tabs+=({subw});
	return subw;
}

//Load up the new signals and expire all the old ones
void subwsignals(mapping(string:mixed) subw)
{
	subw->signals=({
		gtksignal(subw->display,"expose_event",paint,subw),
		gtksignal(subw->scr,"changed",scrchange,subw),
		//gtksignal(subw->scr,"value_changed",lambda(mixed ... args) {write("value_changed: %O %O\n",subw->scr->get_value(),subw->scr->get_property("upper")-subw->scr->get_property("page size"));}),
		gtksignal(subw->ef,"key_press_event",keypress,subw),
		gtksignal(subw->display,"button_press_event",mousedown,subw),
		gtksignal(subw->display,"button_release_event",mouseup,subw),
		gtksignal(subw->display,"motion_notify_event",mousemove,subw),
	});
	subw->display->add_events(GTK2.GDK_POINTER_MOTION_MASK|GTK2.GDK_BUTTON_PRESS_MASK|GTK2.GDK_BUTTON_RELEASE_MASK);
}

void scrchange(object self,mapping subw)
{
	float upper=self->get_property("upper");
	//werror("upper %f, page %f, pos %f\n",upper,self->get_property("page size"),upper-self->get_property("page size"));
	#if constant(GTK_BUGGY)
	//On Windows, there's a problem with having more than 32767 of height. It seems to be resolved, though, by scrolling up to about 16K and then down again.
	//TODO: Solve this properly. Failing that, find the least flickery way to do this scrolling (would it still work if painting is disabled?)
	if (upper>32000.0) self->set_value(16000.0);
	#endif
	self->set_value(upper-self->get_property("page size"));
}

//Convert (x,y) into (line,col) - yes, that switches their order.
//Depends on the current scr->pagesize.
//Note that line and col may exceed the array index limits by 1 - equalling sizeof(subw->lines) or the size of the string at that line.
//A return value equal to the array/string size represents the prompt or the (implicit) newline at the end of the string.
array(int) point_to_char(mapping subw,int x,int y)
{
	int line=(y-(int)subw->scr->get_property("page size"))/subw->lineheight;
	array l;
	if (line<0) line=0;
	if (line>=sizeof(subw->lines)) {line=sizeof(subw->lines); l=subw->prompt;}
	else l=subw->lines[line];
	string str=filter(l,stringp)*"";
	int col=(x-3)/subw->charwidth;
	if (col<0) col=0; else if (col>sizeof(str)) col=sizeof(str);
	return ({line,col});
}

int selstartline=-1,selstartcol,selendline,selendcol;
void mousedown(object self,object ev,mapping subw)
{
	[selstartline,selstartcol]=point_to_char(subw,(int)ev->x,(int)ev->y);
	selendline=selstartline; selendcol=selstartcol;
}
void mouseup(object self,object ev,mapping subw)
{
	if (selstartline==-1) return;
	[int line,int col]=point_to_char(subw,(int)ev->x,(int)ev->y);
	string content;
	if (selstartline==line)
	{
		//Single-line selection: special-cased for simplicity.
		if (selstartcol>col) [col,selstartcol]=({selstartcol,col});
		content=filter((line==sizeof(subw->lines))?subw->prompt:subw->lines[line],stringp)*""+"\n";
		content=content[selstartcol..col-1];
	}
	else
	{
		if (selstartline>line) [line,col,selstartline,selstartcol]=({selstartline,selstartcol,line,col});
		for (int l=selstartline;l<=line;++l)
		{
			string curline=filter((l==sizeof(subw->lines))?subw->prompt:subw->lines[l],stringp)*""+"\n";
			if (l==selstartline) content=curline[selstartcol..];
			else if (l==line) content+=curline[..col-1];
			else content+=curline;
		}
	}
	int y1= min(selstartline,line)   *subw->lineheight;
	int y2=(max(selstartline,line)+1)*subw->lineheight;
	subw->display->queue_draw_area(0,subw->scr->get_property("page size")+y1,1<<30,y2-y1);
	//subw->display->queue_draw();
	selstartline=-1;
	subw->display->get_clipboard(GTK2.Gdk_Atom("CLIPBOARD"))->set_text(content,sizeof(content));
}
void mousemove(object self,object ev,mapping subw)
{
	[int line,int col]=point_to_char(subw,(int)ev->x,(int)ev->y);
	statusbar->set_text(sprintf("Line %d of %d",line,sizeof(subw->lines)));
	if (selstartline!=-1 && (line!=selendline || col!=selendcol))
	{
		int y1= min(selendline,line)   *subw->lineheight;
		int y2=(max(selendline,line)+1)*subw->lineheight;
		subw->display->queue_draw_area(0,subw->scr->get_property("page size")+y1,1<<30,y2-y1);
		//subw->display->queue_draw(); //Full repaint for debugging
		selendline=line; selendcol=col;
	}
}

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

//Paint one piece of text at (x,y), returns the x for the next text.
int painttext(GTK2.DrawingArea display,GTK2.GdkGC gc,int x,int y,string txt,GTK2.GdkColor fg,GTK2.GdkColor bg)
{
	if (txt=="") return x;
	object layout=display->create_pango_layout(txt);
	mapping sz=layout->index_to_pos(sizeof(txt)-1);
	if (bg!=colors[0]) //Why can't I just set_background and then tell draw_text to cover any background pixels? Meh.
	{
		gc->set_foreground(bg); //(sic)
		display->draw_rectangle(gc,1,x,y,(sz->x+sz->width)/1024,sz->height/1024);
	}
	gc->set_foreground(fg);
	display->draw_text(gc,x,y,txt);
	destruct(layout);
	return x+(sz->x+sz->width)/1024;
}

//Paint one line of text at the given 'y'. Will highlight from hlstart to hlend with inverted fg/bg colors.
void paintline(GTK2.DrawingArea display,GTK2.GdkGC gc,array(GTK2.GdkColor|string) line,int y,int hlstart,int hlend)
{
	int x=3;
	for (int i=0;i<sizeof(line);i+=2) if (sizeof(line[i+1]))
	{
		string txt=replace(line[i+1],"\n","\\n");
		if (hlend<0) hlstart=sizeof(txt); //No highlight left to do.
		if (hlstart>0)
		{
			//Draw the leading unhighlighted part (which might be the whole string).
			x=painttext(display,gc,x,y,txt[..hlstart-1],line[i] || colors[7],colors[0]);
		}
		if (hlstart<sizeof(txt))
		{
			//Draw the highlighted part (which might be the whole string).
			x=painttext(display,gc,x,y,txt[hlstart..min(hlend,sizeof(txt))],colors[0],line[i] || colors[7]);
			if (hlend<sizeof(txt))
			{
				//Draw the trailing unhighlighted part.
				x=painttext(display,gc,x,y,txt[hlend+1..],line[i] || colors[7],colors[0]);
			}
		}
		hlstart-=sizeof(txt); hlend-=sizeof(txt);
	}
}
int paint(object self,object ev,mapping subw)
{
	int start=ev->y-subw->lineheight,end=ev->y+ev->height+subw->lineheight; //We'll paint complete lines, but only those lines that need painting.
	GTK2.DrawingArea display=subw->display; //Cache, we'll use it a lot
	display->set_background(colors[0]);
	GTK2.GdkGC gc=GTK2.GdkGC(display);
	int y=(int)subw->scr->get_property("page size");
	int ssl=selstartline,ssc=selstartcol,sel=selendline,sec=selendcol;
	if (ssl==-1) sel=-1;
	else if (ssl>sel || (ssl==sel && ssc>sec)) [ssl,ssc,sel,sec]=({sel,sec,ssl,ssc}); //Get the numbers forward rather than backward
	foreach (subw->lines+({subw->prompt});int l;array(GTK2.GdkColor|string) line)
	{
		if (y>=start && y<=end)
		{
			int hlstart=-1,hlend=-1;
			if (l>=ssl && l<=sel)
			{
				if (l==ssl) hlstart=ssc;
				if (l==sel) hlend=sec-1; else hlend=1<<30;
			}
			paintline(display,gc,line,y,hlstart,hlend);
		}
		y+=subw->lineheight;
	}
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
		if (cmd!="" && (!sizeof(subw->cmdhist) || cmd!=subw->cmdhist[-1])) subw->cmdhist+=({cmd});
		subw->lines+=({subw->prompt+({colors[6],cmd})});
	}
	else subw->lines+=({subw->prompt});
	if (sizeof(cmd)>1 && cmd[0]=='/' && cmd[1]!='/')
	{
		redraw(subw);
		sscanf(cmd,"/%[^ ] %s",cmd,string args);
		if (G->G->commands[cmd] && G->G->commands[cmd](args||"",subw)) return 0;
		say("%% Unknown command.",subw);
		return 0;
	}
	subw->prompt=({ }); redraw(subw);
	if (!subw->passwordmode)
	{
		array hooks=values(G->G->hooks); sort(indices(G->G->hooks),hooks); //Sort by name for consistency
		foreach (hooks,object h) if (h->inputhook(cmd,subw)) return 1;
	}
	if (subw->connection) G->G->connection->write(subw->connection,cmd+"\r\n");
	return 1;
}
void   password(mapping subw) {subw->passwordmode=1; subw->ef->set_visibility(0);}
void unpassword(mapping subw) {subw->passwordmode=0; subw->ef->set_visibility(1);}

string recon(mapping|void subw) {return ((subw||tabs[notebook->get_current_page()])->connection||([]))->recon;}

void create(string name)
{
	if (!G->G->window)
	{
		add_constant("say",bouncer("window","say")); //Say, Bouncer, say!
		GTK2.setup_gtk();
		colors=({});
		foreach (defcolors/" ",string col) colors+=({GTK2.GdkColor(@reverse(array_sscanf(col,"%2x%2x%2x")))});
		mainwindow=GTK2.Window(GTK2.WindowToplevel);
		mainwindow->set_title("Gypsum")->set_default_size(800,500);
		if (array pos=persist["window/winpos"]) mainwindow->move(pos[0],pos[1]);
		mainwindow->add(GTK2.Vbox(0,0)
			->pack_start(GTK2.MenuBar()
				->add(GTK2.MenuItem("_File")->set_submenu(GTK2.Menu()
					->add(menuitem("_New Tab",bouncer("window","addtab")))
					->add(menuitem("_Connect",bouncer("window","connect_menu")))
					->add(menuitem("E_xit",bouncer("window","window_destroy")))
				))
			,0,0,0)
			->add(notebook=GTK2.Notebook())
			->pack_end(GTK2.Frame()->add(statusbar=GTK2.Label((["xalign":0.0])))->set_shadow_type(GTK2.SHADOW_ETCHED_OUT),0,0,0)
			->pack_end(defbutton=GTK2.Button()->set_size_request(0,0)->set_flags(GTK2.CAN_DEFAULT),0,0,0)
		)->show_all();
		defbutton->grab_default();
		addtab();
		call_out(mainwindow->present,0); //After any plugin windows have loaded, grab - or attempt to grab - focus back to the main window.
	}
	else
	{
		object other=G->G->window;
		colors=other->colors; notebook=other->notebook; defbutton=other->defbutton; mainwindow=other->mainwindow;
		tabs=other->tabs; statusbar=other->statusbar;
		if (other->signals) other->signals=0; //Clear them out, just in case.
		foreach (tabs,mapping subw) subwsignals(subw);
	}
	G->G->window=this;
	mainwsignals();
}
void addtab() {subwindow("Tab "+(1+sizeof(tabs)));}
int window_destroy(object self)
{
	exit(0);
}

//Either reconnect, or give the world list.
void connect_menu(object self)
{
	G->G->commands->connect("dlg",tabs[notebook->get_current_page()]);
}

//Helper function to create a menu item and give it an event. Useful because signal_connect doesn't return self.
//Note: This should possibly be changed to tie in with mainwsignals() - somehow.
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

int switchpage(object|mapping subw)
{
	if (objectp(subw)) {call_out(switchpage,0,tabs[notebook->get_current_page()]); return 0;} //Let the signal handler return before actually doing stuff
	subw->activity=0; notebook->set_tab_label_text(subw->page,subw->tabtext);
	subw->ef->grab_focus();
}

mapping(string:int) pos;
void configevent(object self,object ev)
{
	if (ev->type!="configure") return; //This wouldn't be needed if I could hook configure_event
	if (!pos) call_out(savepos,2); //Save 2 seconds after the window moved. "Sweep" movement creates a spew of these events, don't keep saving.
	pos=self->get_position(); //Will return x and y
}

void savepos()
{
	persist["window/winpos"]=({pos->x,pos->y});
	pos=0;
}

void mainwsignals()
{
	signals=({
		gtksignal(mainwindow,"destroy",window_destroy),
		gtksignal(mainwindow,"delete_event",window_destroy),
		gtksignal(defbutton,"clicked",enterpressed_glo),
		gtksignal(notebook,"switch_page",switchpage),
		gtksignal(mainwindow,"event",configevent), //Should be configure_event but not working
	});
}
