constant docstring=#"
Show a graphical representation of your hitpoints, on the status bar.

Displays vibrantly when you see your hitpoints; fades away after a while.

Tracks status separately for each subwindow.
";

inherit hook;
inherit statustext;

//TODO: Make a configdlg.
int barwidth=persist["hpgraph/barwidth"] || 100; //Number of pixels. Larger takes up more space but gives better resolution.
int fadedelay=persist["hpgraph/fadedelay"] || 60; //Number of seconds after update that the display fades
int fadespeed=persist["hpgraph/fadespeed"] || 8; //Speed of fade - each second (after fadedelay), this gets added to the color, capped at 255 (faded to white).

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
	return GTK2.Hbox(0,10)->add(statustxt->lbl=GTK2.Label("HP:"))->add(statustxt->vbox=GTK2.EventBox()->add(GTK2.Vbox(1,0)
		->add(GTK2.Hbox(0,0)->pack_start(statustxt->hp=GTK2.EventBox(),0,0,0))
		->add(GTK2.Hbox(0,0)->pack_start(statustxt->sp=GTK2.EventBox(),0,0,0))
		->add(GTK2.Hbox(0,0)->pack_start(statustxt->ep=GTK2.EventBox(),0,0,0))
	)->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(255,255,255)));
}

void tick()
{
	if (statustxt->ticker) remove_call_out(statustxt->ticker);
	statustxt->ticker=call_out(this_function,1);
	mapping subw=G->G->window->current_subw();
	array hpg=subw->hpgraph || ({0,0,0,0});
	int lvl=limit(0,fadespeed*(time()-hpg[0]),255);
	statustxt->hp->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(255,lvl,lvl))->set_size_request(limit(0,(int)(barwidth*hpg[1]),barwidth),-1);
	statustxt->sp->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(lvl,255,lvl))->set_size_request(limit(0,(int)(barwidth*hpg[2]),barwidth),-1);
	statustxt->ep->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(lvl,255,255))->set_size_request(limit(0,(int)(barwidth*hpg[3]),barwidth),-1);
}

void create(string name)
{
	::create(name);
	//The condition is compat code for 1fc03f and earlier
	//The name "vbox" is now outdated (20141102) as it's actually another EventBox, and it now
	//covers the background. At some point it's probably worth making a breaking change to
	//rename it, but it'll still need to have its width set here - or anywhere else that the
	//barwidth can be changed.
	if (statustxt->vbox) statustxt->vbox->set_size_request(barwidth,-1);
	tick();
}
