inherit command;
inherit hook;

/**
 * The strings for which to monitor.
 *
 */
mapping(string:array) monitors=([
	//Monitors for Threshold RPG
	"wealth":({" Total Wealth: %[0-9,]","%9s Prv: %s"}),
	"xp":({" Current experience points: %[ 0-9,]"," First:%13s; last: %s"}),
	//Feel free to add others, or replace these, according to what you play.
]);

/**
 * Collects a line of output from the connection and parses it.
 *
 * @param 	line 	The line to be parsed
 * @param 	conn	The connection from which the line was collected
 * @return	int		Always returns 0	
 */
int outputhook(string line,mapping(string:mixed) conn)
{
	foreach (monitors;string kwd;array fmt) if (sscanf(line,fmt[0],string cur) && cur)
	{
		string last=persist["wealth/last_"+kwd] || "";
		string first=persist["wealth/first_"+kwd];
		if (first) last+=sprintf(" -> %d",(int)(cur-","-" ")-(int)((last||"")-","-" "));
		else persist["wealth/first_"+kwd]=first=cur;
		say(sprintf(fmt[1],first,last));
		persist["wealth/last_"+kwd]=cur;
	}
	return 0;
}

/**
 * Outputs the provided monitors with the persistant values.
 *
 * @param  param 	Unused
 * @param  subw		The sub window which to display the output.
 * @return int		Always returns 1
 */
int process(string param,mapping(string:mixed) subw)
{
	foreach (indices(monitors),string kwd)
		if (persist["wealth/first_"+kwd]) say(sprintf("%%%% %s: Initial %s, now %s -> %d",kwd,persist["wealth/first_"+kwd],persist["wealth/last_"+kwd],
			(int)(persist["wealth/last_"+kwd]-","-" ")-(int)(persist["wealth/first_"+kwd]-","-" ")),subw);
	return 1;
}

/**
 * Creates an instance of the class
 *
 * @param name	the name of this instance of the class 
 */
void create(string name) {::create(name);}
