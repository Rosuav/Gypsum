inherit hook;
inherit command;
inherit window;

/* TODO: Document me properly somewhere.

To set up for Threshold RPG regeneration timers, create three timers with the
special keywords " HP", " SP" (yes, they begin with a space each), and ".EP"
(yes, that's a period/full stop). Set their times to your corresponding regen
rates, and leave the text blank. Then let the magic happen. :) */

int regenclick; //Doesn't need to be retained; it doesn't make a lot of difference if it's wrong, but can be convenient. For Threshold RPG hp/sp/ep markers.

mapping(string:mapping(string:mixed)) timers=persist["timer/timers"] || ([]);

int resolution=persist["timer/resolution"] || 10; //Higher numbers for more stable display, lower numbers for finer display. Minimum 1 - do not set to 0 or you will bomb the display :)

/**
 * Format an integer seconds according to a base value. The base ensures that the display is stable as the time ticks down.
 *
 * @param 	delay 	the integet to be formated
 * @param 	base	a value that determines if the integet is formated to sec, min, hour
 * @return 	string	the formated integer value	
 */
string format_time(int delay,int base)
{
	delay-=delay%resolution;
	if (delay<=0) return "";
	switch (max(delay,base))
	{
		case 0..60: return sprintf("%02d",delay);
		case 61..3599: return sprintf("%02d:%02d",delay/60,delay%60); //1 minute can be shown as 60 seconds, even though 1 hour is 01:00:00.
		default: return sprintf("%02d:%02d:%02d",delay/3600,(delay/60)%60,delay%60);
	}
}


class config
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Configure timers","modal":1]);
	
	/**
	 * Loads the contents to be configured
	 *
	 * @param info	The information to be loaded
	 */ 
	void create() {items=timers; ::create("plugins/timer"); showwindow();}
	
	/**
	 * Loads the contents to be configured
	 *
	 * @param info	The information to be loaded
	 */ 
	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10)
			->pack_start(GTK2.Table(2,2,0)
				->attach(GTK2.Label((["label":"Keyword","xalign":1.0])),0,1,0,1,GTK2.Fill,GTK2.Fill,5,0)
				->attach_defaults(win->kwd=GTK2.Entry(),1,2,0,1)
				->attach(GTK2.Label((["label":"Time","xalign":1.0])),0,1,2,3,GTK2.Fill,GTK2.Fill,5,0)
				->attach_defaults(win->time=GTK2.Entry(),1,2,2,3)
				/*->attach(GTK2.Label((["label":"Options","xalign":1.0])),0,1,3,4,GTK2.Fill,GTK2.Fill,5,0)
				->attach_defaults(win->some_checkbox=GTK2.CheckButton(),1,2,3,4)*/
			,0,0,0)
			->pack_start(GTK2.Frame("Trigger text")->add(
				win->trigger=GTK2.TextView((["buffer":GTK2.TextBuffer(),"wrap-mode":GTK2.WRAP_WORD_CHAR]))->set_size_request(250,70)
			),1,1,0);
	}
	
	/**
	 * Loads the contents to be configured
	 *
	 * @param info	The information to be loaded
	 */ 
	void load_content(mapping(string:mixed) info)
	{
		win->time->set_text(format_time(info->time,info->time));
		win->trigger->get_buffer()->set_text(info->trigger || "");
	}
	
	/**
	 * Saves the configured values
	 *
	 * @param info	 mapping to which timer values are saved. (Also saved to persist)
	 */	
	void save_content(mapping(string:mixed) info)
	{
		int tm=0; foreach ((array(int))(win->time->get_text()/":"),int part) tm=tm*60+part; info->time=tm;
		info->trigger=get_text(win->trigger);
		persist["timer/timers"]=timers;
		makelabels();
	}
}

/**
 * TODO: Finish function
 *
 */
int process(string param,mapping(string:mixed) subw)
{
	if (param=="dlg") {config(); return 1;}
	//TODO: Way to explicitly trigger a timer
}

/**
 * Collects and parses the output from a connected world
 *
 * @param 	line 	The line to be parsed
 * @param 	conn	The connection to which the line has been collected.
 * @return 	int		always returns zero
 */
int outputhook(string line,mapping(string:mixed) conn)
{
	if (sscanf(line,"%sHP [ %d/%d ]     SP [ %d/%d ]     EP [ %d/%d ]",string prefix,int chp,int mhp,int csp,int msp,int cep,int mep) && mep)
	{
		mapping hp=timers[" HP"],sp=timers[" SP"],ep=timers[".EP"];
		int t=time(1);
		int ofs=22-(t-regenclick)%22;
		if (ofs==22 && (prefix=="" || has_suffix(prefix,": "))) ofs=0; //When in battle, the spam comes up before regen kicks in. So in the precise tick when the regen happens, Timer will show regen times 22 seconds too high.
		if (hp && hp->time) hp->next = t + (chp<mhp && (mhp-chp-1)/hp->time*22+ofs);
		if (sp && sp->time) sp->next = t + (csp<msp && (msp-csp-1)/sp->time*22+ofs);
		if (ep && ep->time) ep->next = t + (cep<mep && (mep-cep-1)/ep->time*22+ofs);
		showtimes();
		return 0;
	}
	if ((<"Your body has recuperated.","You are completely healed.","You sizzle with mystical energy.">)[line]) regenclick=time(1);
	foreach (sort(indices(timers));int i;string kwd)
	{
		mapping tm=timers[kwd];
		if (tm->trigger!="" && has_value(line,tm->trigger))
		{
			tm->next=time(1)+tm->time;
			win->timers[i]->set_text(format_time(tm->next-time(1),tm->time));
			persist["timer/timers"]=timers;
		}
	}
}

/**
 * Updates the window with and in doing so refeshes the timer values.
 *
 */
void showtimes()
{
	remove_call_out(win->ticker); win->ticker=call_out(this_function,1);
	foreach (sort(indices(timers));int i;string kwd)
		win->timers[i]->set_text(format_time(timers[kwd]->next-time(1),timers[kwd]->time));
}

/**
 * Creates the timer labels to be displayed on the timer window
 *
 */
void makelabels()
{
	win->display->resize(sizeof(timers)+1,2,0);
	if (win->labels) ({win->labels,win->timers,win->dblclk})->destroy(); //Clean out the trash - not sure if necessary (they shouldn't refleak AFAIK)
	win->labels=GTK2.Label(sort(indices(timers))[*])->set_alignment(0.0,0.0); win->timers=allocate(sizeof(timers));
	foreach (win->labels;int i;object lbl)
		win->display->attach_defaults(lbl,0,1,i,i+1)
		->attach_defaults(win->timers[i]=GTK2.Label("")->set_alignment(1.0,0.0),1,2,i,i+1);
	win->display->attach_defaults(win->dblclk=GTK2.Label("(Dbl-click to set)"),0,2,sizeof(timers),sizeof(timers)+1)->show_all();
	showtimes();
}

/**
 * Creates the timer window.
 *
 */
void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Timers","transient-for":G->G->window->mainwindow]))
		->add(win->display=GTK2.Table((["row-spacing":2,"col-spacing":5])));
	makelabels();
	int x,y=150; catch {[x,y]=persist["timer/winpos"];};
	win->x=1; call_out(lambda() {m_delete(win,"x");},1);
	win->mainwindow->move(x,y);
}

/**
 * Catches events and if it is a configure event adjust the screen position of the window.
 *
 */
void configevent(object self,object ev)
{
	if (ev->type!="configure") return;
	if (!has_index(win,"x")) call_out(savepos,2);
	mapping pos=self->get_position(); win->x=pos->x; win->y=pos->y;
}

/**
 * Saves the adjusted window potion to persist.
 *
 */
void savepos()
{
	persist["timer/winpos"]=({m_delete(win,"x"),m_delete(win,"y")});
}

/**
 * Catches the mouse down event, and if it is a 2-button moust down event begins moves the window.
 *
 * @param self	the object to be moved
 * @param ev	the event that has occured.
 */
void mousedown(object self,object ev)
{
	if (ev->type=="2button_press") config(); //aka double-click (not right-click, not chord)
	else self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
}

/**
 * Establishes event handlers for the event, and button_press_event events.
 *
 */
void dosignals()
{
	win->signals=({
		gtksignal(win->mainwindow,"event",configevent),
		gtksignal(win->mainwindow,"button_press_event",mousedown),
		gtksignal(win->mainwindow,"delete_event",hidewindow),
	});
	win->mainwindow->add_events(GTK2.GDK_BUTTON_PRESS_MASK);
}

/**
 * Creates and instance of this class.
 *
 * @param name	The name of the instance of this class.
 */
void create(string name)
{
	::create(name);
	showtimes();
}
