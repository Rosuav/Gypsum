//Simple aliases. Uses persist["aliases/simple"] to allow future expansion eg regex aliases.

inherit command;
inherit hook;

int process(string param,mapping(string:mixed) subw)
{
	mapping(string:string) aliases=persist["aliases/simple"];
	if (param=="")
	{
		if (!aliases || !sizeof(aliases)) {say(subw,"%% You have no aliases set ('/alias help' for usage)"); return 1;}
		say(subw,"%% You have the following aliases set:");
		foreach (sort(indices(aliases)),string from)
			say(subw,"%%%% %-20s %=55s",from,aliases[from]);
		say(subw,"%% See '/alias help' for more information.");
		return 1;
	}
	else if (param=="help")
	{
		say(subw,"%% Create/replace an alias: /alias keyword expansion");
		say(subw,"%% Remove an alias: /alias keyword");
		say(subw,"%% Enumerate aliases: /alias");
		say(subw,"%% In an alias, the marker %* will be replaced by all arguments:");
		say(subw,"%%   /alias speak say Sir! %s Sir!");
		say(subw,"%%   speak Hello!",subw);
		say(subw,"%%   --> say Sir! Hello! Sir!");
		return 1;
	}
	if (!aliases) persist["aliases/simple"]=aliases=([]);
	sscanf(param,"%s %s",param,string expansion);
	if (!expansion || expansion=="") //Unalias
	{
		if (string exp=m_delete(aliases,param)) say(subw,"%%%% Removing alias '%s', was: %s",param,exp);
		else say(subw,"%% No alias '"+param+"' to remove.");
	}
	else
	{
		aliases[param]=expansion;
		say(subw,"%% Aliased.");
		persist["aliases/simple"]=aliases; //Force persist to save
	}
	return 1;
}

int inputhook(string line,mapping(string:mixed) subw)
{
	mapping(string:string) aliases=persist["aliases/simple"];
	if (!aliases) return 0;
	sscanf(line,"%s %s",line,string args);
	string expansion=aliases[line];
	if (!expansion) return 0;
	return nexthook(subw,replace(expansion,"%*",args||""));
}

void create(string name) {::create(name);}
