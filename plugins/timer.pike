#!/usr/bin/env pike
#if constant(G)
inherit hook;
inherit command;
inherit movablewindow;
inherit plugin_menu;

constant docstring=#"
Track ticking-down timers (in a separate window)

Whenever a line of text matches a timer's trigger, that timer is reset, and will
tick down from a pre-set time until it reaches zero and blanks out. This can
optionally result in the Gypsum window being presented to the user, to highlight
the timer's expiration.
";

/* TODO: Document me properly somewhere.

To set up for Threshold RPG regeneration timers, create three timers with the
special keywords " HP", " SP" (yes, they begin with a space each), and ".EP"
(yes, that's a period/full stop). Set their times to your corresponding regen
rates, and leave the text blank. Then let the magic happen. :) */

/* TODO maybe: "Hide when done" timers. They're visible only while they tick
down. You can have piles and piles of them and they sit there quietly until
one of them actually gets hit. */

/* TODO: "Highlight when zero" timers. They'll need to go into EventBoxes, and
they go to normal color whenever the time is nonzero, and to a highlight color
when they're blank. Good for the ones that are normally nonzero. (This may mean
it's simpler to put *all* timers into EventBoxes, but that'd be less efficient,
so better to not.) */

/* TODO: Per-world timers. They'll exist for all worlds, but retain
separate countdown times based on current_subw()->world. Hmm. Also may need
separate delays for separate worlds, which will be UI-messy. And they'll have
to respect "present when done" (incl presnext) regardless of current subw.
The display could make use of 'inherit tabstatus'; but what about config? */

/* TODO: Advanced mode. More complicated triggers (eg sscanf or regex patterns)
and the ability to start *or stop* a timer on any line. Or maybe this should
simply expose an API??? There's absolutely no precedent for one plugin offering
an API to other plugins, but it could be pretty handy. */

constant pos_key="timer/winpos";

mapping(string:mapping(string:mixed)) timers=persist->setdefault("timer/timers",([]));

int resolution=persist["timer/resolution"] || 10; //Higher numbers for more stable display, lower numbers for finer display.

class config
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Configure timers","modal":1]);
	constant persist_key="timer/timers";
	constant elements=({"kwd:Keyword", "Time", "?Present when done", "+Trigger text"});

	void load_content(mapping(string:mixed) info)
	{
		win->time->set_text(format_time(info->time,info->time,resolution));
	}

	void save_content(mapping(string:mixed) info)
	{
		//TODO: What should a multi-line trigger mean? Options? Multiple consecutive lines?
		//For now, just replace newline with space, so it at least makes plausible sense.
		info->trigger=replace(String.trim_all_whites(info->trigger),"\n"," ");
		int tm=0; foreach ((array(int))(win->time->get_text()/":"),int part) tm=tm*60+part; info->time=tm;
		makelabels();
	}

	void delete_content(string kwd,mapping(string:mixed) info)
	{
		makelabels();
	}
}

constant menu_label="Timer";
void menu_clicked() {config();}

int output(mapping(string:mixed) subw,string line)
{
	//NOTE: A bug was reported wherein this was attempting to index an empty array with
	//0. This MAY have something to do with loading up with no timers and then adding
	//one; unloading and reloading the plugin appeared to fix it. Or it may have been a
	//simple case of operator error. Unconfirmed. CJA 20150606: How could it even do that?
	if (sscanf(line,"%*sHP [ %d/%d ]%*[ ]SP [ %d/%d ]%*[ ]EP [ %d/%d ]",int chp,int mhp,int csp,int msp,int cep,int mep) && mep)
	{
		//This won't be needed once FluffOS Threshold is the only Threshold.
		mapping hp=timers[" HP"],sp=timers[" SP"],ep=timers[".EP"];
		int t=time(1);
		int tick = subw->regentick || 22;
		int ofs=(subw->regenclick-t)%tick || tick;
		if (hp && hp->time) hp->next = t + (chp<mhp && (mhp-chp-1)/hp->time*tick+ofs);
		if (sp && sp->time) sp->next = t + (csp<msp && (msp-csp-1)/sp->time*tick+ofs);
		if (ep && ep->time) ep->next = t + (cep<mep && (mep-cep-1)/ep->time*tick+ofs);
		#ifdef DEBUG_REGEN_TIMER
		string last = subw->lastvitals ? sprintf(" (%ds)", t - subw->lastvitals) : "";
		subw->lastvitals = t;
		say(subw, "%%%% SP %d/%d -> %d (+%d)%s", csp, msp, sp->next, sp->next - t, last);
		#endif
		showtimes();
		return 0;
	}
	if ((<"Your body has recuperated.","You are completely healed.","You sizzle with mystical energy.">)[line]) subw->regenclick=time(1);
	foreach (sort(indices(timers));int i;string kwd)
	{
		mapping tm=timers[kwd];
		if (tm->trigger!="" && has_value(line,tm->trigger))
		{
			tm->next=time(1)+tm->time;
			if (m_delete(tm,"presnext")) G->G->window->mainwindow->present();
			win->timers[i]->set_text(format_time(tm->next-time(1),tm->time,resolution));
			persist->save();
		}
	}
}

int gmcp_message(mapping(string:mixed) subw, string cmd, mixed data) {
	switch (cmd) {
		case "Char.Vitals": {
			mapping hp=timers[" HP"], sp=timers[" SP"], ep=timers[".EP"];
			data = subw->char_vitals = (subw->char_vitals||([])) | (mapping(string:int))data;
			int chp = data->hp, mhp = data->maxhp;
			int csp = data->sp, msp = data->maxsp;
			int cep = data->ep, mep = data->maxep;
			int t = time(1);
			int tick = subw->regentick || 20; //Old Threshold has it every 22 seconds; new Threshold announces it (and it's currently 20).
			int ofs = (subw->regenclick - t) % tick || tick;
			if (hp && hp->time) hp->next = t + (chp<mhp && (mhp-chp-1)/hp->time*tick+ofs);
			if (sp && sp->time) sp->next = t + (csp<msp && (msp-csp-1)/sp->time*tick+ofs);
			if (ep && ep->time) ep->next = t + (cep<mep && (mep-cep-1)/ep->time*tick+ofs);
			#ifdef DEBUG_REGEN_TIMER
			string last = subw->lastvitals ? sprintf(" (%ds)", t - subw->lastvitals) : "";
			subw->lastvitals = t;
			say(subw, "%%%% SP %d/%d -> %d (+%d)%s", csp, msp, sp->next, sp->next - t, last);
			#endif
			showtimes();
			break;
		}
		case "Char._Tick": subw->regenclick = time(1); subw->regentick = (int)data; break;
		default: break;
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
		int t=tm->next-time(1); if (!tm->time) t=-t;
		string time=format_time(t,tm->time,resolution);
		win->timers[i]->set_text(time);
		if (time=="" && tm->time) {tm->next=0; if (m_delete(tm,"presnext") || tm->present) G->G->window->mainwindow->present();}
	}
}

/**
 * Creates the timer labels to be displayed on the timer window
 */
void makelabels()
{
	win->display->resize(sizeof(timers)||1,2,0);
	if (win->labels)
	{
		//Clean out the trash - not sure if necessary (they shouldn't refleak AFAIK)
		//CJA 20160720: Maybe they do? I'm seeing progressively-increasing numbers of
		//leaked GTK2.Label objects, resulting in crazy memory usage. Explicitly
		//destroying and destructing the objects doesn't seem to stop this though.
		array objects = win->labels + win->timers;
		objects->destroy();
		destruct(objects[*]);
	}
	win->labels=GTK2.Label(sort(indices(timers))[*])->set_alignment(0.0,0.0); win->timers=allocate(sizeof(timers));
	foreach (win->labels;int i;object lbl)
		win->display->attach_defaults(lbl,0,1,i,i+1)
		->attach_defaults(win->timers[i]=GTK2.Label("")->set_alignment(1.0,0.0),1,2,i,i+1);
	win->display->set_col_spacings(4)->show_all();
	showtimes();
	if (sizeof(timers)==1) win->mainwindow->set_no_show_all(0)->show_all();
	//TODO: Shrink the window to fit the new content, iff it was already minimum size.
}

void makewindow()
{
	win->mainwindow = GTK2.Window((["title":"Timers","no-show-all":!sizeof(timers)]))
		->add(win->display=GTK2.Table((["row-spacing":2,"col-spacing":8])))
		->add_events(GTK2.GDK_BUTTON_PRESS_MASK);
	makelabels();
	::makewindow();
}

void sig_mainwindow_button_press_event(object self,object ev)
{
	//NOTE: Sometimes, a combination of click events can result in drag AND config
	//both happening. I'm not sure exactly what triggers this, and it's only minorly
	//ugly, so it's probably not worth trying to figure out a hack to prevent it.
	if (ev->type=="2button_press") config(); //aka double-click (not right-click, not chord)
	else self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
}

void sig_mainwindow_focus_in_event()
{
	G->G->window->mainwindow->present();
}

int closewindow() {return hidewindow();}

int process(string param,mapping(string:mixed) subw)
{
	if (param=="save") say(subw,"%% "+save());
	if (sscanf(param,"save %s",string pfx)) send(subw->connection,pfx+" "+save()+"\r\n");
	if (param=="load")
	{
		//Attempt to load from the most recent line of text with a quote in it
		//TODO: Mark and detect, which would allow wrapped lines to be read.
		//Maybe put braces around the list? That would work, and braces are
		//unlikely to come up inside the strings.
		for (int i=-2;i>=-10;--i) //Just scan back the most recent few
		{
			sscanf(line_text(subw->lines[i]),"%*s\"%s",string content);
			if (content) {param="load \""+content; break;}
		}
		//"fall through" effectively; note that if nothing was found, it'll fall all the way through and do nothing.
	}
	if (sscanf(param,"load %s",string data))
	{
		sscanf(data,"%{%O=%d%}",array(array(string|int)) data);
		foreach (data,[string kwd,int next])
			if (timers[kwd]) timers[kwd]->next=next;
		persist->save();
		showtimes();
		say(subw,"%% Loaded.");
	}
	if (sscanf(param,"next %s",string kwd))
	{
		timers[kwd]->presnext=1;
		say(subw,"%% Will present.");
	}
	if (sscanf(param,"halt %s",string kw))
	{
		foreach (sort(indices(timers));int i;string kwd) if (kwd==kw)
		{
			timers[kwd]->next=0;
			win->timers[i]->set_text("");
			say(subw,"%% Timer halted.");
		}
	}
	if (sscanf(param,"set %d %s",int line,string kwd)) catch
	{
		int starttime=subw->lines[line][0]->timestamp;
		timers[kwd]->next=starttime+timers[kwd]->time;
		say(subw,"%% Timer started.");
	};
	return 1;
}

protected void create(string name)
{
	::create(name);
	showtimes();
}
#else
//This file is executable, as a means of saving (to the console).
//Reads directly from .gypsumrc so it can be used whether Gypsum's running or not.
//Suitable for remote execution eg via SSH
mapping persist=decode_value(Stdio.read_file(combine_path(__FILE__,"..","..",".gypsumrc"))) || ([]);
mapping(string:mapping(string:mixed)) timers=persist["timer/timers"] || ([]);
int main(int argc, array(string) argv)
{
	if (has_value(argv, "show"))
	{
		//Like save() but more human-readable.
		foreach (timers;string kwd;mapping info) if (info->next && info->next>time())
		{
			int t = info->next - time();
			write("%s: %d:%02d:%02d\n", kwd, t/3600, t/60%60, t%60);
		}
		return 0;
	}
	write("%s\n",save());
}
#endif

//Used by both normal and outside-execution modes; renders current timers to text.
string save()
{
	string data="";
	foreach (timers;string kwd;mapping info) if (info->next && info->next>time(1))
		data+=sprintf("%q=%d",kwd,info->next);
	return data;
}
