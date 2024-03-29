inherit command;
inherit hook;
inherit statustext;

constant docstring=#"
Keep track of your wealth/XP gains across a time period, eg a day.

Type '/wealth reset' when your statistical period changes (eg at the start of
a new day), and you'll see and reset stats.
";

//A set of available monitors
mapping(string:array) allmonitors=([
	//Monitors for Threshold RPG
	"wealth":({"%*[ ]Total Wealth: %[-0-9,]","%9s Prv: %s","Wealth"}),
	"xp":({"%*[ ]Current Experience Points: %[- 0-9,]"," First:%13s; last: %s","XP"}),
	"x":({"%*[ ]Current Expertise Points: %[- 0-9,]"," First:%13s; last: %s","Exp"}),
	//Feel free to add others, or replace these, according to what you play.
]);
//The monitors to use.
mapping(string:array) monitors=persist["wealth/monitors"] || (["wealth":allmonitors->wealth, "xp":allmonitors->xp]);

int diff(string cur,string last)
{
	return (int)(cur-","-" ")-(int)(last-","-" ");
}

//Helpers to make sure I'm consistent with persist keys
#define perfirst(kw) persist["wealth/"+subw->world+"/first_"+kw]
#define perlast(kw) persist["wealth/"+subw->world+"/last_"+kw]
#define perdiff(kw) persist["wealth/"+subw->world+"/diff_"+kw]

void updstatus()
{
	string world = persist["wealth/lastworld"]; if (!world) return;
	string status="";
	foreach (sort(indices(monitors)),string kw) status+=sprintf("%s %d, ",monitors[kw][2],persist["wealth/"+world+"/diff_"+kw]);
	setstatus(status[..<2]);
}

int output(mapping(string:mixed) subw,string line)
{
	foreach (monitors;string kwd;array fmt) if (sscanf(line,fmt[0],string cur) && cur)
	{
		if (persist["wealth/first_"+kwd])
		{
			//Migrate from "wealth/last_*" to "wealth/*/last_*" only when a
			//useful line comes through - but then migrate everything.
			foreach (indices(monitors), string kw)
			{
				if (string f=m_delete(persist,"wealth/first_"+kw)) perfirst(kw)=f;
				if (string l=m_delete(persist,"wealth/last_"+kw)) perlast(kw)=l;
				if (string d=m_delete(persist,"wealth/diff_"+kw)) perdiff(kw)=d;
			}
		}
		string last=perlast(kwd) || "";
		string first=perfirst(kwd);
		if (first) last+=sprintf(" -> %d",diff(cur,last));
		else perfirst(kwd)=first=cur;
		//HACK: If wealth gets too long, flip to a different format. TODO: Do without hackery.
		if (kwd == "wealth" && sizeof(first) > 9) say(subw, "%13s: %s", first, last);
		else say(subw,fmt[1],first,last); //TODO: Govern this with an option
		perlast(kwd)=cur;
		perdiff(kwd)=diff(cur,first);
		if (!persist["wealth/"+subw->world+"/stats_since"]) persist["wealth/"+subw->world+"/stats_since"]=time();
		persist["wealth/lastworld"] = subw->world;
		updstatus();
	}
	foreach (({"Orb","Crown","Danar","Slag"}),string type)
		if (sscanf(replace(line, ",", ""), "%*[ ]" + type + ": %d", int val) == 2)
			persist["wealth/"+type]=val;
}

//TODO: Show docs somehow - there are a lot of subcommands now.
int process(string param,mapping(string:mixed) subw)
{
	if (sscanf(param,"add %s",string addme) && allmonitors[addme])
	{
		//Note that this can also be used to update your monitor to the
		//latest version, as allmonitors will always come from code.
		monitors[addme]=allmonitors[addme];
		persist["wealth/monitors"]=monitors;
		say(subw,"%%%% Added monitoring of %s.",addme);
		updstatus();
		return 1;
	}
	if (sscanf(param,"remove %s",string delme) && monitors[delme])
	{
		m_delete(monitors,delme);
		persist["wealth/monitors"]=monitors;
		say(subw,"%%%% Removed monitoring of %s.",delme);
		updstatus();
		return 1;
	}
	if (int t=persist["wealth/"+subw->world+"/stats_since"]) say(subw,"%% Stats since "+ctime(t));
	foreach (indices(monitors),string kwd) if (perfirst(kwd))
	{
		say(subw,"%%%% %s: Initial %s, now %s -> %d",kwd,perfirst(kwd),perlast(kwd),
			(int)(perlast(kwd)-","-" ")-(int)(perfirst(kwd)-","-" "));
		if (param=="reset" || param=="reset "+kwd) perfirst(kwd)=perlast(kwd);
	}
	if (param=="reset") {m_delete(persist,"wealth/"+subw->world+"/stats_since"); say(subw,"%% Stats reset to zero.");}
	return 1;
}

int party(string param,mapping(string:mixed) subw)
{
	//NOTE: Partying isn't currently per-world. Should it be?
	//This is where the wealth/Orb, wealth/Danar, etc figures would go.
	if (param=="")
	{
		if (m_delete(persist,"wealth/party")) say(subw,"%% No longer partying.");
		else say(subw,"%% Usage: /party name1 [name2 [name3...]]");
		return 1;
	}
	int members=sizeof(persist["wealth/party"]=param/" ")+1;
	say(subw,"%% Partying with "+members+" members (self included).");
	persist["wealth/party_split"]=perlast("wealth");
	return 1;
}

int split(string param,mapping(string:mixed) subw)
{
	int tot=diff(perlast("wealth"),persist["wealth/party_split"]);
	int members=sizeof(persist["wealth/party"])+1;
	int each=tot/members;
	say(subw,"%% Splitting "+tot+" slag between "+members+" people - "+each+" each.");
	if (tot<members) {say(subw,"%% Not enough to split."); return 1;}
	int orb=persist["wealth/Orb"];
	int crown=persist["wealth/Crown"];
	int danar=persist["wealth/Danar"];
	int slag=persist["wealth/Slag"];
	if (each*(members-1)>orb*1000+crown*100+danar*10+slag)
	{
		//The giving will fail. Shortcut the iterative search.
		//It's still possible for it to fail after this (eg if you're carrying
		//10 orb coins and need to give out 2 danar each), but there's no way
		//it can succeed if you aren't carrying that much total wealth.
		say(subw,"%% You aren't carrying enough money to give it all out. Giving nothing.");
		return 1;
	}
	string cmd="";
	foreach (persist["wealth/party"],string giveto)
	{
		int left=each;
		int o=min(orb, left/1000); left-=o*1000;  orb-=o;
		int c=min(crown,left/100); left-=c*100; crown-=c;
		int d=min(danar,left/10 ); left-=d*10;  danar-=d;
		int s=min(slag, left/1  ); left-=s*1;    slag-=s;
		say(subw,"%%%% Give %s: %d orb, %d crown, %d danar, %d slag - total %d/%d",giveto,o,c,d,s,o*1000+c*100+d*10+s,each);
		if (left)
		{
			//If the entire job can't be done, abort.
			say(subw,"%% You aren't carrying the right coins to be able to split it.");
			return 1;
		}
		string pat=giveto=="drop"?"drop %d %s%.0s\r\n":"give %d %s to %s\r\n"; //For debugging, you can 'drop' a share of the money.
		if (o) cmd+=sprintf(pat,o,"orb",giveto);
		if (c) cmd+=sprintf(pat,c,"crown",giveto);
		if (d) cmd+=sprintf(pat,d,"danar",giveto);
		if (s) cmd+=sprintf(pat,s,"slag",giveto);
	}
	//For compliance with the rules of Threshold RPG, by default does not actually execute the commands, but merely shows/suggests them.
	//Set this option only if you understand the implications, and (eg) are using this with another server. There is no UI way to do so.
	if (persist["wealth/autosplit"]) send(subw->connection,cmd+"wealth\r\n");
	else say(subw,"%% This will give you a perfect split:\n"+replace(cmd,"\r","")+"wealth\n%% End of perfect split.");
	int splitpoint=(int)(persist["wealth/party_split"]-","-" ");
	persist["wealth/party_split"]=(string)(splitpoint+each); //Pretend you got your share of now-split loot prior to partying.
	return 1;
}

protected void create(string name)
{
	statustxt->tooltip="Threshold RPG wealth stats";
	::create(name);
	G->G->commands->party=party;
	G->G->commands->split=split;
	updstatus();
}
