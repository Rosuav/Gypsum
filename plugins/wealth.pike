inherit command;
inherit hook;

mapping(string:array) monitors=([
	//Monitors for Threshold RPG
	"wealth":({" Total Wealth: %[0-9,]","%9s Prv: %s"}),
	"xp":({" Current experience points: %[ 0-9,]"," First:%13s; last: %s"}),
	//Feel free to add others, or replace these, according to what you play.
]);

int outputhook(string line,mapping(string:mixed) conn)
{
	foreach (monitors;string kwd;array fmt) if (sscanf(line,fmt[0],string cur) && cur)
	{
		string last=persist["wealth/last_"+kwd] || "";
		string first=persist["wealth/first_"+kwd];
		if (first) last+=sprintf(" -> %d",(int)(cur-","-" ")-(int)((last||"")-","-" "));
		else persist["wealth/first_"+kwd]=first=cur;
		say(sprintf(fmt[1],first,last)+" "+(int)(cur-","-" "));
		persist["wealth/last_"+kwd]=cur;
	}
	return 0;
}

int process(string param,mapping(string:mixed) subw)
{
	foreach (indices(monitors),string kwd)
		if (persist["wealth/first_"+kwd]) say(sprintf("%%%% %s: Initial %s, now %s -> %d",kwd,persist["wealth/first_"+kwd],persist["wealth/last_"+kwd],
			(int)(persist["wealth/last_"+kwd]-","-" ")-(int)(persist["wealth/first_"+kwd]-","-" ")),subw);
	return 1;
}

void create(string name) {::create(name);}
