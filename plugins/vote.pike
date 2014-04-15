//Threshold RPG vote assistant
//Ticks down 12 hours, then reminds you to vote.
inherit plugin_menu;
inherit statusevent;

constant plugin_active_by_default = 1;

void showtime()
{
	remove_call_out(statustxt->ticker); statustxt->ticker=call_out(this_function,60);
	int t=persist["plugins/vote/nexttime"]-time();
	if (t<=0) {setstatus("VOTE: NOW!"); return;}
	setstatus(sprintf("Vote: %02d:%02d",t/3600,(t/60)%60));
}

void vote()
{
	invoke_browser("http://vote.thresholdrpg.com");
	invoke_browser("http://www.mpogd.com/games/game.asp?ID=449");
	invoke_browser("http://www.mudconnect.com/cgi-bin/vote_rank.cgi?mud=Threshold+RPG");
	persist["plugins/vote/nexttime"]=time()+12*3600;
	showtime();
}

constant menu_label="Vote for Threshold RPG";
void menu_clicked() {vote();}
void statusbar_double_click() {vote();}

void create(string name)
{
	statustxt->tooltip="Threshold RPG vote assistant";
	::create(name);
	showtime();
}
