//Time zone converter - handles two magical zones "local" (your local time,
//whatever that be) and "Thresh" (Threshold RPG in-character time), plus all
//timezones listed in tzdata. Puts one clock on the status bar and can convert
//between any pre-specified set. There's quite a bit of Thresh-specific code,
//and persist keys all begin "threshtime/", but this can happily be used with
//no Threshold times.
inherit hook;
inherit plugin_menu;
inherit statusevent; //TODO: Should this use the maxwidth variant? If so, how should the two variants be combined?

constant plugin_active_by_default = 1;

//TODO: Colorize the background (subtly, not intrusively) to show season - esp summer vs non-summer.
//We're already in an EventBox so that shouldn't cost much more.

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

//Update the display with the current time
void showtime()
{
	remove_call_out(statustxt->ticker); statustxt->ticker=call_out(this_function,1);
	string zone=persist["threshtime/statuszone"] || "Thresh";
	if (zone=="Thresh")
	{
		int th_year,th_mon,th_day,th_hour,th_min;
		int threshtime=persist["threshtime/sync_th"]+(time()-persist["threshtime/sync_rl"])/5;
		th_min=threshtime%60; threshtime/=60;
		th_hour=threshtime%24; threshtime/=24;
		th_day=threshtime%30; threshtime/=30;
		th_mon=threshtime%12; threshtime/=12;
		th_year=threshtime;
		setstatus(sprintf("%s %d, %d at %d:%02d",threshmonth[th_mon],th_day+1,th_year,th_hour,th_min));
		return;
	}
	Calendar.Gregorian.Second tm=Calendar.Gregorian.Second();
	if (zone!="local") tm=tm->set_timezone(zone);
	mapping t=tm->datetime();
	int tzhr=-t->timezone/3600,tzmin=abs(t->timezone/60%60);
	if (tzmin && tzhr<0) ++tzhr; //Modulo arithmetic produces odd results here. What I want is a four-digit number, but with the last two digits capped at 60 not 100.
	setstatus(sprintf("%s %d, %d at %02d:%02d %+03d%02d",terramonth[t->month-1],t->day,t->year,t->hour,t->minute,tzhr,tzmin));
}

constant menu_label="Time zone converter";
class menu_clicked
{
	inherit window;
	array(string) zones;
	void create() {zones=(persist["threshtime/zones"]||"local America/New_York UTC Thresh")/" "; ::create();}

	GTK2.Entry ef(string name,int|void width)
	{
		return noex(win[name]=GTK2.Entry((["width-chars":width||2])));
	}

	GTK2.Frame timebox(string label,string pfx,array months)
	{
		return GTK2.Frame(label)->add(GTK2Table(({
			({"Year","Month","Day","","Time",0}),
			({ef(pfx+"_year",4),win[pfx+"_mon"]=SelectBox(months),ef(pfx+"_day",3),win[pfx+"_dow"]=GTK2.Label(""),ef(pfx+"_hour"),ef(pfx+"_min")}),
		})));
	}

	void makewindow()
	{
		GTK2.Vbox box=GTK2.Vbox(0,10);
		mapping(string:string) desc=(["local":"Local time","America/New_York":"New York time (EST/EDT)","Thresh":"Threshold time"]);
		foreach (zones,string zone) box->add(timebox(desc[zone] || zone, zone, zone=="Thresh"?threshmonth:terramonth));
		win->mainwindow=GTK2.Window((["title":"Time Zone Conversion","transient-for":G->G->window->mainwindow]))->add(box
			->add(GTK2.HbuttonBox()
				->add(win->set_now=GTK2.Button("Set today"))
				->add(win->config=GTK2.Button("Configure"))
				->add(GTK2.HbuttonBox()->add(stock_close()))
			)
		);
		sig_set_now_clicked(); //Before signals get connected.
		::makewindow();
	}

	void dosignals()
	{
		::dosignals();
		foreach (zones,string pfx) foreach (({"year","mon","day","hour","min"}),string sfx)
			win->signals+=({gtksignal(win[pfx+"_"+sfx],"changed",pfx=="Thresh"?convert_th:convert_rl,pfx)});
	}

	void set_rl_time(int time,string|void which,int|void dowonly)
	{
		if (!which) {set_rl_time(time,(zones-({"Thresh"}))[*]); return;}
		Calendar.Gregorian.Second tm=Calendar.Gregorian.Second(time);
		if (which!="local") tm=tm->set_timezone(which);
		win[which+"_dow"]->set_text(tm->week_day_shortname()); //Could be part of the foreach except for the dowonly flag
		if (dowonly) return;
		if (win->signals) destruct(win->signals[*]); //Suppress 'changed' signals from this.
		//Transfer cal->year_no() into win->est_year->set_text() or win->loc_year->set_text(), etc.
		foreach ((["year":"year_no","day":"month_day","hour":"hour_no","min":"minute_no"]);string ef;string cal)
			win[which+"_"+ef]->set_text((string)tm[cal]());
		win[which+"_mon"]->set_active(tm->month_no()-1);
		if (win->signals) dosignals(); //Un-suppress changed signals.
	}

	void set_th_time(int time)
	{
		if (!win->Thresh_year) return; //No Thresh time on the window, do nothing
		if (win->signals) destruct(win->signals[*]); //As above, in set_rl_time
		win->Thresh_min->set_text((string)(time%60)); time/=60;
		win->Thresh_hour->set_text((string)(time%24)); time/=24;
		win->Thresh_day->set_text((string)(time%30+1)); time/=30;
		win->Thresh_mon->set_active(time%12); time/=12;
		win->Thresh_year->set_text((string)time);
		if (win->signals) dosignals();
	}

	class sig_config_clicked()
	{
		inherit window;
		void create() {::create();}

		void makewindow()
		{
			win->mainwindow=GTK2.Window((["title":"Choose time zones for display","transient-for":G->G->window->mainwindow]))->add(GTK2.Vbox(0,0)
				->add(two_column(({
					GTK2.Label("Time zones should be taken from the tzdata list."),0,
					//TODO: Make a timezone picker, in two parts (pick a continent, then a city)
					//And somehow, make that either work for both sbzone and convzone, or not be confusing. Hmm.... hmm.
					"Status bar timezone",win->sbzone=GTK2.Entry()->set_text(persist["threshtime/statuszone"]||"Thresh"),
					"Converter timezones",win->convzone=GTK2.Entry()->set_width_chars(30)->set_text(zones*" "),
				})))
				->add(GTK2.HbuttonBox()
					->add(win->pb_ok=GTK2.Button("OK"))
					->add(stock_close())
				)
			);
			::makewindow();
		}

		void sig_pb_ok_clicked()
		{
			//TODO: Validate the timezones
			persist["threshtime/zones"]=win->convzone->get_text();
			persist["threshtime/statuszone"]=win->sbzone->get_text();
			closewindow();
		}
	}

	void sig_set_now_clicked()
	{
		int tm=time();
		set_rl_time(tm);
		set_th_time(persist["threshtime/sync_th"]+(tm-persist["threshtime/sync_rl"])/5);
	}

	void convert_th()
	{
		int tm=
			(int)win->Thresh_year->get_text() * 518400 +
			(int)win->Thresh_mon->get_active() * 43200 +
			(int)win->Thresh_day->get_text() * 1440 - 1440 +
			(int)win->Thresh_hour->get_text() * 60 +
			(int)win->Thresh_min->get_text();
		set_rl_time(persist["threshtime/sync_rl"]+(tm-persist["threshtime/sync_th"])*5); //Reverse the usual calculation and turn Thresh into RL time
	}

	void convert_rl(object self,string source)
	{
		catch //If error, just don't convert.
		{
			Calendar.Gregorian.Day day=Calendar.Gregorian.Day(
				(int)win[source+"_year"]->get_text(),
				(int)win[source+"_mon"]->get_active()+1,
				(int)win[source+"_day"]->get_text()
			);
			if (source!="local") day=day->set_timezone(source);
			int hr=(int)win[source+"_hour"]->get_text();
			int min=(int)win[source+"_min"]->get_text();
			Calendar.Gregorian.Second tm=day->second(3600*hr+60*min);
			if (int diff=hr-tm->hour_no()) tm=tm->add(3600*diff); //If DST switch happened, adjust time
			if (int diff=min-tm->minute_no()) tm=tm->add(60*diff);
			if (int diff=0-tm->second_no()) tm=tm->add(60*diff); //As above but since sec will always be zero, hard-code it.
			//Note that it's possible for the figures to still be wrong, if time jumped forward.
			//(For instance, there is no 2014-03-09 02:30:00 AM in America/New_York.)
			//This ought to be a parse failure; however, since this is done live with 'changed' signals,
			//it's more polite to show something, even if it's not precisely right.
			int ts=tm->unix_time(); //Work with Unix time for simplicity
			if (ts==win->last_rl_time) return; //No change, no updates
			win->last_rl_time=ts;
			set_rl_time(ts,(zones-({"Thresh",source}))[*]); //Update the other RL time boxes
			set_rl_time(ts,source,1); //Update day of week without touching anything else
			set_th_time(persist["threshtime/sync_th"]+(ts-persist["threshtime/sync_rl"])/5);
		};
	}
}

void statusbar_double_click() {menu_clicked();} //Double-click on status bar to show the conversion window

void create(string name)
{
	if (!persist["threshtime/sync_rl"]) {persist["threshtime/sync_rl"]=1399531774; persist["threshtime/sync_th"]=205512058;}
	statustxt->tooltip="Current date/time - double-click for converter";
	::create(name);
	showtime();
}
