constant docstring=#"
Time zone converter - handles two magical zones \"local\" (your local time,
whatever that be) and \"Thresh\" (Threshold RPG in-character time), plus all
timezones listed in tzdata. Puts one clock on the status bar and can convert
between any pre-specified set. There's quite a bit of Thresh-specific code,
and persist keys all begin \"threshtime/\", but this can happily be used with
no Threshold times.

Note that the conversions depend on your system - your clock, your computer's
time zone, and so on. Accuracy of the Threshold times depends on access to an
in-game timepiece; without one, the clock can generally be correct to within
an hour or two, but that's all. This is good enough for event planning, but
not for predicting in-game events such as bank hours.
";
//Note that when Stash is launched, it may have its own clock. Auto-sync may
//be tricky, but we can at least provide "Stash" as another pseudo-timezone.

//This can be invoked as a stand-alone application via timezone.pike (the
//microkernel). Ideally, there should be as little as possible special code
//to handle this case. So far that has not been attained, but it's close.
inherit hook;
inherit plugin_menu;
inherit statusevent; constant fixedwidth = 1;

constant plugin_active_by_default = 1;

//TODO: Colorize the background (subtly, not intrusively) to show season - esp summer vs non-summer.
//We're already in an EventBox so that shouldn't cost much more.

constant threshmonth=({"Dawn", "Cuspis", "Thawing", "Renasci", "Tempest", "Serenus", "Solaria", "Torrid", "Sojourn", "Hoerfest", "Twilight", "Deepchill"});
constant terramonth=({"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"});

//Set to 1 to debug time conversions
constant show_errors = 0;

//Threshold times are stored as integer minutes:
//1 hour    ==  60 mins
//1 day    == 1440 mins
//1 month == 43200 mins (== 30 days, as only Thresh months are)
//1 year == 518400 mins (== 360 days, as only Thresh years are)

//One Thresh hour == five RL minutes.
//So th 60 == rl 300 or a ratio of 1:5 (which is the combination of the 12:1 time ratio and a 1:60 ratio of the units, due to Thresh time being stored in minutes).

int halfsync; //1 = Timepiece of Phzult (or equivalent portable chronometer), 2 = default 'time'. Both take two lines to display their info; the first is accurate, the second not.
int halfsync_hour,halfsync_min;
int halfsync_day,halfsync_year;
int halfsync_rl=0;
string halfsync_monname;

int output(mapping(string:mixed) subw,string line)
{
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
		if (halfsync_rl!=time())
			; //If we're half way through syncing, require that time() not change before we finish - if it does, reject the sync (latency is bad, mm'kay?).
		else if (halfsync==1 && sscanf(line,"%*[ ]%s %d, %d",th_monname,th_day,th_year)==4)
		{
			th_hour=halfsync_hour; th_min=halfsync_min;
			sync=1;
		}
		else if (halfsync==2 && sscanf(line,"%*[ ]It is the hour of the %d",th_hour)==2)
		{
			th_day=halfsync_day; th_year=halfsync_year;
			th_min=30; //Mid-way through the hour, for an estimate.
			th_monname=halfsync_monname;
			sync=2;
		}
		else return 0;
		halfsync_rl=0;
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
	string zone=persist["threshtime/statuszone"] || "UTC";
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
	//I can't decide whether it's better to separate with spaces (as per the example) or newlines. Accepting both for now.
	array(string) zones=replace(persist["threshtime/zones"]||"local America/New_York UTC Thresh","\n"," ")/" "-({""});
	void create() {::create();}

	GTK2.Entry ef(string name,int|void width)
	{
		return noex(win[name]=GTK2.Entry((["width-chars":width||2])));
	}

	void makewindow()
	{
		GTK2.Vbox box=GTK2.Vbox(0,10);
		mapping(string:string) desc=(["local":"Local time","America/New_York":"New York time (EST/EDT)","Thresh":"Threshold time"]);
		foreach (zones,string zone) box->add(GTK2.Frame(desc[zone] || zone)->add(GTK2Table(({
			({"Year","Month","Day","","Time",0}),
			({ef(zone+"_year",4), win[zone+"_mon"]=SelectBox(zone=="Thresh"?threshmonth:terramonth),
				ef(zone+"_day",3), win[zone+"_dow"]=GTK2.Label(""), ef(zone+"_hour"), ef(zone+"_min")}),
		}))));
		win->mainwindow=GTK2.Window((["title":"Time Zone Conversion"]))->add(box
			->add(GTK2.HbuttonBox()
				->add(win->pick_date=GTK2.Button("Pick date"))
				->add(win->config=GTK2.Button("Configure"))
				->add(GTK2.HbuttonBox()->add(stock_close()))
			)
		);
		//Before signals get connected, set to current time.
		int tm=time();
		set_rl_time(tm);
		set_th_time(persist["threshtime/sync_th"]+(tm-persist["threshtime/sync_rl"])/5);
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
			object store = win->store = GTK2.TreeStore(({"string", "string"}));
			mapping(string:GTK2.TreeIter) regions=([]);
			object special = store->append(); store->set_value(special, 0, "Special");
			store->set_row(store->append(special), ({"local - your local time", "local"}));
			store->set_row(store->append(special), ({"UTC - Coordinated Universal Time", "UTC"}));
			store->set_row(store->append(special), ({"Thresh - in-game time in Threshold RPG", "Thresh"}));
			foreach (sort(Calendar.TZnames.zonenames()), string zone)
			{
				array(string) parts = zone/"/"; //eg "America/New_York", "Australia/Melbourne", "America/Argentina/Buenos_Aires"
				object lastreg = UNDEFINED;
				for (int i=0;i<sizeof(parts);++i)
				{
					string region = parts[..i] * "/";
					if (!regions[region])
						store->set_value(regions[region] = store->append(lastreg), 0, parts[i]);
					lastreg = regions[region];
				}
				store->set_value(lastreg, 1, zone); //Set column 1 only on the leaf nodes.
			}
			win->mainwindow=GTK2.Window((["title":"Choose time zones for display"]))->add(GTK2.Vbox(0,0)
				->add(GTK2.Frame("Status bar timezone")->add(
					win->sbzone=GTK2.Entry()
						->set_text(persist["threshtime/statuszone"]||"UTC")
				))
				->add(GTK2.Frame("Converter timezones")->add(GTK2.ScrolledWindow()
					->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_AUTOMATIC)
					->add(win->convzone=MultiLineEntryField()->set_size_request(100,100)->set_text(zones*"\n"))
				))
				->add(GTK2.ScrolledWindow()
					->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_AUTOMATIC)
					->add(win->timezones=GTK2.TreeView(store)->set_size_request(400,250)
						->append_column(GTK2.TreeViewColumn("Available regions - double-click to add",GTK2.CellRendererText(),"text",0))
					)
				)
				->add(GTK2.HbuttonBox()
					->add(win->pb_ok=GTK2.Button("OK"))
					->add(stock_close())
				)
			);
			::makewindow();
		}

		void sig_timezones_row_activated(object self,object iter,object col,mixed arg)
		{
			iter = win->store->get_iter(iter); //It actually comes in as a TreePath, which isn't very useful.
			string tz = win->store->get_value(iter, 1);
			if (tz=="") return; //TODO: Don't be silent
			string zones = win->convzone->get_text();
			if (zones!="" && zones[-1]!='\n') zones += "\n";
			win->convzone->set_text(zones + tz);
		}

		void sig_pb_ok_clicked()
		{
			multiset(string) validzones=(multiset)(Calendar.TZnames.zonenames()+({"Thresh","local"})+indices(Calendar.TZnames.abbr2zones));
			string convzone=win->convzone->get_text();
			string sbzone=win->sbzone->get_text();
			if (!validzones[sbzone]) {MessageBox(0,GTK2.MESSAGE_ERROR,GTK2.BUTTONS_OK,"Status bar timezone not recognized.",win->mainwindow); return;}
			foreach (convzone/"\n",string z) if (!validzones[z]) {MessageBox(0,GTK2.MESSAGE_ERROR,GTK2.BUTTONS_OK,"Timezone "+z+" not recognized.",win->mainwindow); return;}
			persist["threshtime/zones"]=convzone;
			persist["threshtime/statuszone"]=sbzone;
			closewindow();
			//It's not easy to update the display window on the fly, so close it and open a new one.
			//This causes a bit of messy flicker, and the code here looks a bit bizarre, but it works.
			#if constant(MICROKERNEL)
			write("Changes will take effect when you restart.\n"); //Too much magic in the microkernel to be worth making this work
			#else
			menu_clicked::closewindow();
			menu_clicked();
			#endif
		}
	}

	class sig_pick_date_clicked
	{
		inherit window;
		string zone;
		void create() {::create();}
		void makewindow()
		{
			array z = zones - ({"thresh"}); //The picker uses the first non-Thresh time you have selected ("local", by default)
			if (!sizeof(z)) {MessageBox(0,0,GTK2.BUTTONS_OK,"Need RL time for the picker",menu_clicked::win->mainwindow); return;}
			zone = z[0];
			win->_parentwindow = menu_clicked::win->mainwindow;
			win->mainwindow=GTK2.Window((["title":"Date picker"]))->add(GTK2.Vbox(0,0)
				->add(win->calendar=GTK2.Calendar())
				->pack_start(GTK2.HbuttonBox()->add(stock_close()),0,0,0)
			);
		}
		void sig_calendar_day_selected()
		{
			mapping d=win->calendar->get_date();
			mapping win=menu_clicked::win;
			win[zone+"_year"]->set_text((string)d->year);
			win[zone+"_mon"]->set_active(d->month);
			win[zone+"_day"]->set_text((string)d->day);
		}
		void sig_calendar_day_selected_double_click() {closewindow();}
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
		if (mixed ex=catch
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
		}) if (show_errors) werror("Error converting timezones: %s\n",describe_error(ex));
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
