//Simple aliases. Uses persist["aliases/simple"] to allow future expansion eg regex aliases.
//NOTE: It's not possible to alias slash commands, currently. This could be special-cased.
//It's also not possible to alias hook commands registered later than this plugin, for the
//same reason that aliases can't get into infinite loops (they get injected via nexthook()).

inherit command;
inherit hook;
inherit plugin_menu;

// Current Mapping:
// Mapping     Mapping
// |==========||=============================|
// <alias key>  [expansion] <expansion value>
mapping(string:mapping(string:mixed)) aliases=persist->setdefault("aliases/simple",([]));

int process(string param,mapping(string:mixed) subw)
{
	if (param=="")
	{
		if (!sizeof(aliases)) {say(subw,"%% You have no aliases set ('/alias help' for usage)"); return 1;}
		say(subw,"%% You have the following aliases set:");
		foreach (sort(indices(aliases)),string from)
			say(subw,"%%%% %-20s %=55s",from,aliases[from]->expansion);
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
		say(subw,"%%   speak Hello!");
		say(subw,"%%   --> say Sir! Hello! Sir!");
		return 1;
	}
	if (!aliases) persist["aliases/simple"]=aliases=([]);
	sscanf(param,"%s %s",param,string expansion);
	if (!expansion || expansion=="") //Unalias
	{
		if (mapping(string:mixed) alias=m_delete(aliases,param)) say(subw,"%%%% Removing alias '%s', was: %s",param,alias->expansion);
		else say(subw,"%% No alias '"+param+"' to remove.");
	}
	else
	{
		aliases[param] = (["expansion":expansion]);
		persist->save();
		say(subw,"%% Aliased.");
	}
	return 1;
}

int inputhook(string line,mapping(string:mixed) subw)
{
	sscanf(line,"%s %s",line,string args);
	if (mapping(string:mixed) alias=aliases[line]) return nexthook(subw,replace(alias["expansion"],"%*",args||""));
}

//Plugin menu takes us straight into the config dlg
constant menu_label="Aliases";
class menu_clicked
{
	inherit configdlg;
	constant strings=({"expansion"});
	constant persist_key="aliases/simple";
	mapping(string:mixed) windowprops=(["title":"Configure Aliases","modal":1]);
	void create() {::create("Alias");}

	GTK2.Widget make_content() 
	{
		return two_column(({
			"Alias",win->kwd=GTK2.Entry(),
			"Expansion",win->expansion=GTK2.Entry(),
		}));
	}
}

void create(string name)
{
	::create(name);
	//Compatibility: Previously, aliases were mapped directly to their expansions.
	//Any string expansions need to get converted to mappings. 20140201, can be
	//removed once no longer needed.
	foreach (aliases;string keyword;string|mapping expansion)
		if (stringp(expansion)) aliases[keyword]=(["expansion":expansion]);
}
