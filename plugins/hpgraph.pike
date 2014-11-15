constant docstring=#"
Show a graphical representation of your hitpoints, on the status bar.

Displays vibrantly when you see your hitpoints; fades away after a while.

Tracks status separately for each subwindow.
";

inherit hook;
inherit statustext;

int barwidth=persist["hpgraph/barwidth"] || 100; //Number of pixels. Larger takes up more space but gives better resolution.
int fadedelay=persist["hpgraph/fadedelay"] || 60; //Number of seconds after update that the display fades
int fadespeed=persist["hpgraph/fadespeed"] || 8; //Speed of fade - each second (after fadedelay), this gets added to the color, capped at 255 (faded to white).
//Currently the colors must be either 255 or 0 (the latter becomes the fade level).
//Putting any other value in (not possible with the config) will cause odd
//interactions with the fade-to-white, so just don't do it. :) TODO: Should this
//use setdefault() to ensure that there's always at least something in persist?
array barcolors=persist["hpgraph/barcolors"] || ({
	({255,0,0}),
	({0,255,0}),
	({0,255,255}),
});

//TODO: Incorporate the timer.pike code for tick-downs - if they can overlay the bands, that would be great.

//Stashes some info in subw->hpgraph as an array:
//({fadetime, hp, sp, ep})
//fadetime: time() when fading should begin. If in the distant past, image is white; if in the future, is fresh and completely solid.
//hp, sp, ep: 0.0 <= x <= 1.0 for the proportion of the bar that should be colored.

int outputhook(string line,mapping(string:mixed) conn)
{
	int chp,mhp,csp,msp,cep,mep;
	array hpg=conn->display->hpgraph;
	if (sscanf(line,"%*sHP [ %d/%d ]     SP [ %d/%d ]     EP [ %d/%d ]",chp,mhp,csp,msp,cep,mep)==7)
	{
		conn->display->hpgraph=({time()+fadedelay,chp/(float)mhp,csp/(float)msp,cep/(float)mep});
		if (conn->display==G->G->window->current_subw()) tick(); //If we changed current status, redraw immediately.
	}
	else if (hpg && line=="You are completely healed.") hpg[1]=1.0;
	else if (hpg && line=="You sizzle with mystical energy.") hpg[2]=1.0;
	else if (hpg && line=="Your body has recuperated.") hpg[3]=1.0;
}

GTK2.Widget makestatus()
{
	statustxt->bars=({GTK2.EventBox(),GTK2.EventBox(),GTK2.EventBox()});
	return GTK2.Hbox(0,10)->add(statustxt->lbl=GTK2.Label("HP:"))->add(statustxt->vbox=GTK2.EventBox()->add(GTK2.Vbox(1,0)
		->add(GTK2.Hbox(0,0)->pack_start(statustxt->bars[0],0,0,0))
		->add(GTK2.Hbox(0,0)->pack_start(statustxt->bars[1],0,0,0))
		->add(GTK2.Hbox(0,0)->pack_start(statustxt->bars[2],0,0,0))
	)->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(255,255,255)));
}

void tick()
{
	if (statustxt->ticker) remove_call_out(statustxt->ticker);
	statustxt->ticker=call_out(this_function,1);
	mapping subw=G->G->window->current_subw();
	array hpg=subw->hpgraph || ({0,0,0,0});
	int lvl=limit(0,fadespeed*(time()-hpg[0]),255);
	foreach (barcolors;int i;array col)
		statustxt->bars[i]->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(@(col[*]|lvl)))->set_size_request(limit(0,(int)(barwidth*hpg[i+1]),barwidth),-1);
}

class config
{
	inherit window;
	void create() {::create();}

	array(GTK2.Widget) color(array(string) names)
	{
		array(GTK2.Widget) ret=({ });
		foreach (names;int i;string n) ret+=({
			win["colorbar"+i]=GTK2.EventBox()->add(GTK2.Label(n+" bar color"))->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(@barcolors[i])),
			GTK2.Hbox(0,10)
				->add(win["color0"+i]=GTK2.CheckButton("Red")->set_active(barcolors[i][0]==255))
				->add(win["color1"+i]=GTK2.CheckButton("Green")->set_active(barcolors[i][1]==255))
				->add(win["color2"+i]=GTK2.CheckButton("Blue")->set_active(barcolors[i][2]==255))
		});
		return ret;
	}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Graphical HP display"]))->add(GTK2.Vbox(0,0)
			->add(two_column(({
				"Bar width",win->barwidth=GTK2.Entry()->set_text((string)barwidth),
				"Fade delay (secs)",win->fadedelay=GTK2.Entry()->set_text((string)fadedelay),
				"Fade speed (256=instant)",win->fadespeed=GTK2.Entry()->set_text((string)fadespeed),
			})+color(({"HP","SP","EP"}))))
			->add(GTK2.HbuttonBox()
				->add(win->pb_ok=GTK2.Button("OK"))
				->add(stock_close())
			)
		);
		::makewindow();
	}

	void update_color(object self,int bar)
	{
		win["colorbar"+bar]->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(
			win["color0"+bar]->get_active() && 255,
			win["color1"+bar]->get_active() && 255,
			win["color2"+bar]->get_active() && 255,
		));
	}

	void dosignals()
	{
		::dosignals();
		foreach (barcolors;int i;array(int) col) foreach (col;int j;)
			win->signals+=({gtksignal(win["color"+j+i],"clicked",update_color,i)});
	}

	void sig_pb_ok_clicked()
	{
		int newwidth = (int)win->barwidth->get_text() || 100;
		if (newwidth!=barwidth) statustxt->vbox->set_size_request(persist["hpgraph/barwidth"]=barwidth=newwidth,-1);
		fadedelay = persist["hpgraph/fadedelay"] = (int)win->fadedelay->get_text() || 60;
		fadespeed = persist["hpgraph/fadespeed"] = (int)win->fadespeed->get_text() || 8;
		foreach (barcolors;int i;array(int) col) foreach (col;int j;)
			col[j]=win["color"+j+i]->get_active() && 255;
		persist["hpgraph/barcolors"]=barcolors;
		tick(); //Don't wait another second
		closewindow();
	}
}

void mousedown(object self,object ev)
{
	if (ev->type=="2button_press") config();
}

void create(string name)
{
	statustxt->tooltip="Graphical HP display - double-click to configure";
	::create(name);
	//The condition is compat code for 1fc03f and earlier
	//The name "vbox" is now outdated (20141102) as it's actually another EventBox, and it now
	//covers the background. At some point it's probably worth making a breaking change to
	//rename it, but it'll still need to have its width set on startup, in case the persist
	//value got changed out from under us.
	if (statustxt->vbox) statustxt->vbox->set_size_request(barwidth,-1);
	//Compat for d6bfa9 and earlier
	if (statustxt->hp) statustxt->bars=({statustxt->hp,statustxt->sp,statustxt->ep});
	statustxt->signals=({gtksignal(statustxt->vbox,"button_press_event",mousedown)});
	tick();
}
