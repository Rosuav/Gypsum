/* Pop-out character sheet renderer for Minstrel Hall

Carefully matched to the corresponding code on the server, this will pop out a
character sheet based on data stored on the server.

Formulas can be entered. They reference the underlying data mapping, NOT the
coordinates of the cell on some spreadsheet layout, so it's as simple as
referencing the names used. Full Pike syntax is available, but please be
aware: The code broadly assumes that the person devising the formula knows
what s/he is doing. It is entirely possible to break things by mucking that
up. So take a bit of care, and don't deploy without knowing that it's right. :)

Still need:
* Spells (with Prepared and Cast counters for each, and totals per tier, and
  quick buttons to clear out the Prepared and Cast columns)
*/

inherit hook;
mapping(string:multiset(object)) charsheets;

class charsheet(mapping(string:mixed) conn,string owner,mapping(string:mixed) data)
{
	inherit movablewindow;
	constant pos_key="charsheet/winpos";
	mapping(string:multiset(function)) depends=([]); //Whenever something changes, recalculate all its depends.

	void create()
	{
		if (!charsheets[owner]) charsheets[owner]=(<>);
		charsheets[owner][this]=1;
		::create(); //No name. Each one should be independent.
		win->mainwindow->set_skip_taskbar_hint(0)->set_skip_pager_hint(0); //Undo the hinting done by default
	}

	//Allow XP (and only XP) to be entered as a sum, eg 4000+1000 will be replaced with 5000
	string fmt_xp(string val)
	{
		array parts=val/"+";
		if (sizeof(parts)==1) return val;
		return (string)`+(@(array(int))parts);
	}

	void set_value(string kwd,string val,multiset|void beenthere)
	{
		if (val=="0") val="";
		if (val==data[kwd] || (!data[kwd] && val=="")) return; //Nothing changed, nothing to do.
		if (!beenthere) beenthere=(<>);
		if (beenthere[kwd]) return; //Recursion trap: don't recalculate anything twice.
		beenthere[kwd]=1;
		G->G->connection->write(conn,string_to_utf8(sprintf("charsheet @%s qset %s %q\r\n",owner,kwd,data[kwd]=val)));
		if (depends[kwd]) indices(depends[kwd])(data,beenthere);
	}

	void checkchanged(object self,mixed ... args)
	{
		string kwd=args[-1];
		string val=self->get_text();
		if (function f=this["fmt_"+kwd]) catch {self->set_text(val=f(val));}; //See if there's a reformatter function. If there is, it MUST be idempotent.
		set_value(kwd,val);
	}

	void set(string what,string towhat)
	{
		object ef=win[what];
		if (!ef) return; //Nothing to work with
		string cur=ef->get_text();
		if (cur==towhat) return; //No change
		ef->set_text(towhat);
		checkchanged(ef,0,what); //Pretend the user entered it and tabbed out
	}

	GTK2.Table GTK2Table(array(array(string|GTK2.Widget)) contents,int|void homogenousp)
	{
		GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),homogenousp);
		foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
		{
			if (stringp(obj)) obj=GTK2.Label(obj);
			int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
			tb->attach_defaults(obj,x,xend,y,y+1);
		}
		return tb;
	}

	GTK2.Entry ef(string kwd,int|mapping|void width_or_props)
	{
		if (!width_or_props) width_or_props=5;
		if (intp(width_or_props)) width_or_props=(["width-chars":width_or_props]);
		object ret=win[kwd]=GTK2.Entry(width_or_props)->set_text(data[kwd]||"");
		ret->signal_connect("focus-out-event",checkchanged,kwd);
		return ret;
	}

	GTK2.Entry num(string kwd,int|mapping|void width_or_props)
	{
		GTK2.Entry ret=ef(kwd,width_or_props||3); //Smaller default width
		return ret->set_alignment(0.5);
	}

	MultiLineEntryField mle(string kwd,mapping|void props)
	{
		object ret=win[kwd]=MultiLineEntryField(props||([]))->set_text(data[kwd]||"");
		ret->signal_connect("focus-out-event",checkchanged,kwd);
		return ret;
	}

	SelectBox select(string kwd,array(string) options)
	{
		SelectBox ret=win[kwd]=SelectBox(options)->set_text(data[kwd]||"");
		ret->signal_connect("changed",checkchanged,kwd);
		return ret;
	}

	//Magic resolver. Any symbol at all can be resolved; it'll come through as 0, but the name
	//will be retained. Used in the precompilation stage to capture external references.
	multiset(string) symbols;
	mixed resolv(string symbol,string fn,object handler) {symbols[symbol]=1;}

	//Perform magic and return something that has a calculated value.
	//The formula is Pike syntax. Any unexpected variable references in it become lookups
	//into data[] and will be cast to the specified type (default 'int').
	GTK2.Widget calc(string formula,string|void name,string|void type)
	{
		object lbl=GTK2.Label();
		catch
		{
			if (!type) type="int";
			//Phase zero: Precompile, to get a list of used symbols
			symbols=(<>);
			program p=compile("mixed _="+formula+";",this); //Note, p must be retained or the compile() call will be optimized out!

			//Phase one: Compile the formula calculator itself.
			function f1=compile(sprintf(
				"%s _(mapping data) {%{"+type+" %s=("+type+")data->%<s;%}return %s;}",
				type,(array)symbols,formula
			))()->_;
			//Phase two: Snapshot a few extra bits of info via a closure.
			function f2=lambda(mapping data,multiset beenthere)
			{
				string val=(string)f1(data);
				if (name) set_value(name,val,beenthere);
				lbl->set_text(val);
			};
			foreach ((array)symbols,string dep)
				if (!depends[dep]) depends[dep]=(<f2>);
				else depends[dep][f2]=1;
			f2(data,(<name>));
		};
		return lbl;
	}

	//Add a weapon block - type is "melee" or "ranged"
	GTK2.Widget weapon(string prefix,string type)
	{
		prefix="attack_"+prefix;
		string stat=(["melee":"STR","ranged":"DEX"])[type];
		return GTK2.Frame(String.capitalize(type))->add(GTK2.Vbox(0,0)
			->add(GTK2.Hbox(0,0)
				->add(GTK2.Label("Keyword"))->add(ef(prefix,8))
				->add(GTK2.Label("Weapon"))->add(ef(prefix+"_weapon",10))
			)
			->add(GTK2.Hbox(0,0)
				->add(GTK2.Label("Damage"))->add(ef(prefix+"_dmgdice"))
				->add(GTK2.Label("Crit"))->add(select(prefix+"_crittype",({"20 x2","19-20 x2","18-20 x2","20 x3","20 x4"})))
			)
			->add(GTK2.Hbox(0,0)
				->add(GTK2.Label("Enchantment"))->add(num(prefix+"_ench_hit"))->add(num(prefix+"_ench_dam"))
				->add(GTK2.Label("Other hit mod"))->add(num(prefix+"_tohit_other"))->add(ef(prefix+"_tohit_other_desc"))
			)
			->add(GTK2Table(({
				({"hit:",calc(
					"\"d20+\"+(int)bab+\" BAB+\"+(int)"+stat+"_mod+\" "+stat+"\""
					+"+((int)"+prefix+"_ench_hit?\"+\"+(int)"+prefix+"_ench_hit+\" ench\":\"\")"
					+"+((int)"+prefix+"_tohit_other?\"+\"+(int)"+prefix+"_tohit_other+\" \"+("+prefix+"_tohit_other_desc||\"\"):\"\")",
				prefix+"_hit","string")}),
				({"dmg:",
				/* This is a lot more complicated than to-hit. Do it later.
				calc(
					prefix+"_dmgdice",
				prefix+"_dmg","string"))
				*/
				}),
				({"crit:",
					//Ditto and even more so.
				}),
			})))
		);
	}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)"),"type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Notebook()
			->append_page(GTK2.Vbox(0,20)
				->pack_start(GTK2.Hbox(0,10)
					->add(GTK2Table(({
						({"Name",ef("name",12),0,0,"Character level",num("level",8)}),
						({"Race",ef("race",8),"HD",ef("race_hd"),"Experience",num("xp",8)}),
						({"Class",ef("class1",12),"Level",ef("level1"),"To next level",calc("`+(@enumerate(level,1000,1000))-xp")}),
						({"Class",ef("class2",12),"Level",ef("level2")}),
						({"Class",ef("class3",12),"Level",ef("level3")}),
						({"Class",ef("class4",12),"Level",ef("level4")}),
					}))->set_col_spacings(4))
					->add(GTK2.Frame("Wealth")->add(GTK2Table(({
						({"Platinum",num("wealth_plat",7)}),
						({"Gold",num("wealth_gold",7)}),
						({"Silver",num("wealth_silver",7)}),
						({"Copper",num("wealth_copper",7)}),
						({"3.5ed:",calc("wealth_plat*1000+wealth_gold*100+wealth_silver*10+wealth_copper")}),
						({"4ed:",calc("wealth_plat*10000+wealth_gold*100+wealth_silver*10+wealth_copper")}),
					}))))
				,0,0,0)
				->add(GTK2.Hbox(0,20)
					->add(GTK2Table(
						({({"Stat","Score","Eq","Temp","Mod"})})+
						//For each stat (eg "str"): ({"STR",ef("str"),ef("str_eq"),ef("str_tmp"),calc("(str+str_eq+str_tmp-10)/2")})
						map(({"STR","DEX","CON","INT","WIS","CHA"}),lambda(string stat) {return ({
							stat,num(stat),num(stat+"_eq"),num(stat+"_tmp"),
							calc(sprintf("min((%s+%<s_eq+%<s_tmp-10)/2,%<s_max||1000)",stat),stat+"_mod") //TODO: Distinguish DEX_max=="" from DEX_max=="0", and don't cap the former
						});})
					))
					->add(GTK2.Vbox(0,10)
						->add(GTK2.Frame("HP")->add(GTK2Table(({
							({"Normal","Current"}),
							({num("hp"),num("cur_hp")}),
						}))))
						->add(GTK2.Frame("AC")->add(GTK2Table(({
							({"Base","Nat","Suit","Shield","DEX","Deflec","Size","Misc"}),
							({
								"10",num("natural_ac"),calc("bodyarmor_ac"),calc("shield_ac"),calc("DEX_mod"),
								calc("magicarmor_1_ac+magicarmor_2_ac+magicarmor_3_ac","deflection_ac"),
								num("size_ac"),num("misc_ac")
							}),
							({
								"Melee",calc("10+DEX_mod+bodyarmor_ac+shield_ac+natural_ac+deflection_ac+size_ac+misc_ac","ac"),"",
								"Touch",calc("10+DEX_mod+size_ac+misc_ac","ac_touch"),"",
								"Flat",calc("10+bodyarmor_ac+shield_ac+natural_ac+deflection_ac+size_ac+misc_ac","ac_flat"),"",
							}),
						}))->set_col_spacings(5)))
					)
				)
				->add(GTK2.Hbox(0,20)
					->add(GTK2Table(({
						({"Saves","Base","Ability","Misc","Total"}),
						({"Fort",num("fort_base"),calc("CON_mod"),num("fort_misc"),calc("fort_base+CON_mod+fort_misc","fort_save")}),
						({"Refl",num("refl_base"),calc("DEX_mod"),num("refl_misc"),calc("refl_base+DEX_mod+refl_misc","refl_save")}),
						({"Will",num("will_base"),calc("WIS_mod"),num("will_misc"),calc("will_base+WIS_mod+will_misc","will_save")}),
					})))
					->add(GTK2.Vbox(0,20)
						->add(GTK2.Frame("Init")->add(GTK2.Hbox(0,10)
							->add(calc("DEX_mod"))->add(GTK2.Label("DEX +"))
							->add(num("init_misc"))
							->add(GTK2.Label("="))->add(calc("DEX_mod+init_misc","init"))
						))
						->add(GTK2Table(({
							({"Speed",num("speed")}),
							({"BAB",num("bab")}),
							({"Grapple",calc("bab+STR_mod")}),
						})))
					)
				)
			,GTK2.Label("Vital Stats"))
			->append_page(GTK2.Hbox(0,20)
				->pack_start(GTK2.Vbox(0,10)
					->add(weapon("1","melee"))
					->add(weapon("2","melee"))
					->add(weapon("3","ranged"))
					->add(GTK2.Frame("Body armor")->add(GTK2.Vbox(0,0)
						->add(GTK2.Hbox(0,0)
							->add(GTK2.Label("Name"))->add(ef("bodyarmor"))
							->add(GTK2.Label("Type"))->add(select("bodyarmor_type",({"Light","Medium","Heavy"})))
						)
						->add(GTK2.Hbox(0,0)
							->add(GTK2.Label("AC"))->add(ef("bodyarmor_ac"))
							->add(GTK2.Label("Max DEX"))->add(ef("DEX_max"))
							->add(GTK2.Label("Check pen"))->add(ef("bodyarmor_acpen"))
						)
					))
					->add(GTK2.Frame("Shield")->add(GTK2.Hbox(0,0)
						->add(GTK2.Label("Name"))->add(ef("shield"))
						->add(GTK2.Label("AC"))->add(ef("shield_ac"))
						->add(GTK2.Label("Check pen"))->add(ef("shield_acpen"))
					))
					->add(GTK2.Frame("Protective gear (deflection bonuses)")->add(GTK2Table(({
						({"Name","AC"}),
						({ef("magicarmor_1_name",15),num("magicarmor_1_ac")}),
						({ef("magicarmor_2_name",15),num("magicarmor_2_ac")}),
						({ef("magicarmor_3_name",15),num("magicarmor_3_ac")}),
					}))))
				,0,0,0)
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Item","Qty","Weight"})})
					+map(enumerate(50),lambda(int i) {return ({ef("inven_"+i,20),num("inven_qty_"+i),num("inven_wgt_"+i)});})
				))
			)
			,GTK2.Label("Gear"))
			->append_page(GTK2.Vbox(0,20)
				->pack_start(GTK2Table(({
					({"Age",ef("age"),"Skin",ef("skin")}),
					({"Gender",ef("gender"),"Eyes",ef("eyes")}),
					({"Height",ef("height"),"Hair",ef("hair")}),
					({"Weight",ef("weight"),"Size",ef("size")}),
					({"Deity",ef("deity"),"Alignment",ef("alignment",12)}),
				})),0,0,0)
				->add(GTK2.Frame("Languages known")->add(mle("languages")))
			,GTK2.Label("Description"))
			->append_page(GTK2.ScrolledWindow()->add(GTK2Table(
				({({"Name","Stat","Mod","Rank","Synergy","Other","Total"})})
				+map(#"INT Appraise
					DEX Balance
					CHA Bluff
					STR Climb
					CON Concentration
					INT *Craft 1
					INT *Craft 2
					INT *Craft 3
					INT Decipher Script
					CHA Diplomacy
					INT Disable Device
					CHA Disguise
					DEX Escape Artist
					INT Forgery
					CHA Gather Info
					CHA Handle Animal
					WIS Heal
					DEX Hide
					CHA Intimidate
					STR Jump
					INT *Knowledge 1
					INT *Knowledge 2
					INT *Knowledge 3
					INT *Knowledge 4
					INT *Knowledge 5
					INT *Knowledge 6
					WIS Listen
					DEX Move Silently
					DEX Open Lock
					CHA *Perform 1
					CHA *Perform 2
					CHA *Perform 3
					WIS *Profession 1
					WIS *Profession 2
					DEX Ride
					INT Search
					WIS Sense Motive
					DEX Sleight of Hand
					INT Spellcraft
					WIS Spot
					WIS Survival
					STR Swim
					DEX Tumble
					CHA Use Magic Device
					DEX Use Rope"/"\n",lambda(string s)
				{
					sscanf(s,"%*[\t]%s %s",string stat,string|object desc);
					string kwd=replace(lower_case(desc),({"*"," "}),({"","_"}));
					if (desc[0]=='*') //Editable fields (must have unique descriptions)
					{
						desc=desc[1..];
						if (!data[desc]) data[desc]=desc;
						desc=ef(desc);
					}
					//TODO: Synergies (including armor check penalties)
					return ({
						desc,stat,calc(stat+"_mod"),num(kwd+"_rank"),calc("0",kwd+"_synergy"),num(kwd+"_other"),
						calc(sprintf("%s_mod+%s_rank+%<s_synergy+%<s_other",stat,kwd),"skill_"+kwd)
					});
				})
			)),GTK2.Label("Skills"))
			->append_page(GTK2.Vbox(0,10)
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Feat name","Benefit(s)"})})
					+map(enumerate(20),lambda(int i) {return ({ef("feat_"+i,20),ef("feat_benefit_"+i)});})
				)))
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Special ability","Benefit(s)"})})
					+map(enumerate(15),lambda(int i) {return ({ef("ability_"+i,20),ef("ability_benefit_"+i)});})
				)))
			,GTK2.Label("Feats"))
			->append_page(GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Permissions")->add(GTK2.Vbox(0,0)
					->pack_start(GTK2.Label((["label":"Your own account always has full access. You may grant access to any other account or character here; on save, the server will translate these names into canonical account names.","wrap":1])),0,0,0)
					->pack_start(ef("perms"),0,0,0)
				),0,0,0)
				->add(GTK2.Frame("Notes")->add(mle("notes")))
			,GTK2.Label("Administrivia"))
		);
		::makewindow();
	}

	void window_destroy()
	{
		charsheets[owner][this]=0;
		destruct();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->mainwindow,"destroy",window_destroy),
		});
	}
}

int outputhook(string line,mapping(string:mixed) conn)
{
	if (sscanf(line,"===> Charsheet @%s <===",string acct))
	{
		conn->charsheet_eax=""; conn->charsheet_acct=acct;
		return 0;
	}
	if (sscanf(line,"===> Charsheet @%s qset %s %O",string acct,string what,string|int towhat))
	{
		if (multiset sheets=charsheets[acct]) indices(sheets)->set(what,towhat||"");
		return 1; //Suppress the spam
	}
	if (conn->charsheet_eax)
	{
		if (line=="<=== Charsheet ===>")
		{
			mixed data; catch {data=decode_value(MIME.decode_base64(m_delete(conn,"charsheet_eax")));};
			if (mappingp(data)) charsheet(conn,m_delete(conn,"charsheet_acct"),data);
			return 0;
		}
		conn->charsheet_eax+=line+"\n";
		return 0;
	}
}

void create(string|void name)
{
	::create(name);
	if (!G->G->charsheets) G->G->charsheets=([]);
	charsheets=G->G->charsheets;
}
