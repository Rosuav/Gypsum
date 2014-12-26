//Simple aliases. Uses persist["aliases/simple"] to allow future expansion eg regex aliases.
//NOTE: It's not possible to alias slash commands, currently. This could be special-cased.
//It's also not possible to alias hook commands registered later than this plugin, for the
//same reason that aliases can't get into infinite loops (they get injected via nexthook()).

inherit command;
inherit hook;
inherit plugin_menu;

constant plugin_active_by_default = 1;

constant docstring=#"
Simple client-side aliases: replace one command with another.

Allows two forms of alias: global and per-world. Per-world aliases are
configured by first connecting to that world, and then calling up the
menu item 'Aliases - this world'; global aliases can be configured in a
similar way, or via the /alias command - type '/alias help' for instructions.

Aliases cannot expand to slash commands, and cannot expand to other aliases.
";

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
		say(subw,"%%   /alias speak say Sir! %* Sir!");
		say(subw,"%%   speak Hello!");
		say(subw,"%%   --> say Sir! Hello! Sir!");
		return 1;
	}
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
	if (mapping worldalias=subw->world && persist["aliases/simple/"+subw->world])
		if (mapping(string:mixed) alias=worldalias[line]) return nexthook(subw,replace(alias["expansion"],"%*",args||""));
}

class aliasdlg(string persist_key)
{
	inherit configdlg;
	constant strings=({"expansion"});
	mapping(string:mixed) windowprops=(["modal":1]);
	void create(string title) {windowprops->title=title; ::create("Alias");}

	GTK2.Widget make_content() 
	{
		return two_column(({
			"Alias",win->kwd=GTK2.Entry(),
			"Expansion",win->expansion=GTK2.Entry(),
		}));
	}
}

constant menu_label="Aliases - global";
void menu_clicked() {aliasdlg("aliases/simple","Configure global aliases");}

//Hack: A second plugin menu item.
object hack=class {inherit plugin_menu; constant menu_label="Aliases - this world"; void menu_clicked()
{
	mapping subw=G->G->window->current_subw(); if (!subw || !subw->world) return;
	persist->setdefault("aliases/simple/"+subw->world,([]));
	aliasdlg("aliases/simple/"+subw->world,"Configure aliases for "+subw->world);
}}("alias_more");

void create(string name) {::create(name);}
