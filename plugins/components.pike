inherit hook;
inherit movablewindow;

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
	else if (has_prefix(line,"You complete the spell of conjuration")) conn["components/partial"]=line;
}

void showcounts()
{
	foreach (sort(indices(components));int i;string kwd)
	{
		mapping cm=components[kwd];
		win->counts[i]->set_text((string)cm->curcount);
		//TODO maybe: Highlight full/empty (and "empty" might be defined as "less than N")
	}
}

void makelabels()
{
	win->display->resize(sizeof(components)||1,2,0);
	if (win->labels) ({win->labels,win->counts})->destroy(); //Clean out the trash - not sure if necessary (they shouldn't refleak AFAIK)
	win->labels=GTK2.Label(sort(indices(components))[*])->set_alignment(0.0,0.0); win->counts=allocate(sizeof(components));
	foreach (win->labels;int i;object lbl)
		win->display->attach_defaults(lbl,0,1,i,i+1)
		->attach_defaults(win->counts[i]=GTK2.Label("")->set_alignment(1.0,0.0),1,2,i,i+1);
	win->display->set_col_spacings(4)->show_all();
	showcounts();
}

void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Components","transient-for":G->G->window->mainwindow]))
		->add(win->display=GTK2.Table((["row-spacing":2,"col-spacing":8])));
	makelabels();
	::makewindow();
}

void mousedown(object self,object ev)
{
	if (ev->type=="2button_press") return; //aka double-click (not right-click, not chord)
	self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
}

void dosignals()
{
	::dosignals();
	win->signals+=({
		gtksignal(win->mainwindow,"button_press_event",mousedown),
		gtksignal(win->mainwindow,"delete_event",hidewindow),
	});
	win->mainwindow->add_events(GTK2.GDK_BUTTON_PRESS_MASK);
}

void create(string name) {::create(name); showcounts();}
