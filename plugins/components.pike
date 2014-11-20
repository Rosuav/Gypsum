inherit hook;
inherit movablewindow;

constant docstring=#"
For Threshold RPG: keep track of your currently-held components in a separate window.

Currently works only for mages. Could later be extended to support more guilds; need
a volunteer to check the texts.
";

//Persist key chosen to allow separate components display for alchies. This may or may not be useful.
//It might be worth having two or three of these, and any which have content will be displayed in
//columns. So if (sizeof(components/mage)), the mage components run down the line (there are 16, I
//think); and if (sizeof(components/alchemist)), correspondingly (maybe in two cols as there are 30).
mapping(string:mapping(string:mixed)) components=persist->setdefault("components/mage",([]));

void setcount(string name,int cnt)
{
	persist->save(); //A bit naughty - trigger the save before making the change. It's done by a call_out anyway.
	if (mapping cm=components[name]) {cm->curcount=cnt; showcounts(); return;} //Easy
	//Make a new one.
	components[name]=(["curcount":cnt]);
	makelabels();
}

int outputhook(string line,mapping(string:mixed) conn)
{
	if (string partial=m_delete(conn,"components/partial")) line=partial+" "+String.trim_all_whites(line);
	if (String.trim_all_whites(line)=="Carried Spell Components") conn["components/watch"]=1;
	else if (conn["components/watch"])
	{
		if (sscanf(line,"%*[ ]You can conjure a maximum of %d at a time.",int max) && max) conn["components/watch"]=0;
		else if (sscanf(line,"%{%*[ ]%s: %d%}",array info)) foreach (info,[string name,int cnt])
			setcount(lower_case(name),cnt);
	}
	if (sscanf(line,"You complete the spell of conjuration and add some %s to your spell component pouch. You now have %d.",string name,int cnt))
		setcount(name,cnt);
	else if (has_prefix(line,"You complete the spell of conjuration") && sizeof(line)<200) conn["components/partial"]=line;
	//Note that after a few lines (200 characters total), it'll just give up and try again next time.
}

void showcounts()
{
	foreach (sort(indices(components));int i;string kwd)
	{
		mapping cm=components[kwd];
		win->counts[i]->set_text((string)cm->curcount);
		//TODO maybe: Highlight full and/or low (where "low" is defined as "less than N", which may vary for different components)
	}
}

void makelabels()
{
	win->display->resize(sizeof(components)||1,2,0);
	if (win->labels) ({win->labels,win->counts})->destroy(); //Clean out the trash - not sure if necessary (they shouldn't refleak AFAIK)
	win->labels=GTK2.Label(sort(indices(components))[*])->set_alignment(0.0,0.0);
	if (!sizeof(win->labels)) win->labels=({GTK2.Label("(no components known yet)")});
	win->counts=allocate(sizeof(win->labels));
	foreach (win->labels;int i;object lbl)
		win->display->attach_defaults(lbl,0,1,i,i+1)
		->attach_defaults(win->counts[i]=GTK2.Label("")->set_alignment(1.0,0.0),1,2,i,i+1);
	win->display->set_col_spacings(4)->show_all();
	showcounts();
}

void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Components"]))
		->add(win->display=GTK2.Table((["row-spacing":2,"col-spacing":8])));
	makelabels();
	::makewindow();
}

void sig_mainwindow_button_press_event(object self,object ev)
{
	if (ev->type=="2button_press") return; //aka double-click (not right-click, not chord)
	self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
}

void dosignals()
{
	::dosignals();
	win->signals+=({
		gtksignal(win->mainwindow,"delete_event",hidewindow),
	});
	win->mainwindow->add_events(GTK2.GDK_BUTTON_PRESS_MASK);
}

void create(string name) {::create(name); showcounts();}
