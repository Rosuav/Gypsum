#!/usr/bin/env pike
#if constant(G)
inherit hook;
inherit command;
inherit movablewindow;
inherit plugin_menu;

/* TODO: Document me properly somewhere.

To set up for Threshold RPG regeneration timers, create three timers with the
special keywords " HP", " SP" (yes, they begin with a space each), and ".EP"
(yes, that's a period/full stop). Set their times to your corresponding regen
rates, and leave the text blank. Then let the magic happen. :) */

int regenclick; //Doesn't need to be retained; it doesn't make a lot of difference if it's wrong, but can be convenient. For Threshold RPG hp/sp/ep markers.
constant pos_key="timer/winpos";

mapping(string:mapping(string:mixed)) timers=persist["timer/timers"] || ([]);

int resolution=persist["timer/resolution"] || 10; //Higher numbers for more stable display, lower numbers for finer display. Minimum 1 - do not set to 0 or you will bomb the display :)

/**
 * Format an integer seconds according to a base value. The base ensures that the display is stable as the time ticks down.
 *
 * @param 	delay 	the integer to be formated
 * @param 	base	a value that determines if the integer is formatted to sec, min, hour
 * @return 	string	the formatted integer value
 */
string format_time(int delay,int base)
{
	/*
	Open question: Is it better to show 60 seconds as "60" or as "01:00"?
	Previously, this would show it as 60 (unless it's ticking down from a longer time, of course),
	but this makes HP/SP/EP display - which can't know what they're ticking down from - to look
	a bit odd. Changing it 20140117 to show as 01:00. Question is still open as to how it ought
	best to be done. There are arguments on both sides.
	*/
	delay-=delay%resolution;
	if (delay<=0) return "";
	switch (max(delay,base))
	{
		case 0..59: return sprintf("%02d",delay);
		case 60..3599: return sprintf("%02d:%02d",delay/60,delay%60);
		default: return sprintf("%02d:%02d:%02d",delay/3600,(delay/60)%60,delay%60);
	}
}


class config
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Configure timers","modal":1]);
	void create() {items=timers; ::create("plugins/timer"); showwindow();}

	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10)
			->pack_start(two_column(({
				"Keyword",win->kwd=GTK2.Entry(),
				"Time",win->time=GTK2.Entry(),
				"",win->present=GTK2.CheckButton("Present when done"),
			})),0,0,0)
			->pack_start(GTK2.Frame("Trigger text")->add(
				win->trigger=MultiLineEntryField((["buffer":GTK2.TextBuffer(),"wrap-mode":GTK2.WRAP_WORD_CHAR]))->set_size_request(250,70)
			),1,1,0);
	}

	void load_content(mapping(string:mixed) info)
	{
		win->time->set_text(format_time(info->time,info->time));
		win->trigger->get_buffer()->set_text(info->trigger || "");
		win->present->set_active(info->present);
	}

	void save_content(mapping(string:mixed) info)
	{
		int tm=0; foreach ((array(int))(win->time->get_text()/":"),int part) tm=tm*60+part; info->time=tm;
		info->trigger=win->trigger->get_text();
		info->present=win->present->get_active();
		persist["timer/timers"]=timers;
		makelabels();
	}

	void delete_content(string kwd,mapping(string:mixed) info)
	{
		persist["timer/timers"]=timers;
		makelabels();
	}
}

constant menu_label="Timer";
void menu_clicked() {config();}

int outputhook(string line,mapping(string:mixed) conn)
{
	if (sscanf(line,"%*sHP [ %d/%d ]     SP [ %d/%d ]     EP [ %d/%d ]",int chp,int mhp,int csp,int msp,int cep,int mep) && mep)
	{
		mapping hp=timers[" HP"],sp=timers[" SP"],ep=timers[".EP"];
		int t=time(1);
		int ofs=(regenclick-t)%22;
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
 * Update display of countdowns
 */
void showtimes()
{
	remove_call_out(win->ticker); win->ticker=call_out(this_function,1);
	foreach (sort(indices(timers));int i;string kwd)
	{
		mapping tm=timers[kwd]; if (!tm->next) continue;
		string time=format_time(tm->next-time(1),tm->time);
		win->timers[i]->set_text(time);
		if (time=="") {tm->next=0; if (tm->present) G->G->window->mainwindow->present();}
	}
}

/**
 * Creates the timer labels to be displayed on the timer window
 */
void makelabels()
{
	win->display->resize(sizeof(timers)||1,2,0);
	if (win->labels) ({win->labels,win->timers})->destroy(); //Clean out the trash - not sure if necessary (they shouldn't refleak AFAIK)
	win->labels=GTK2.Label(sort(indices(timers))[*])->set_alignment(0.0,0.0); win->timers=allocate(sizeof(timers));
	foreach (win->labels;int i;object lbl)
		win->display->attach_defaults(lbl,0,1,i,i+1)
		->attach_defaults(win->timers[i]=GTK2.Label("")->set_alignment(1.0,0.0),1,2,i,i+1);
	win->display->set_col_spacings(4)->show_all();
	showtimes();
	if (sizeof(timers)==1) win->mainwindow->set_no_show_all(0)->show_all();
}

void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Timers","transient-for":G->G->window->mainwindow,"no-show-all":!sizeof(timers)]))
		->add(win->display=GTK2.Table((["row-spacing":2,"col-spacing":8])));
	makelabels();
	::makewindow();
}

void mousedown(object self,object ev)
{
	if (ev->type=="2button_press") config(); //aka double-click (not right-click, not chord)
	else self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
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

void create(string name)
{
	::create(name);
	showtimes();
}
#else
//This file is executable, as a means of saving (to the console).
//Reads directly from .gypsumrc so it can be used whether Gypsum's running or not.
//Suitable for remote execution eg via SSH
mapping G=(["G":([])]);
mapping persist=decode_value(Stdio.read_file(combine_path(__FILE__,"..","..",".gypsumrc"))) || ([]);
mapping(string:mapping(string:mixed)) timers=persist["timer/timers"] || ([]);
void config() {}
void showtimes() {}
void say(mapping|void subw,string msg) {write("%s\n",msg);}
void send(mapping dest,string msg) {/* Not needed */}
int main() {process("save",0);}
#endif

int process(string param,mapping(string:mixed) subw)
{
	if (param=="dlg") {config(); return 1;}
	//TODO: Way to explicitly trigger a timer, especially one starting in the past
	//For instance, it should be possible to create a new timer and ask that it be
	//started as at the most recent string that matches it (that one's easy enough
	//to do); but also, it'd be great to have a one-off timer that has custom time
	//and description, starting in the past.
	if (param=="save" || sscanf(param,"save %s",string pfx))
	{
		string data="";
		foreach (timers;string kwd;mapping info) if (info->next && info->next>time(1))
			data+=sprintf("%q=%d",kwd,info->next);
		if (pfx) send(subw->connection,pfx+" "+data+"\r\n");
		else say(subw,"%% "+data);
		return 1;
	}
	if (sscanf(param,"load %s",string data))
	{
		sscanf(param,"%{%O=%d%}",array(array(string|int)) data);
		foreach (data,[string kwd,int next])
			if (timers[kwd]) timers[kwd]->next=next;
		persist["timer/timers"]=timers;
		showtimes();
		say(subw,"%% Loaded.");
		return 1;
	}
}
