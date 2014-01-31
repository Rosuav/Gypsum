//Simple aliases. Uses persist["aliases/simple"] to allow future expansion eg regex aliases.

inherit command;
inherit hook;
inherit plugin_menu;

// Current Mapping:
// Mapping     Mapping
// |==========||=============================|
// <alias key>  [expansion] <expansion value>
mapping(string:mapping(string:mixed)) aliases=persist["aliases/simple"]||([]);

int process(string param,mapping(string:mixed) subw)
{
	if (param=="")
	{
		if (!aliases || !sizeof(aliases)) {say(subw,"%% You have no aliases set ('/alias help' for usage)"); return 1;}
		say(subw,"%% You have the following aliases set:");
		foreach (sort(indices(aliases)),string from)
			say(subw,"%%%% %-20s %=55s",from,aliases[from]["expansion"]);
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
	sscanf(param,"%s %s",param,string expansionValue);
	if (!expansionValue || expansionValue=="") //Unalias
	{
		if (mapping(string:mixed) alias=m_delete(aliases,param)) say(subw,"%%%% Removing alias '%s', was: %s",param,alias->expansion);
		else say(subw,"%% No alias '"+param+"' to remove.");
	}
	else
	{
		aliases[param] = (["expansion":expansionValue]);
		say(subw,"%% Aliased.");
		persist["aliases/simple"]=aliases; //Force persist to save
	}
	return 1;
}

int inputhook(string line,mapping(string:mixed) subw)
{
	aliases=persist["aliases/simple"];
	if (!aliases) return 0;
	sscanf(line,"%s %s",line,string args);
	mapping(string:mixed) alias=aliases[line];
	if (!alias) return 0;
	return nexthook(subw,replace(alias["expansion"],"%*",args||""));
}

void create(string name) { ::create(name);}

// Plugin_menu Overrides
constant menu_label="Alias";

// Configdlg Overrides
class menu_clicked
{

        inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Configure Aliases","modal":1]);

	void create()
	{
                items=persist["aliases/simple"]||([]);
                ::create("Alias");
		::showwindow();
	}


	GTK2.Widget make_content() 
	{
                return GTK2.Vbox(0,10)
                        ->pack_start(two_column(({
                                "Alias",win->kwd=GTK2.Entry(),
                                "Expansion",win->exp=GTK2.Entry(),
                        })),0,0,0);

	}

        void load_content(mapping(string:mixed) info)
        {
                if(info->expansion)
		{
        		win->exp->set_text(info->expansion);
                }
                else
                {
                        win->exp->set_text("");
                }
        }


        void save_content(mapping(string:mixed) info)
        {
                info->expansion=win->exp->get_text();
                persist["aliases/simple"]=aliases;
        }

        void delete_content(string kwd,mapping(string:mixed) info)
        {
                persist["aliases/simple"]=aliases;
                win->exp->set_text("");
        }
}

