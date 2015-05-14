constant docstring=#"
Threshold RPG vote assistant
Ticks down 12 hours, then reminds you to vote.
By default, it's non-intrusive. If you'd like it to be a bit more visible,
type this:

/x persist[\"plugins/vote/color\"]=11

That'll make a yellow highlight. (Other numbers for other colors, per the
usual definitions.)

By default, you get a non-personalized link. To personalize it to your
character, fill in your character name above.
";
//TODO: Tie this to an IP address, not to a computer. This MAY mean syncing
//across Gypsums, but more importantly, means it needs to somehow detect its
//external IP and re-highlight accordingly. Reference separate timestamps as
//persist["plugins/vote/nexttime/"+ip] or similar.
//The detection of external IP could ideally be tied in to Threshold RPG's
//server, but otherwise, any What Is My IP service would do.
inherit plugin_menu;
inherit statusevent;

//This is the simplest part to work with; all you need is a character name.
//Selecting a color probably requires a nice little drop-down, so that's a
//feature to implement later.
constant config_persist_key="plugins/vote/character";
constant config_description="Char name for vote registration";

void showtime()
{
	remove_call_out(statustxt->ticker); statustxt->ticker=call_out(this_function,60);
	int t=persist["plugins/vote/nexttime"]-time();
	if (t<=0)
	{
		setstatus("VOTE: NOW!");
		if (int col=persist["plugins/vote/color"]) statustxt->evbox->modify_bg(GTK2.STATE_NORMAL,G->G->window->colors[col]); //Reaching into core here, not a pledged feature but it's convenient to do it this way
	}
	else
	{
		setstatus(sprintf("Vote: %02d:%02d",t/3600,(t/60)%60));
		statustxt->evbox->modify_bg(GTK2.STATE_NORMAL);
	}
}

void vote()
{
	if (string n=persist["plugins/vote/character"]) invoke_browser("http://vote.thresholdrpg.com/vote.php?name="+n);
	else invoke_browser("http://vote.thresholdrpg.com");
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
