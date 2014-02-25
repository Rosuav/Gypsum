inherit hook;
inherit plugin_menu;
inherit statusevent;
inherit window;

constant plugin_active_by_default = 1;

//TODO: Switch to using Calendar.Gregorian with set_timezone("America/New York") for EST/EDT
//Might also be able to use that to get the list of Terran month names, which could then
//be localized. Probably not worth it though, just use the English names.

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
	remove_call_out(statustxt->ticker); statustxt->ticker=call_out(this_function,1);
	int th_year,th_mon,th_day,th_hour,th_min;
	int threshtime=persist["threshtime/sync_th"]+(time()-persist["threshtime/sync_rl"])/5;
	th_min=threshtime%60; threshtime/=60; //Need to optimize this somehow. Each is being rendered as two duplicate divisions.
	th_hour=threshtime%24; threshtime/=24;
	th_day=threshtime%30; threshtime/=30;
	th_mon=threshtime%12; threshtime/=12;
	th_year=threshtime;
	setstatus(sprintf("%s %d, %d at %d:%02d",threshmonth[th_mon],th_day+1,th_year,th_hour,th_min));
}

constant menu_label="Thresh Time converter";
void menu_clicked() {showwindow();}

GTK2.Entry ef(string name,int|void width)
{
	return win[name]=GTK2.Entry((["width-chars":width||2]));
}

void makewindow()
{
	win->mainwindow=GTK2.Window((["title":"Threshold Time Conversion","transient-for":G->G->window->mainwindow,"no-show-all":1]))->add(GTK2.Vbox(0,10)
		->add(GTK2.Frame("Real life (Terra) time")->add(GTK2.Vbox(0,0)
			->add(GTK2.Hbox(0,0)
				->add(win->rb_local=GTK2.RadioButton("Local")->set_active(1))
				->add(win->rb_est=GTK2.RadioButton("EST",win->rb_local))
				->add(win->rb_edt=GTK2.RadioButton("EDT",win->rb_local))
			)
			->add(GTK2Table(({
				({"Year","Month","Day","Time",0}),
				({ef("rl_year",4),win->rl_mon=SelectBox(terramonth),ef("rl_day",3),ef("rl_hour"),ef("rl_min")}),
			})))
		))
		->add(GTK2.HbuttonBox()
			->add(win->conv_up=GTK2.Button("Convert ^"))
			->add(win->conv_dn=GTK2.Button("Convert v"))
			->add(win->set_now=GTK2.Button("Set today"))
		)
		->add(GTK2.Frame("Threshold time")->add(GTK2Table(({
			({"Year","Month","Day","Time",0}),
			({ef("th_year",4),win->th_mon=SelectBox(threshmonth),ef("th_day",3),ef("th_hour"),ef("th_min")}),
		}))))
		->add(GTK2.HbuttonBox()->add(stock_close()))
	);
}

void showwindow()
{
	::showwindow();
	set_time_now();
}

void dosignals()
{
	::dosignals();
	win->signals+=({
		gtksignal(win->rb_local,"toggled",check_timezone),
		gtksignal(win->rb_est,"toggled",check_timezone),
		gtksignal(win->rb_edt,"toggled",check_timezone),
		gtksignal(win->conv_up,"clicked",convert_up),
		gtksignal(win->conv_dn,"clicked",convert_down),
		gtksignal(win->set_now,"clicked",set_time_now),
	});
}

void set_rl_time(int time)
{
	win->last_rl_time=time;
	mapping tm;
	if (win->rb_local->get_active()) tm=localtime(time); //Local time. Ask for it directly.
	else tm=gmtime(time-3600*(4+!win->rb_edt->get_active())); //EST/EDT. A bit of a cheat; ask for GMT, but bias the time by either 4 or 5 hours.
	win->rl_min->set_text((string)tm->min);
	win->rl_hour->set_text((string)tm->hour);
	win->rl_day->set_text((string)tm->mday);
	win->rl_mon->set_active(tm->mon);
	win->rl_year->set_text((string)(tm->year+1900));
}

void check_timezone() {set_rl_time(win->last_rl_time);}

void set_th_time(int time)
{
	win->last_th_time=time;
	win->th_min->set_text((string)(time%60)); time/=60;
	win->th_hour->set_text((string)(time%24)); time/=24;
	win->th_day->set_text((string)(time%30+1)); time/=30;
	win->th_mon->set_active(time%12); time/=12;
	win->th_year->set_text((string)time);
}

void set_time_now()
{
	int tm=time();
	set_rl_time(tm);
	set_th_time(persist["threshtime/sync_th"]+(tm-persist["threshtime/sync_rl"])/5);
}

void convert_up()
{
	int tm=
		(int)win->th_year->get_text() * 518400 +
		(int)win->th_mon->get_active() * 43200 +
		(int)win->th_day->get_text() * 1440 - 1440 +
		(int)win->th_hour->get_text() * 60 +
		(int)win->th_min->get_text();
	win->last_th_time=tm;
	set_rl_time(persist["threshtime/sync_rl"]+(tm-persist["threshtime/sync_th"])*5);
}

void convert_down()
{
	//Pick a timezone. Local time is represented by UNDEFINED, which is distinct
	//from a normal zero which would mean UTC.
	int tz=UNDEFINED;
	if (win->rb_edt->get_active()) tz=4*3600;
	else if (win->rb_est->get_active()) tz=5*3600;
	int tm=mktime(0,
		(int)win->rl_min->get_text(),
		(int)win->rl_hour->get_text(),
		(int)win->rl_day->get_text(),
		(int)win->rl_mon->get_active(),
		(int)win->rl_year->get_text()-1900,
		UNDEFINED,tz);
	win->last_rl_time=tm;
	set_th_time(persist["threshtime/sync_th"]+(tm-persist["threshtime/sync_rl"])/5);
}

void statusbar_double_click() {showwindow();} //Double-click on status bar to show the conversion window

void create(string name)
{
	if (!persist["threshtime/sync_rl"]) {persist["threshtime/sync_rl"]=1356712257; persist["threshtime/sync_th"]=196948184;}
	statustxt->tooltip="Threshold RPG date/time - double-click for converter";
	::create(name);
	showtime();
}
