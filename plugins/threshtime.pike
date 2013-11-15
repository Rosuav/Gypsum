inherit hook;
//inherit command; //TODO: Time conversions (another window, or a command, or both)
inherit window;

constant threshmonth=({"Dawn", "Cuspis", "Thawing", "Renasci", "Tempest", "Serenus", "Solaria", "Torrid", "Sojourn", "Hoerfest", "Twilight", "Deepchill"});
constant terramonth=({"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"});

//Threshold times are stored as integer minutes:
//1 hour    ==  60 mins
//1 day    == 1440 mins
//1 month == 43200 mins (== 30 days, as only Thresh months are)
//1 year == 518400 mins (== 360 days, as only Thresh years are)

//One Thresh hour == five RL minutes.
//So th 60 == rl 300 or a ratio of 1:5 (which is the combination of the 12:1 time ratio and a 1:60 ratio of the units, due to Thresh time being stored in minutes).

int halfsync; //1 = Timepiece of Phzult, 2 = default 'time'. Both take two lines to display their info.
int halfsync_hour,halfsync_min;
int halfsync_day,halfsync_year;
int halfsync_rl=0;
string halfsync_monname;

int outputhook(string line,mapping(string:mixed) conn)
{
	//Look for Timepiece of Phzult or Chronos's clock
	//Look also for a default 'time' but that's only to the hour so it's only approximate.
	string th_monname;
	int th_year,th_mon,th_day,th_hour,th_min;
	int sync=0;
	if (sscanf(line,"%*[ ]The Clock displays: %s %d, %d - %d:%d",th_monname,th_day,th_year,th_hour,th_min)==6) sync=1;
	if (sscanf(line,"%*[ ]::%*[ ]%d:%d%*[ ]::=-",th_hour,th_min)==5) {halfsync=1; halfsync_hour=th_hour; halfsync_min=th_min; halfsync_rl=time(); return 0;}
	if (sscanf(line,"%*[ ]It is the %d%*s of %s in the year %d.",th_day,halfsync_monname,th_year)==5)
	{
		halfsync_day=th_day; halfsync_year=th_year; halfsync_rl=time();
		halfsync=2;
		return 0;
	}
	if (halfsync_rl)
	{
		if (halfsync==1 && sscanf(line,"%*[ ]%s %d, %d",th_monname,th_day,th_year)==4)
		{
			halfsync_rl-=time(); //This'll clear halfsync_rl if successful.
			if (halfsync_rl) {halfsync_rl=0; return 0;} //Took too long.
			th_hour=halfsync_hour; th_min=halfsync_min;
			sync=1;
		}
		else if (halfsync==2 && sscanf(line,"%*[ ]It is the hour of the %d",th_hour)==2)
		{
			halfsync_rl-=time(); //Duplicated from the above
			if (halfsync_rl) {halfsync_rl=0; return 0;} //Took too long.
			th_day=halfsync_day; th_year=halfsync_year;
			th_min=30; //Mid-way through the hour, for an estimate.
			th_monname=halfsync_monname;
			sync=2;
		}
		else if (halfsync_rl!=time()) halfsync_rl=0;
	}
	if (sync)
	{
		if ((th_mon=search(threshmonth,th_monname))==-1) return 0; //Not found - must be a botched month.
		if (sync==2) //Rough sync
		{
			int threshtime = th_year*518400 + th_mon*43200 + (th_day-1)*1440 + th_hour*60 + th_min;
			int tt_calc=persist["threshtime/sync_th"]+(time()-persist["threshtime/sync_rl"])/5;
			tt_calc-=threshtime;
			if (tt_calc>-120 && tt_calc<120) return 0; //If it's more than 2 game hours (10 RL minutes) out, then sync. Otherwise don't, chances are this approximate sync isn't right.
			persist["threshtime/sync_th"]=threshtime;
		}
		else persist["threshtime/sync_th"] = th_year*518400 + th_mon*43200 + (th_day-1)*1440 + th_hour*60 + th_min;
		persist["threshtime/sync_rl"]=time();
	}
}

/**
 * Update the display with the current Thresh time
 */
void showtime()
{
	remove_call_out(win->ticker); win->ticker=call_out(this_function,1);
	int th_year,th_mon,th_day,th_hour,th_min;
	int threshtime=persist["threshtime/sync_th"]+(time()-persist["threshtime/sync_rl"])/5;
	th_min=threshtime%60; threshtime/=60; //Need to optimize this somehow. Each is being rendered as two duplicate divisions.
	th_hour=threshtime%24; threshtime/=24;
	th_day=threshtime%30; threshtime/=30;
	th_mon=threshtime%12; threshtime/=12;
	th_year=threshtime;
	win->display->set_text(sprintf("%s %d, %d at %d:%02d",threshmonth[th_mon],th_day+1,th_year,th_hour,th_min));
}

void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Threshold time","transient-for":G->G->window->mainwindow]))
		->add(win->display=GTK2.Label());
	showtime();
	int x,y; catch {[x,y]=persist["threshtime/winpos"];}; //If errors, let 'em sit at the defaults (0,0 since I haven't set any other default)
	win->x=1; call_out(lambda() {m_delete(win,"x");},1);
	win->mainwindow->move(x,y);
}

void configevent(object self,object ev)
{
	if (ev->type!="configure") return;
	if (!has_index(win,"x")) call_out(savepos,2);
	mapping pos=self->get_position(); win->x=pos->x; win->y=pos->y;
}

void savepos()
{
	persist["threshtime/winpos"]=({m_delete(win,"x"),m_delete(win,"y")});
}

void mousedown(object self,object ev)
{
	self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
}

void dosignals()
{
	win->signals=({
		gtksignal(win->mainwindow,"event",configevent),
		gtksignal(win->mainwindow,"button_press_event",mousedown),
		gtksignal(win->mainwindow,"delete_event",hidewindow),
	});
	win->mainwindow->add_events(GTK2.GDK_BUTTON_PRESS_MASK);
}

void create(string name)
{
	if (!persist["threshtime/sync_rl"]) {persist["threshtime/sync_rl"]=1356712257; persist["threshtime/sync_th"]=196948184;}
	::create(name);
	showtime();
}
