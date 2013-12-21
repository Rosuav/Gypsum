inherit command;
inherit hook;
inherit statustext;

/**
 * The strings for which to monitor.
 */
mapping(string:array) monitors=([
	//Monitors for Threshold RPG
	"wealth":({" Total Wealth: %[0-9,]","%9s Prv: %s","Wealth"}),
	"xp":({" Current experience points: %[ 0-9,]"," First:%13s; last: %s","XP"}),
	//"x":({"  Current expertise points: %[ 0-9,]"," First:%13s; last: %s","Exp"}),
	//Feel free to add others, or replace these, according to what you play.
]);

int diff(string cur,string last)
{
	return (int)(cur-","-" ")-(int)(last-","-" ");
}

int outputhook(string line,mapping(string:mixed) conn)
{
	foreach (monitors;string kwd;array fmt) if (sscanf(line,fmt[0],string cur) && cur)
	{
		string last=persist["wealth/last_"+kwd] || "";
		string first=persist["wealth/first_"+kwd];
		if (first) last+=sprintf(" -> %d",diff(cur,last));
		else persist["wealth/first_"+kwd]=first=cur;
		say(sprintf(fmt[1],first,last));
		persist["wealth/last_"+kwd]=cur;
		persist["wealth/diff_"+kwd]=diff(cur,first);
		string status="";
		foreach (sort(indices(monitors)),string kw) status+=sprintf("%s %d, ",monitors[kw][2],persist["wealth/diff_"+kw]);
		setstatus(status[..<2]);
	}
	return 0;
}

int process(string param,mapping(string:mixed) subw)
{
	foreach (indices(monitors),string kwd) if (persist["wealth/first_"+kwd])
	{
		say(sprintf("%%%% %s: Initial %s, now %s -> %d",kwd,persist["wealth/first_"+kwd],persist["wealth/last_"+kwd],
			(int)(persist["wealth/last_"+kwd]-","-" ")-(int)(persist["wealth/first_"+kwd]-","-" ")),subw);
		if (param=="reset") persist["wealth/first_"+kwd]=persist["wealth/last_"+kwd];
	}
	if (param=="reset") say("%% Stats reset to zero.",subw);
	return 1;
}

void create(string name) {::create(name);}
