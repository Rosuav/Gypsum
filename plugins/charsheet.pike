/* Pop-out character sheet renderer for Minstrel Hall

Carefully matched to the corresponding code on the server, this will pop out a
character sheet based on data stored on the server.

Formulas can be entered. They reference the underlying data mapping, NOT the
coordinates of the cell on some spreadsheet layout, so it's as simple as
referencing the names used. Full Pike syntax is available, but please be
aware: The code broadly assumes that the person devising the formula knows
what s/he is doing. It is entirely possible to break things by mucking that
up. So take a bit of care, and don't deploy without knowing that it's right. :)
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
		send(conn,sprintf("charsheet @%s qset %s %q\r\n",owner,kwd,data[kwd]=val));
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

	//Advisory note that this widget should be packed without the GTK2.Expand|GTK2.Fill options
	//As of 8.0.1 with CJA patch, this could safely be done with wid->set_data(), but it's not
	//safe to call get_data() with a keyword that hasn't been set (it'll segfault older Pikes).
	//So this works with a multiset instead.
	multiset(GTK2.Widget) noexpand=(<>);
	GTK2.Widget noex(GTK2.Widget wid) {noexpand[wid]=1; return wid;}

	void ensurevisible(GTK2.Widget self)
	{
		//Scan upward until we find a GTK2.ScrolledWindow. Depends on self->allocation() returning
		//coordinates relative to that parent, and not to the immediate parent (which might be a
		//layout manager or a Frame or something).
		for (GTK2.Widget par=self->get_parent();par;par=par->get_parent())
		{
			if (par->get_hscrollbar) //Is there a better way to detect a GTK2.ScrolledWindow?
			//if (par->get_name()=="GtkScrolledWindow") //Is this reliable?
			{
				mapping alloc=self->allocation();
				par->get_hadjustment()->clamp_page(alloc->x,alloc->x+alloc->width);
				par->get_vadjustment()->clamp_page(alloc->y,alloc->y+alloc->height);
				return;
			}
		}
	}
	
	GTK2.Table GTK2Table(array(array(string|GTK2.Widget)) contents,int|void homogenousp)
	{
		GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),homogenousp);
		foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
		{
			if (stringp(obj)) obj=noex(GTK2.Label(obj));
			int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
			int opt=noexpand[obj]?0:(GTK2.Fill|GTK2.Expand);
			tb->attach(obj,x,xend,y,y+1,opt,opt,1,1);
		}
		return tb;
	}

	GTK2.Entry ef(string kwd,int|mapping|void width_or_props)
	{
		if (!width_or_props) width_or_props=5;
		if (intp(width_or_props)) width_or_props=(["width-chars":width_or_props]);
		object ret=win[kwd]=GTK2.Entry(width_or_props)->set_text(data[kwd]||"");
		ret->signal_connect("focus-out-event",checkchanged,kwd);
		ret->signal_connect("focus-in-event",ensurevisible);
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
		ret->signal_connect("focus-in-event",ensurevisible);
		return ret;
	}

	SelectBox select(string kwd,array(string) options)
	{
		SelectBox ret=win[kwd]=SelectBox(options)->set_text(data[kwd]||"");
		ret->signal_connect("changed",checkchanged,kwd);
		return ret;
	}

	//Highlight an object - probably a label or ef - as something the human
	//should be looking at (as opposed to an intermediate calculation, for
	//instance). It will be accompanied by the specified label.
	GTK2.Widget readme(string lbl,GTK2.Widget main)
	{
		return GTK2.Frame((["shadow-type":GTK2.SHADOW_IN]))
			->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(192,192,255))
			->add(GTK2.Hbox(0,3)->add(GTK2.Label(lbl))->add(main))
		;
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

	void clear_prepared() {clear("prepared");}
	void clear_cast() {clear("cast");}
	void clear(string which)
	{
		foreach (data;string kw;string val)
			if (sscanf(kw,"spells_t%d_%d_%s",int tier,int row,string part) && part==which)
				set(kw,"");
	}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)"),"type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Notebook()
			->append_page(GTK2.Vbox(0,20)
				->pack_start(GTK2.Hbox(0,10)
					->add(GTK2Table(({
						({"Name",ef("name",12),0,0,"Char level",num("level",8)}),
						({"Race",ef("race",8),"HD",ef("race_hd"),"Experience",num("xp",8)}),
						({"Class",ef("class1",12),"Level",num("level1"),"To next lvl",calc("`+(@enumerate(level,1000,1000))-xp")}),
						({"Class",ef("class2",12),"Level",num("level2"),"Size",select("size",({"Fine","Diminutive","Tiny","Small","Medium","Large","Huge","Gargantuan","Colossal"}))}),
						({"Class",ef("class3",12),"Level",num("level3"),
							"Grapple",calc(#"(string)(([
								\"Fine\":-16,\"Diminutive\":-12,\"Tiny\":-8,\"Small\":-4,
								\"Large\":4,\"Huge\":8,\"Gargantuan\":12,\"Colossal\":16
							])[size]+(int)bab+(int)STR_mod)","grapple","string")
						}),
						({"Class",ef("class4",12),"Level",num("level4")}),
					}))->set_col_spacings(4))
					->add(GTK2.Frame("Wealth")->add(GTK2Table(({
						({"Platinum",num("wealth_plat",7)}),
						({"Gold",num("wealth_gold",7)}),
						({"Silver",num("wealth_silver",7)}),
						({"Copper",num("wealth_copper",7)}),
						({"Total gp",calc("(wealth_plat*1000+wealth_gold*100+wealth_silver*10+wealth_copper)/100")}),
						//({"(4ed)",calc("(wealth_plat*10000+wealth_gold*100+wealth_silver*10+wealth_copper)/100")}), //4th ed has platinum worth ten times as much as 3.5ed does
					}))))
				,0,0,0)
				->add(GTK2.Hbox(0,20)
					->add(GTK2.Frame("Stats")->add(GTK2Table(
						({({"","Score","Eq","Temp","Mod"})})+
						//For each stat (eg "str"): ({"STR",ef("str"),ef("str_eq"),ef("str_tmp"),calc("(str+str_eq+str_tmp-10)/2")})
						map(({"STR","DEX","CON","INT","WIS","CHA"}),lambda(string stat) {return ({
							stat,num(stat),num(stat+"_eq"),num(stat+"_tmp"),
							calc(sprintf("min((%s+%<s_eq+%<s_tmp-10)/2,%<s_max||1000)",stat),stat+"_mod") //TODO: Distinguish DEX_max=="" from DEX_max=="0", and don't cap the former
						});})
					)))
					->add(GTK2.Vbox(0,10)
						->add(GTK2.Hbox(0,10)
							->add(GTK2.Frame("HP")->add(GTK2Table(({
								({"Normal","Current"}),
								({num("hp"),num("cur_hp")}),
							}))))
							->add(GTK2.Frame("Init")->add(GTK2.Hbox(0,10)
								->add(calc("DEX_mod"))->add(GTK2.Label("DEX +"))
								->add(num("init_misc"))
								->add(GTK2.Label("="))->add(calc("DEX_mod+init_misc","init"))
							))
						)
						->add(GTK2.Frame("Saves")->add(GTK2Table(({
							({"","Base","Ability","Misc","Total"}),
							({"Fort",num("fort_base"),calc("CON_mod"),num("fort_misc"),calc("fort_base+CON_mod+fort_misc","fort_save")}),
							({"Refl",num("refl_base"),calc("DEX_mod"),num("refl_misc"),calc("refl_base+DEX_mod+refl_misc","refl_save")}),
							({"Will",num("will_base"),calc("WIS_mod"),num("will_misc"),calc("will_base+WIS_mod+will_misc","will_save")}),
						}))))
					)
				)
				->add(GTK2.Hbox(0,20)
					->add(GTK2.Frame("AC")->add(GTK2.Vbox(0,0)
						->add(GTK2Table(({
							({"Base","Nat","Suit","Shield","DEX","Deflec","Size","Misc"}),
							({
								"10",num("natural_ac"),calc("bodyarmor_ac"),calc("shield_ac"),calc("DEX_mod"),
								calc("magicarmor_1_ac+magicarmor_2_ac+magicarmor_3_ac","deflection_ac"),
								calc(#"(string)([
									\"Fine\":8,\"Diminutive\":4,\"Tiny\":2,\"Small\":1,
									\"Large\":-1,\"Huge\":-2,\"Gargantuan\":-4,\"Colossal\":-8
								])[size]","size_ac","string"),num("misc_ac")
							}),
						}))->set_col_spacings(5))
						->add(GTK2.Hbox(0,20)
							->add(readme("Melee",calc("10+DEX_mod+bodyarmor_ac+shield_ac+natural_ac+deflection_ac+size_ac+misc_ac","ac")))
							->add(readme("Touch",calc("10+DEX_mod+size_ac+misc_ac","ac_touch")))
							->add(readme("Flat",calc("10+bodyarmor_ac+shield_ac+natural_ac+deflection_ac+size_ac+misc_ac","ac_flat")))
						)
					))
					->add(GTK2Table(({
						({"Speed",num("speed")}),
						({"BAB",num("bab")}),
					})))
				)
			,GTK2.Label("Vital Stats"))
			->append_page(GTK2.Hbox(0,20)
				->add(GTK2.Vbox(0,10)
					->add(weapon("1","melee"))
					->add(weapon("2","melee"))
					->add(weapon("3","ranged"))
				)
				->pack_start(GTK2.Vbox(0,10)
					->pack_start(GTK2.Frame("Body armor")->add(GTK2.Vbox(0,10)
						->add(GTK2.Hbox(0,0)
							->add(GTK2.Label("Name"))->add(ef("bodyarmor"))
							->add(GTK2.Label("Type"))->add(select("bodyarmor_type",({"Light","Medium","Heavy"})))
						)
						->add(GTK2.Hbox(0,0)
							->add(GTK2.Label("AC"))->add(num("bodyarmor_ac"))
							->add(GTK2.Label("Max DEX"))->add(ef("DEX_max"))
							->add(GTK2.Label("Check pen"))->add(num("bodyarmor_acpen"))
						)
					),0,0,0)
					->pack_start(GTK2.Frame("Shield")->add(GTK2.Hbox(0,0)
						->add(GTK2.Label("Name"))->add(ef("shield"))
						->add(GTK2.Label("AC"))->add(num("shield_ac"))
						->add(GTK2.Label("Check pen"))->add(num("shield_acpen"))
					),0,0,0)
					->pack_start(GTK2.Frame("Protective gear (deflection bonuses)")->add(GTK2Table(({
						({"Name",noex(GTK2.Label("AC"))}),
						({ef("magicarmor_1_name",15),noex(num("magicarmor_1_ac"))}),
						({ef("magicarmor_2_name",15),noex(num("magicarmor_2_ac"))}),
						({ef("magicarmor_3_name",15),noex(num("magicarmor_3_ac"))}),
					}))),0,0,0)
					->pack_start(GTK2.Frame("Other magical or significant gear")->add(GTK2.Vbox(0,2)
						->add(ef("gear_1_name",15))
						->add(ef("gear_2_name",15))
						->add(ef("gear_3_name",15))
						->add(ef("gear_4_name",15))
					),0,0,0)
				,0,0,0)
			,GTK2.Label("Gear"))
			->append_page(GTK2.ScrolledWindow()->add(GTK2Table(
				({({"Item",noex(GTK2.Label("Qty")),noex(GTK2.Label("Wght"))})})
				+map(enumerate(50),lambda(int i) {return ({ef("inven_"+i,20),noex(num("inven_qty_"+i)),noex(num("inven_wgt_"+i))});})
			))
			,GTK2.Label("Inven"))
			->append_page(GTK2.Vbox(0,20)
				->pack_start(GTK2Table(({
					({"Age",ef("age"),"Skin",ef("skin")}),
					({"Gender",ef("gender"),"Eyes",ef("eyes")}),
					({"Height",ef("height"),"Hair",ef("hair")}),
					({"Weight",ef("weight"),"Carried",calc(sprintf("inven_wgt_%d*(inven_qty_%<d||1)",enumerate(4)[*])*"+")}),
					({"Deity",ef("deity"),"Alignment",ef("alignment",12)}),
				})),0,0,0)
				->add(GTK2.Frame("Languages known")->add(mle("languages")))
			,GTK2.Label("Description"))
			->append_page(GTK2.ScrolledWindow()->add(GTK2Table(
				({({"Name","Stat","Mod","Rank","Synergy","Other","Total","Notes"})})
				+map(#"INT Appraise	Craft 1 (if related), Craft 2 (if related), Craft 3 (if related)
					DEX Balance	AC, Tumble
					CHA Bluff
					STR Climb	AC, Use Rope (if climbing rope)
					CON Concentration
					INT *Craft 1
					INT *Craft 2
					INT *Craft 3
					INT Decipher Script
					CHA Diplomacy	Bluff, Knowledge Local, Sense Motive
					INT Disable Device
					CHA Disguise	Bluff (if acting in character)
					DEX Escape Artist	AC, Use Rope (if involving ropes)
					INT Forgery
					CHA Gather Info	Knowledge Local
					CHA Handle Animal
					WIS Heal	AC
					DEX Hide
					CHA Intimidate	Bluff
					STR Jump	AC, Tumble
					INT Knowledge Arcana
					INT Knowledge Local
					INT Knowledge Nobility
					INT Knowledge Nature	Survival
					INT *Knowledge 1
					INT *Knowledge 2
					INT *Knowledge 3
					INT *Knowledge 4
					INT *Knowledge 5
					INT *Knowledge 6
					WIS Listen
					DEX Move Silently	AC
					DEX Open Lock
					CHA *Perform 1
					CHA *Perform 2
					CHA *Perform 3
					WIS *Profession 1
					WIS *Profession 2
					DEX Ride	Handle Animal
					INT Search
					WIS Sense Motive
					DEX Sleight of Hand	AC, Bluff
					INT Spellcraft	Knowledge Arcana, Use Magic Device (if deciphering scroll)
					WIS Spot
					WIS Survival	Search (if following tracks)
					STR Swim	AC, AC
					DEX Tumble	AC, Jump
					CHA Use Magic Device	Decipher Script (if involving scrolls), Spellcraft (if involving scrolls)
					DEX Use Rope	Escape Artist (if involving bindings)"/"\n",lambda(string s)
				{
					sscanf(s,"%*[\t]%s %[^\t]\t%s",string stat,string|object desc,string syn);
					string kwd=replace(lower_case(desc),({"*"," "}),({"","_"}));
					if (desc[0]=='*') //Editable fields (must have unique descriptions)
					{
						desc=desc[1..];
						if (!data[kwd]) data[kwd]=desc;
						desc=noex(ef(kwd,18));
					}
					string|GTK2.Widget synergy_desc="";
					if (syn)
					{
						//Figure out two things: the formula, for the easy bits, and the description, for everything else.
						//Keep the original syn (RFC 793 compliant pun) around for documentation purposes, just in case.
						//The array consists of a number of tuples: ({keyword, type, description})
						//If type == -1, it's the keyword*-1 and is an armor check penalty.
						//If type == 2, it's typical synergy, >=5 gives +2 unconditionally.
						//If type == 0, it's a conditional synergy, >=5 gives +2 in the description only.
						//Note that a keyword may come up more than once, eg with different conditions.
						array(array(string|int)) synergies=({ });
						foreach (syn/", ",string s)
						{
							if (s=="AC") {synergies+=({({"bodyarmor_acpen",-1,"Armor penalty"}),({"shield_acpen",-1,"Shield penalty"})}); continue;} //Non-skill but still a synergy... of sorts.
							sscanf(s,"%s (%s)",string kw,string cond);
							//Simple synergy: 5 or more ranks gives +2, possibly conditionally.
							//If there's a condition, ignore it from the normal figure (which
							//affects the displayed rank).
							synergies+=({({replace(lower_case(kw||s),({"*"," "}),({"","_"}))+"_rank",cond && 2,s})});
						}
						synergy_desc=noex(GTK2.Button(""));
						array(array(string)) full_desc; //Shared state between the two closures, nothing more
						function recalc=lambda(mapping data,multiset beenthere)
						{
							int mod=0;
							full_desc=({({"Synergy","Value"})});
							foreach (synergies,[string kw,int type,string desc])
							{
								int val=(int)data[kw];
								switch (type)
								{
									case -1: if (val) {mod-=val; full_desc+=({({desc,(string)-val})});} break;
									case 0: if (val>=5) mod+=2; //Fall through
									case 2: if (val>=5) full_desc+=({({desc,"2"})});
								}
							}
							string desc="";
							if (sizeof(full_desc)>1)
							{
								desc=(string)mod;
								synergy_desc->set_relief(GTK2.RELIEF_NORMAL)->set_sensitive(1);
							}
							else synergy_desc->set_relief(GTK2.RELIEF_NONE)->set_sensitive(0);
							set_value(kwd+"_synergy",desc,beenthere);
							synergy_desc->set_label(desc);
						};
						synergy_desc->signal_connect("clicked",lambda()
						{
							object cancel=GTK2.Button((["label":GTK2.STOCK_CLOSE,"use-stock":1]));
							cancel->signal_connect("clicked",lambda(object self) {self->get_toplevel()->destroy();});
							GTK2.Window((["title":"Synergies","transient-for":win->mainwindow]))
								->add(GTK2.Vbox(0,2)
									->add(GTK2.Frame("Synergies for "+desc)->add(GTK2Table(full_desc)))
									->add(GTK2.HbuttonBox()->add(cancel))
								)
								->show_all()
								->signal_connect("delete-event",lambda(object self) {self->destroy();});
						});
						foreach (synergies,[string dep,int type,string desc])
							if (!depends[dep]) depends[dep]=(<recalc>);
							else depends[dep][recalc]=1;
						recalc(data,(<kwd+"_synergy">));
					}
					return ({
						desc,stat,noex(calc(stat+"_mod")),noex(num(kwd+"_rank")),synergy_desc,noex(num(kwd+"_other")),
						noex(calc(sprintf("%s_mod+%s_rank+%<s_synergy+%<s_other",stat,kwd),"skill_"+kwd)),
						ef(kwd+"_notes",10),
					});
				})
			)),GTK2.Label("Skills"))
			->append_page(GTK2.Vbox(0,10)
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Feat name","Benefit(s)"})})
					+map(enumerate(20),lambda(int i) {return ({ef("feat_"+i,15),ef("feat_benefit_"+i,25)});})
				)))
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Special ability","Benefit(s)"})})
					+map(enumerate(15),lambda(int i) {return ({ef("ability_"+i,15),ef("ability_benefit_"+i,25)});})
				)))
			,GTK2.Label("Feats"))
			->append_page(GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Prepared spells, by level/tier")->add(GTK2Table(({
					({"L0","L1","L2","L3","L4","L5","L6","L7","L8","L9"}),
					map(enumerate(10),lambda(int i) {array n=enumerate(30); return calc(sprintf("spells_t%d_%d_prepared",i,n[*])*"+");}),
					({win->clear_prepared=GTK2.Button("Clear"),0,0,0,0,0,0,0,0,0}),
				}))),0,0,0)
				->pack_start(GTK2.Frame("Already-cast spells, by level/tier")->add(GTK2Table(({
					({"L0","L1","L2","L3","L4","L5","L6","L7","L8","L9"}),
					map(enumerate(10),lambda(int i) {array n=enumerate(30); return calc(sprintf("spells_t%d_%d_cast",i,n[*])*"+");}),
					({win->clear_cast=GTK2.Button("Clear"),0,0,0,0,0,0,0,0,0}),
				}))),0,0,0)
				->add(GTK2.ScrolledWindow()->add(GTK2Table(lambda() { //This could be done with map() but I want the index (tier) as well as the value (rowcount).
					array ret=({ });
					foreach (({7,10,15,15,15,15,15,15,15,8});int tier;int rowcount)
					{
						ret+=({({GTK2.Frame("Level/tier "+tier)->add(GTK2Table(
							({({"Spell","Description",noex(GTK2.Label("Prep")),noex(GTK2.Label("Cast"))})})
							+map(enumerate(rowcount),lambda(int row)
							{
								string pfx=sprintf("spells_t%d_%d_",tier,row);
								return ({ef(pfx+"name"),ef(pfx+"descr"),noex(num(pfx+"prepared")),noex(num(pfx+"cast"))});
							})
						))})});
					}
					return ret;
				}())))
			,GTK2.Label("Spells"))
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
			gtksignal(win->clear_prepared,"clicked",clear_prepared),
			gtksignal(win->clear_cast,"clicked",clear_cast),
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
		return 1;
	}
}

void create(string name)
{
	::create(name);
	if (!G->G->charsheets) G->G->charsheets=([]);
	charsheets=G->G->charsheets;
}
