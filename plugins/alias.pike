//Simple aliases. Uses persist["aliases/simple"] to allow future expansion eg regex aliases.

inherit commandhook;

int process(string param,mapping(string:mixed) subw)
{
	mapping(string:string) aliases=persist["aliases/simple"];
	if (param=="")
	{
		if (!aliases || !sizeof(aliases)) {say("%% You have no aliases set ('/alias help' for usage)",subw); return 1;}
		say("%% You have the following aliases set:",subw);
		foreach (sort(indices(aliases)),string from)
			say(sprintf("%%%% %-20s %=55s",from,aliases[from]),subw);
		say("%% See '/alias help' for more information.",subw);
		return 1;
	}
	else if (param=="help")
	{
		say("%% Create/replace an alias: /alias keyword expansion",subw);
		say("%% Remove an alias: /alias keyword",subw);
		say("%% Enumerate aliases: /alias",subw);
		say("%% In an alias, the marker %* will be replaced by all arguments:",subw);
		say("%%   /alias speak say Sir! %s Sir!",subw);
		say("%%   speak Hello!",subw);
		say("%%   --> say Sir! Hello! Sir!",subw);
		return 1;
	}
	if (!aliases) persist["aliases/simple"]=aliases=([]);
	sscanf(param,"%s %s",param,string expansion);
	if (!expansion || expansion=="") //Unalias
	{
		if (string exp=m_delete(aliases,param)) say(sprintf("%%%% Removing alias '%s', was: %s",param,exp),subw);
		else say("%% No alias '"+param+"' to remove.",subw);
	}
	else
	{
		aliases[param]=expansion;
		say("%% Aliased.",subw);
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
	line=replace(expansion,"%*",args);
	if (subw->connection) G->G->connection->write(subw->connection,line+"\r\n");
	return 1;
}
