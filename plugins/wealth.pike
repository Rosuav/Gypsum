inherit command;
inherit hook;
void create(string name) {command::create(name); hook::create(name);} //Necessary when one file uses both

array(mapping) monitors=({
	(["find":" Total Wealth: %[0-9,]","show":"%9s Prv: %s","last":0]),
	(["find":" Current experience points: %[0-9,]","show":" First:%13s; last: %s","last":0]),
});

int outputhook(string line)
{
	foreach (monitors,mapping m) if (sscanf(line,m->find,string cur) && cur)
	{
		if (m->first) m->last+=sprintf(" -> %d",(int)replace(cur,",","")-(int)replace(m->last || "",",",""));
		else m->first=cur;
		say(sprintf(m->show,m->first,m->last || ""));
		m->last=cur;
	}
	return 0;
}

int process(string param)
{
	say("%% TODO: Show stats.");
	return 1;
}
