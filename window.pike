//GUI handler.

string buf="<tt><span foreground='white' background='black'>";
string prompt="";
GTK2.Label label;
GTK2.Adjustment scr;
GTK2.Entry ef;
GTK2.Button defbutton;
array signal;
array(string) cmdhist=({ });
int histpos=-1;
array(string) colors=({
	"black","dark red","dark green","#880","dark blue","dark magenta","dark cyan","grey",
	"dark grey","red","green","yellow","blue","magenta","cyan","white",
});

void saybouncer(string msg) {G->G->window->say(msg);} //Say, Bouncer, say!
void say(string msg)
{
	buf+=replace(msg,"<","&lt;")+"\n";
	redraw();
}

void say_raw(string msg)
{
	buf+=msg+"\n";
	redraw();
}
void redraw() {label->set_markup(buf+prompt+"</span></tt>");}

string mkcolor(int fg,int bg)
{
	return "</span><span"
		+ (fg!=-1 ? " foreground='"+colors[fg]+"'" : "")
		+ (bg!=-1 ? " background='"+colors[bg]+"'" : "") + ">";
}

void create(string name)
{
	if (!G->G->window)
	{
		add_constant("say",saybouncer);
		GTK2.setup_gtk();
		object mainwindow=G->G->mainwindow=GTK2.Window(GTK2.WindowToplevel);
		mainwindow->set_title("Gypsum")->set_default_size(800,500)->signal_connect("destroy",window_destroy);
		mainwindow->signal_connect("delete_event",window_destroy);
		GTK2.Widget maindisplay=GTK2.ScrolledWindow((["hadjustment":GTK2.Adjustment(),"vadjustment":scr=GTK2.Adjustment(),"background":"black"]))
			->add(label=GTK2.Label((["xalign":0,"yalign":0,"foreground":"white"])))
			->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_ALWAYS)
			->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(0,0,0));
		maindisplay->get_child()->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(0,0,0));
		defbutton=GTK2.Button()->set_size_request(0,0)->set_flags(GTK2.CAN_DEFAULT);
		mainwindow->add(GTK2.Vbox(0,0)
			->add(maindisplay)
			->pack_end(ef=GTK2.Entry(),0,0,0)
			->pack_end(defbutton,0,0,0)
		)->show_all();
		ef->grab_focus();
		mainwindow->set_default(defbutton); ef->set_activates_default(1);
		mainwindow->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(0,0,0));
		//maindisplay->get_child()->signal_connect("event",showev);
		//say("Hello, world!"); say("Red","red"); say("Blue on green","blue","green");
		scr->signal_connect("changed",lambda() {scr->set_value(scr->get_property("upper")-scr->get_property("page size"));});
		//scr->signal_connect("value_changed",lambda(mixed ... args) {write("value_changed: %O %O\n",scr->get_value(),scr->get_property("upper")-scr->get_property("page size"));});
	}
	else
	{
		object other=G->G->window;
		label=other->label; scr=other->scr; ef=other->ef; defbutton=other->defbutton; buf=other->buf;
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

int keypress(object self,array(object) ev)
{
	switch (ev[0]->keyval)
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
	histpos=-1; if (!sizeof(cmdhist) || cmd!=cmdhist[-1]) cmdhist+=({cmd});
	buf+=prompt+replace(cmd,"<","&lt;")+"\n";
	if (sizeof(cmd)>1 && cmd[0]=='/' && cmd[1]!='/')
	{
		redraw();
		sscanf(cmd,"/%[^ ] %s",cmd,string args);
		if (G->G->command[cmd] && G->G->command[cmd](args||"")) return 0;
		say("%% Unknown command.");
		return 0;
	}
	prompt=""; redraw();
	G->G->sock->write(cmd+"\r\n");
	return 1;
}
