inherit commandhook;

mapping(string:array) monitors=([
	"wealth":({" Total Wealth: %[0-9,]","%9s Prv: %s"}),
	"xp":({" Current experience points: %[0-9,]"," First:%13s; last: %s"}),
]);

int outputhook(string line)
{
	foreach (monitors;string kwd;array fmt) if (sscanf(line,fmt[0],string cur) && cur)
	{
		string last=persist["wealth/last_"+kwd] || "";
		string first=persist["wealth/first_"+kwd];
		if (first) last+=sprintf(" -> %d",(int)replace(cur,",","")-(int)replace(last || "",",",""));
		else persist["wealth/first_"+kwd]=first=cur;
		say(sprintf(fmt[1],first,last));
		persist["wealth/last_"+kwd]=cur;
	}
	return 0;
}

int process(string param)
{
	say("%% TODO: Show stats.");
	return 1;
}
