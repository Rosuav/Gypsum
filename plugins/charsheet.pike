constant docstring=#"
Pop-out character sheet renderer for Minstrel Hall

Carefully matched to the corresponding code on the server, this will pop out a
character sheet based on data stored on the server.
";

inherit hook;

constant plugin_active_by_default = 1;

array(string) cs_types = array_sscanf(indices(this)[*],"charsheet_%s")*({ });
mapping(string:string) cs_descr = (mapping)lambda(string s) {return ({s,this["charsheet_"+s]->desc});}(cs_types[*]);

mapping(string:multiset(object)) charsheets;

//This class is inherited by all calc() blocks. Functions here are available to all calc expressions.
class UTILS
{
	//Exponentiation but guaranteed to return an integer. Avoids typing issues when Pike is
	//unsure whether the exponent will always be positive.
	//(Does Pike 7.8 not support "base ** exponent"?)
	int intpow(int base, int exponent) {if (exponent < 0) return 1; return pow(base, exponent);}

	int exalted_damage(int oxbody, int dmg_bashing, int dmg_lethal, int dmg_aggravated)
	{
		array health = ({0}) + ({-1}) * (2 + oxbody) + ({-2}) * (2 + oxbody * 2) + ({-4, -100});
		int hp = sizeof(health);
		//Spare damage "wraps around" and gets upgraded
		if (dmg_bashing > hp) dmg_lethal += dmg_bashing - hp;
		if (dmg_lethal > hp) dmg_aggravated += dmg_lethal - hp;
		//TODO: Depict damage levels somewhere
		int dmg = dmg_bashing + dmg_lethal + dmg_aggravated;
		if (!dmg) return 0;
		if (dmg >= hp) return -100;
		return health[dmg - 1];
	}
}

//TODO: Figure out why this is sometimes disgustingly laggy on Sikorsky. Is it because
//I update code so much? Are old versions of the code getting left around? Worse, is it
//that the window isn't getting properly disposed of when it closes? I've never managed
//to actually recreate the problem in a stress-test. :(
//May not be happening any more - not sure. At any rate, it's not so laggy, and I've had
//Gypsum up for the past month-ish.
//Happening again. It seems to take about a month of real-world usage. Hmmmmm. Maybe the
//problem actually comes from somewhere else in Gypsum, and this is just a symptom. Or
//maybe it's actually a GTK issue somewhere?

//TODO: Add a stat buying option somewhere. Where, I'm not sure; the actual stats display
//doesn't need that kind of clutter, and there isn't really a "setup" place. Adding an
//entire new tab just for one-off creation stuff seems cluttery too. But it would be nice
//to have a way to use any of several stat-buying methods (including sending "roll stats"
//to the server), to simplify char creation some, particularly if this is used for NPCs.
//Maybe the tab with tokens can become a "one-off setup" option???

//TODO: Ctrl-Tab/Ctrl-Shift-Tab to cycle through the pages.
class charsheet(mapping(string:mixed) subw,string owner,mapping(string:mixed) data)
{
	inherit movablewindow;
	constant is_subwindow=0;
	constant pos_key="charsheet/winpos";
	mapping(string:array(function)) depends=([]); //Whenever something changes, recalculate all its depends.
	mapping(string:string) skillnames=([]); //For the convenience of the level-up assistant, map skill keywords to their names.
	mapping(string:array(string)) class_skills=([]); //Parsed from the primary skill table - which skills are class skills for each class?
	constant roll_default = ""; //Subclasses can override these to control the Administrivia buttons
	constant roll_attribute = "";

	int errors=0;
	protected void create()
	{
		if (!charsheets[owner]) charsheets[owner]=(<>);
		charsheets[owner][this]=1;
		::create(); //No name. Each one should be independent.
		if (errors) say(subw,"%%%% %d load-time errors - see console for details",errors);
	}

	//Allow numeric fields to be entered as a sum and/or difference, eg 40+10-5 will be replaced with 45
	multiset(string) numerics=(<>);
	string format_num(string val)
	{
		array parts=replace(val,"-","+-")/"+";
		if (sizeof(parts)==1) return val; //Note that without a plus sign, non-numerics won't cause problems.
		return (string)`+(@(array(int))parts);
	}

	multiset(string) writepending=(<>);
	void write_change(string kwd)
	{
		if (!send(subw,sprintf("charsheet @%s qset %s %s\r\n",owner,kwd,Standards.JSON.encode(data[kwd]))))
			//Can't do much :( But at least warn the user.
			win->mainwindow->set_title("UNSAVED CHARACTER SHEET");
		writepending[kwd]=0;
	}

	multiset(string) meaningful_zero = (<"DEX_max">);
	void set_value(string kwd,string val,multiset|void beenthere, int|void debug)
	{
		//TODO: Calculate things more than once if necessary, in order to resolve refchains,
		//but without succumbing to refloops (eg x: "y+1", y: "x+1"). Currently, depends are
		//recalculated in the order they were added, which may not always be perfect.
		//Consider using C3 linearization on the graph of deps - if it fails, error out.
		//Or use Kahn 1962: https://en.wikipedia.org/wiki/Topological_sorting
		if (val == "0" && !meaningful_zero[kwd]) val = ""; //List of things that distinguish 0 from blank
		if (debug) werror("set_value(%O, %O, %O)\n", kwd, val, beenthere);
		if (val==data[kwd] || (!data[kwd] && val=="")) return; //Nothing changed, nothing to do.
		if (!beenthere) beenthere=(<>);
		if (beenthere[kwd]) return; //Recursion trap: don't recalculate anything twice.
		beenthere[kwd]=1;
		data[kwd]=val; writepending[kwd]=1; call_out(write_change,0,kwd);
		if (depends[kwd]) depends[kwd](data,beenthere); //Call all the functions, in order
	}

	void checkchanged(object self,mixed ... args)
	{
		string kwd=args[-1];
		string val=self->get_text();
		//See if there's a reformatter function. If there is, it MUST be idempotent.
		if (function f=numerics[kwd]?format_num:this["fmt_"+kwd])
		{
			string oldval=val; catch {val=f(val);};
			if (val!=oldval) self->set_text(val);
		}
		set_value(kwd,val);
	}

	void set(string what,string towhat)
	{
		object ef=win[what];
		if (!ef) return; //Nothing to work with
		string cur=ef->get_text();
		if (cur==towhat) return; //No change
		ef->set_text(towhat);
		checkchanged(ef,what); //Pretend the user entered it and tabbed out
	}

	void ensurevisible(GTK2.Widget self)
	{
		//Scan upward until we find a GTK2.ScrolledWindow. Depends on self->allocation() returning
		//coordinates relative to that parent, and not to the immediate parent (which might be a
		//layout manager or a Frame or something). What is the rule about where that boundary is?
		//Is ScrolledWindow (or the Viewport it contains) just magical?
		for (GTK2.Widget par=self->get_parent();par;par=par->get_parent())
		{
			if (par->get_hscrollbar) //Only a GTK2.ScrolledWindow has this attribute :)
			{
				mapping alloc=self->allocation();
				par->get_hadjustment()->clamp_page(alloc->x,alloc->x+alloc->width);
				par->get_vadjustment()->clamp_page(alloc->y,alloc->y+alloc->height);
				return;
			}
		}
	}

	mapping(GTK2.Entry:string) ef_kwd = ([]); //As with noex(), this can be done with [sg]et_data() in recent Pikes.
	GTK2.Entry ef(string kwd,int|mapping|void width_or_props)
	{
		if (!width_or_props) width_or_props=5;
		if (intp(width_or_props)) width_or_props=(["width-chars":width_or_props]);
		object ret=win[kwd]=GTK2.Entry(width_or_props)->set_text(data[kwd]||"");
		ret->signal_connect("focus-out-event",checkchanged,kwd);
		ret->signal_connect("focus-in-event",ensurevisible);
		ret->signal_connect("icon-press", edit_notes); //Note that older Pikes have assertion errors on the click event. If this causes segfaults, recommend F2 instead.
		#if constant(GTK2.ENTRY_ICON_SECONDARY)
		//This doesn't work on older GTKs, but it's non-essential. The F2 key is still available (or, should be!).
		//Note that older GTKs may have crashy bugs, so it's definitely not recommended to use anything older than
		//2.24.x, but at least this way you don't get completely locked out of the charsheet.
		if (data["note_"+kwd] && data["note_"+kwd]!="") ret->set_icon_from_stock(GTK2.ENTRY_ICON_SECONDARY,GTK2.STOCK_EDIT);
		#endif
		ef_kwd[ret] = kwd;
		return ret;
	}

	//Display a field as numeric. Formats it differently, and allows summation evaluation,
	//though it doesn't actually force it to store only numbers.
	GTK2.Entry num(string kwd,int|mapping|void width_or_props)
	{
		numerics[kwd]=1; //Flag it for summation formatting
		GTK2.Entry ret=ef(kwd,width_or_props||3); //Smaller default width
		return ret->set_alignment(0.5);
	}

	//Like num() but has increment and decrement buttons
	GTK2.SpinButton spinner(string kwd, float ... minmaxstep)
	{
		object ret = win[kwd] = GTK2.SpinButton(@minmaxstep)->set_value((float)(data[kwd] || "0.0"));
		meaningful_zero[kwd] = 1;
		//NOTE: You can get immediate notification on change by hooking
		//the value-changed signal, but this makes it easy to get into
		//a loop with the server where you're arguing over which value
		//is the correct one. Safer to stick to the default focus event.
		ret->signal_connect("focus-out-event", checkchanged, kwd);
		ret->signal_connect("focus-in-event", ensurevisible);
		return ret;
	}

	MultiLineEntryField mle(string kwd)
	{
		object ret=win[kwd]=MultiLineEntryField()->set_text(data[kwd]||"");
		ret->signal_connect("focus-out-event",checkchanged,kwd);
		ret->signal_connect("focus-in-event",ensurevisible);
		return ret;
	}

	SelectBox select(string kwd,array(string) options)
	{
		SelectBox ret=win[kwd]=SelectBox(options)->set_text(data[kwd]||"");
		ret->signal_connect("changed", (function)checkchanged, kwd);
		return ret;
	}

	//A select box that gives an index within its set of options
	//Each option is data[fields[n]] || defaults[n], and will result in
	//n+1 being the value at this keyword. If none selected, value is 0.
	class picker(string kwd, array(string) fields, array(string) defaults)
	{
		inherit GTK2.ComboBox;
		protected void create()
		{
			::create("");
			foreach (fields; int i; string fld)
			{
				append_text((data[fld] != "" && data[fld]) || defaults[i]);
				depends[fld] += ({reset_strings});
			}
			set_text(data[kwd] || "");
			signal_connect("changed", (function)checkchanged, kwd);
		}
		this_program set_text(string txt)
		{
			set_active((int)txt - 1);
			return this;
		}
		string get_text()
		{
			int idx = get_active();
			return (idx >= 0 && idx < sizeof(fields)) && (string)(idx + 1);
		}
		void reset_strings(mapping data, multiset beenthere)
		{
			int ac = get_active();
			foreach (fields; int i; string fld)
			{
				remove_text(0);
				append_text((data[fld] != "" && data[fld]) || defaults[i]);
			}
			set_active(ac);
		}
	}

	ToggleButton cb(string kwd, string label)
	{
		ToggleButton ret = win[kwd] = ToggleButton(label)->set_text(data[kwd] || "");
		ret->signal_connect("toggled", (function)checkchanged, kwd);
		return ret;
	}

	//Mark that an entry field or MLE is rarely used. Currently done with bg color.
	GTK2.Widget rare(GTK2.Widget wid)
	{
		return wid->modify_base(GTK2.STATE_NORMAL,GTK2.GdkColor(224,192,224));
	}

	//Highlight an object - probably a label or ef - as something the human
	//should be looking at (as opposed to an intermediate calculation, for
	//instance). It will be accompanied by the specified label.
	GTK2.Widget readme(string|zero lbl,GTK2.Widget main)
	{
		if (lbl) main = GTK2.Hbox(0,3)->add(GTK2.Label(lbl))->add(main);
		return GTK2.Frame((["shadow-type":GTK2.SHADOW_IN]))
			->modify_bg(GTK2.STATE_NORMAL,GTK2.GdkColor(192,192,255))
			->add(main)
		;
	}

	//Magic resolver. Any symbol at all can be resolved; it'll come through as 0, but the name
	//will be retained. Used in the precompilation stage to capture external references.
	multiset(string) symbols;
	mixed resolv(string symbol,string fn,object handler) {if (symbol == "UTILS") return UTILS; symbols[symbol]=1;}

	//Perform magic and return something that has a calculated value.
	//The formula is Pike syntax. Any unexpected variable references in it become lookups
	//into data[] and will be cast to the specified type (default 'int').
	//Note that exotic usage of external references can be done by directly referencing the
	//data mapping, eg data->foo or even data[data->statname + "_mod"]. These will not
	//trigger automatic dependency handling. TODO: Allow manual dep addition?
	/* Notes formerly in the docstring:
	Formulas can be entered. They reference the underlying data mapping, NOT the
	coordinates of the cell on some spreadsheet layout, so it's as simple as
	referencing the names used. Full Pike syntax is available, but please be
	aware: The code broadly assumes that the person devising the formula knows
	what s/he is doing. It is entirely possible to break things by mucking that
	up. So take a bit of care, and don't deploy without knowing that it's right. :)
	*/
	GTK2.Widget calc(string formula,string|void name,string|void type, array|multiset|void deps, int|void debug)
	{
		object lbl=GTK2.Label();
		if (mixed ex=catch
		{
			if (!type) type="int";
			if (debug) werror("CALC DEBUG:\nFormula %O\nName %O\nType %O\n", formula, name, type);
			//Use raw/val/deref for dynamic deps. If the formula looks up something
			//in data, it should add that key to the deps (if not already there). If
			//something gets removed, don't bother removing the dep.
			if (has_value(formula, "data->") || has_value(formula, "data["))
				werror("Consider using a lookup function for the definition of %O\n%O\n", name, formula);

			//Phase zero: Precompile, to get a list of used symbols
			symbols = deps ? (multiset)deps : (<>);
			program p=compile("inherit UTILS;\nstring raw(string key) {}string val(string key) {}string deref(string key) {}\n"
						"mapping data = ([]); mixed _="+formula+";",this); //Note: As of Pike 8.1, p must be retained or the compile() call will be optimized out.

			//Phase one: Compile the formula calculator itself.
			function f1=compile(sprintf(
				"inherit UTILS;\n%s _(mapping data, multiset deps) {"
					"%{" + type + " %s=(" + type + ")data->%<s;%}"
					//Using this syntax for nested functions rather than simple declarative b/c Pike 7.8 doesn't support declarative
					"function raw = lambda(string key) {deps[key] = 1; return data[key];};"
					"function val = lambda(string key) {return (%[0]s)raw(key);};"
					"function deref = lambda(string key) {return val(lower_case(raw(key)));};" //deref("use_this_skill") ==> data[data->use_this_skill]
					"deref;" //Prevent warning if it isn't used (which is the common case)
				"return %s;}",
				type, (array)symbols, formula
			), this)()->_;
			//Phase two: Snapshot a few extra bits of info via a closure.
			deps = symbols + (<>);
			void f2(mapping data,multiset beenthere)
			{
				multiset newdeps = (<>);
				string val=(string)f1(data, newdeps);
				foreach ((array)newdeps, string dep) if (!deps[dep])
				{
					if (debug) werror("NEW DEP FOR %O: %O\n", name, dep);
					deps[dep] = 1;
					depends[dep] += ({f2});
				}
				if (debug) werror("Updating calc (%O) to %O\n%O\n", name, val, beenthere);
				if (name) set_value(name,val,beenthere, debug);
				lbl->set_text(val);
			};
			if (debug) werror("Deps for %O:%{ %O%}\n", name, sort((array)symbols));
			foreach ((array)deps, string dep)
				depends[dep] += ({f2});
			f2(data,(<name>));
		}) {++errors; werror("Error compiling %O\n%s\n",formula,describe_backtrace(ex));} //Only someone who's editing charsheet.pike should trigger these errors, so the console should be fine.
		return lbl;
	}

	GTK2.Widget debugcalc(string formula,string|void name, string|void type, array|multiset|void deps)
	{
		return calc(formula, name, type, deps, 1);
	}

	//Add a weapon block - type "ranged" is special
	GTK2.Widget weapon(string prefix,string type)
	{
		prefix="attack_"+prefix;
		string stat = type=="ranged" ? "DEX" : "STR";
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
				/* This is a lot more complicated than to-hit. Do it later. Or should it just be a straight EF?
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

	void sig_clear_prepared_clicked() {clear("prepared");}
	void sig_clear_cast_clicked() {clear("cast");}
	void clear(string which)
	{
		foreach (data;string kw;string val)
			if (sscanf(kw,"spells_t%d_%d_%s",int tier,int row,string part) && part==which)
				set(kw,"");
	}

	//To make an alternate character sheet, start by subclassing this. Then you can override a function to
	//change the page layout, or add/remove/reorder pages in this array.
	constant pages = ({"Vital Stats", "Gear", "Inven", "Description", "Skills", "Feats", "Spells", "Token", "Administrivia", "Help"});

	GTK2.Widget Page_Vital_Stats()
	{
		return GTK2.Vbox(0,20)
				->pack_start(GTK2.Hbox(0,10)
					->add(GTK2Table(({
						({"Name",ef("name",12),0,0,"Char level",num("level",8)}),
						({"Race",ef("race",8),"HD",rare(ef("race_hd")),"Experience",num("xp",8)}),
						({"Class",ef("class1",12),"Level",num("level1"),"To next lvl",win->tnl=GTK2.Button()->add(calc("(level && `+(@enumerate(level,1000,1000)))-xp"))}),
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
					}))))
				,0,0,0)
				->add(GTK2.Hbox(0,20)
					->add(GTK2.Frame("Stats")->add(GTK2Table(
						({({"","Score","Eq","Temp","Mod"})})+
						//For each stat (eg "str"): ({"STR",ef("str"),ef("str_eq"),ef("str_tmp"),calc("(str+str_eq+str_tmp-10)/2")})
						map(({"STR","DEX","CON","INT","WIS","CHA"}),lambda(string stat) {return ({
							stat,num(stat),num(stat+"_eq"),rare(num(stat+"_tmp")),
							calc(sprintf("(%s+%<s_eq+%<s_tmp-10)/2",stat),stat+"_mod")
						});})
					)))
					->add(GTK2.Vbox(0,10)
						->add(GTK2.Hbox(0,10)
							->add(GTK2.Frame("HP")->add(GTK2Table(({
								({"Normal","Current"}),
								({num("hp"),num("cur_hp")}),
							}))))
							->add(GTK2.Frame("Initiative")->add(GTK2.Hbox(0,10)
								->add(calc("DEX_mod"))->add(GTK2.Label("DEX +"))
								->add(num("init_misc"))
								->add(GTK2.Label("="))->add(calc("DEX_mod+init_misc","init"))
							))
						)
						->add(GTK2.Frame("Saves")->add(GTK2Table(({
							({"","Base","Ability","Eq","Misc","Total"}),
							({"Fort",num("fort_base"),calc("CON_mod"),num("fort_eq"),rare(num("fort_misc")),calc("fort_base+CON_mod+fort_eq+fort_misc","fort_save")}),
							({"Refl",num("refl_base"),calc("DEX_mod"),num("refl_eq"),rare(num("refl_misc")),calc("refl_base+DEX_mod+refl_eq+refl_misc","refl_save")}),
							({"Will",num("will_base"),calc("WIS_mod"),num("will_eq"),rare(num("will_misc")),calc("will_base+WIS_mod+will_eq+will_misc","will_save")}),
						}))))
					)
				)
				->add(GTK2.Hbox(0,20)
					->add(GTK2.Frame("AC")->add(GTK2.Vbox(0,0)
						->add(GTK2Table(({
							({"Base","Nat","Suit","Shield","DEX","Deflec","Size","Misc"}),
							({
								"10", num("natural_ac"), calc("bodyarmor_ac"), calc("shield_ac"),
								//Distinguishes DEX_max=="" from DEX_max=="0", and doesn't cap the former.
								calc("DEX_max == \"\" ? DEX_mod : min(DEX_mod, DEX_max)", "DEX_ac", "string"),
								calc("magicarmor_1_ac+magicarmor_2_ac+magicarmor_3_ac","deflection_ac"),
								calc(#"(string)([
									\"Fine\":8,\"Diminutive\":4,\"Tiny\":2,\"Small\":1,
									\"Large\":-1,\"Huge\":-2,\"Gargantuan\":-4,\"Colossal\":-8
								])[size]","size_ac","string"),num("misc_ac")
							}),
						}))->set_col_spacings(5))
						->add(GTK2.Hbox(0,20)
							->add(readme("Melee",calc("10+DEX_ac+bodyarmor_ac+shield_ac+natural_ac+deflection_ac+size_ac+misc_ac","ac")))
							->add(readme("Touch",calc("10+DEX_ac+size_ac+misc_ac","ac_touch")))
							->add(readme("Flat",calc("10+bodyarmor_ac+shield_ac+natural_ac+deflection_ac+size_ac+misc_ac","ac_flat")))
						)
					))
					->add(GTK2Table(({
						({"Speed",num("speed")}),
						({"BAB",num("bab")}),
					})))
				);
	}

	GTK2.Widget Page_Gear()
	{
		return GTK2.Hbox(0,20)
				->add(GTK2.Vbox(0,10)
					->add(weapon("1","primary"))
					->add(weapon("2","secondary"))
					->add(weapon("3","ranged"))
				)
				->pack_start(GTK2.Vbox(0,10)
					->pack_start(GTK2.Frame("Body armor")->add(GTK2.Vbox(0,10)
						->add(two_column(({
							"Name", ef("bodyarmor"),
							"Type", select("bodyarmor_type",({"Light","Medium","Heavy"})),
						})))
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
						->add(ef("gear_5_name",15))
						->add(ef("gear_6_name",15))
					),0,0,0)
				,0,0,0);
	}

	GTK2.Widget Page_Inven()
	{
		return GTK2.ScrolledWindow()->add(GTK2Table(({
				({GTK2Table(({ //Yep, a table in a table. Tidier than a Vbox with two tables.
					({"Total weight",calc(sprintf("0%{+inven_qty_%d*inven_wgt_%<d%}",enumerate(20)),"inven_tot_weight","float"),
					"Size mod",GTK2.Hbox(0,0)
						->add(GTK2.Label("")) //Center the important info by absorbing spare space at the two ends
						->pack_start(GTK2.Label("*"),0,0,0)
						->pack_start(calc("([\"Small\":3,\"Large\":2,\"Huge\":4,\"Gargantuan\":8,\"Colossal\":16])[size] || \"1\"","size_mul","string"),0,0,0)
						->pack_start(GTK2.Label("/"),0,0,0)
						->pack_start(calc("([\"Small\":4,\"Tiny\":2,\"Diminutive\":4,\"Fine\":8])[size] || \"1\"","size_div","string"),0,0,0)
						->add(GTK2.Label("")),
					"Light load",calc("inven_hvy_load/3"),"Med load",calc("inven_hvy_load*2/3"),"Heavy load",calc("(STR<0 ? 0 :" //Negative STR shouldn't happen
						"STR<20 ? ({0,10,20,30,40,50,60,70,80,90,100,115,130,150,175,200,230,260,300,350})[STR] :" //Normal range strengths
						"({400,460,520,600,700,800,920,1040,1200,1400})[STR_mod%10] * intpow(4,STR/10-2)" //Tremendous strength
					") * (size_mul||1) / (size_div||1)","inven_hvy_load")})
				})),0,0}),
				({"Item",noex(GTK2.Label("Qty")),noex(GTK2.Label("Wght"))})
				})+map(enumerate(50),lambda(int i) {return ({ef("inven_"+i,20),noex(num("inven_qty_"+i)),noex(num("inven_wgt_"+i))});})
			));
	}

	GTK2.Widget Page_Description()
	{
		return GTK2.Vbox(0,20)
				->pack_start(GTK2Table(({
					({"Age",ef("age"),"Skin",ef("skin")}),
					({"Gender",ef("gender"),"Eyes",ef("eyes")}),
					({"Height",ef("height"),"Hair",ef("hair")}),
					({"Weight",ef("weight"),"Carried",calc("inven_tot_weight",0,"float")}),
					({"Deity",ef("deity"),"Alignment",ef("alignment",12)}),
				})),0,0,0)
				->add((object)(GTK2.Frame("Languages known")->add((object)(mle("languages")))));
	}

	GTK2.Widget Page_Skills()
	{
		return GTK2.ScrolledWindow()->add(GTK2Table(
				({({"Name","Stat","Mod","Rank","Synergy","Other","Total","Notes"})})
				//	Stat and skill name	Class skill for these classes	Synergies, including Armor Check penalty and conditionals.
				+map( #"INT Appraise		Brd,Rog				Craft 1 (if related), Craft 2 (if related), Craft 3 (if related)
					DEX Balance		Brd,Mnk,Rog			AC, Tumble
					CHA Bluff		Brd,Rog,Sor
					STR Climb		Bbn,Brd,Ftr,Mnk,Rgr,Rog		AC, Use Rope (if climbing rope)
					CON Concentration	Brd,Clr,Drd,Mnk,Pal,Rgr,Sor,Wiz
					INT *Craft 1		Bbn,Brd,Clr,Drd,Ftr,Mnk,Pal,Rgr,Rog,Sor,Wiz
					INT *Craft 2		Bbn,Brd,Clr,Drd,Ftr,Mnk,Pal,Rgr,Rog,Sor,Wiz
					INT *Craft 3		Bbn,Brd,Clr,Drd,Ftr,Mnk,Pal,Rgr,Rog,Sor,Wiz
					INT +Decipher Script	Brd,Rog,Wiz
					CHA Diplomacy		Brd,Clr,Drd,Mnk,Pal,Rog		Bluff, Knowledge Local, Sense Motive
					INT +Disable Device	Rog
					CHA Disguise		Brd,Rog				Bluff (if acting in character)
					DEX Escape Artist	Brd,Mnk,Rog			AC, Use Rope (if involving ropes)
					INT Forgery		Rog
					CHA Gather Info		Brd,Rog				Knowledge Local
					CHA +Handle Animal	Bbn,Drd,Ftr,Pal,Rgr
					WIS Heal		Clr,Drd,Pal,Rgr
					DEX Hide		Bbn,Mnk,Rgr,Rog			AC
					CHA Intimidate		Bbn,Ftr,Rog			Bluff
					STR Jump		Bbn,Brd,Ftr,Mnk,Rgr,Rog		AC, Tumble
					INT +Knowledge Arcana	Bbn,Clr,Mnk,Sor,Wiz
					INT +Knowledge Local	Brd,Rog,Wiz
					INT +Knowledge Nobility	Brd,Pal,Wiz
					INT +Knowledge Nature	Brd,Drd,Rgr,Wiz			Survival
					INT +*Knowledge 1	Brd,Wiz
					INT +*Knowledge 2	Brd,Wiz
					INT +*Knowledge 3	Brd,Wiz
					INT +*Knowledge 4	Brd,Wiz
					INT +*Knowledge 5	Brd,Wiz
					INT +*Knowledge 6	Brd,Wiz
					WIS Listen		Bbn,Brd,Drd,Mnk,Rgr,Rog
					DEX Move Silently	Brd,Mnk,Rgr,Rog	AC
					DEX +Open Lock		Rog
					CHA *Perform 1		Brd,Mnk,Rog
					CHA *Perform 2		Brd,Mnk,Rog
					CHA *Perform 3		Brd,Mnk,Rog
					WIS +*Profession 1	Brd,Clr,Drd,Mnk,Pal,Rgr,Rog,Sor,Wiz
					WIS +*Profession 2	Brd,Clr,Drd,Mnk,Pal,Rgr,Rog,Sor,Wiz
					DEX Ride		Bbn,Drd,Ftr,Pal,Rgr		Handle Animal
					INT Search		Rgr,Rog
					WIS Sense Motive	Brd,Mnk,Pal,Rog
					DEX +Sleight of Hand	Brd,Rog	AC, Bluff
					INT +Spellcraft		Brd,Clr,Drd,Sor,Wiz		Knowledge Arcana, Use Magic Device (if deciphering scroll)
					WIS Spot		Drd,Mnk,Rgr,Rog
					WIS Survival		Bbn,Drd,Rgr			Search (if following tracks)
					STR Swim		Bbn,Brd,Drd,Ftr,Mnk,Rgr,Rog	AC, AC
					DEX +Tumble		Brd,Mnk,Rog			AC, Jump
					CHA +Use Magic Device	Brd,Rog				Decipher Script (if involving scrolls), Spellcraft (if involving scrolls)
					DEX Use Rope		Rgr,Rog				Escape Artist (if involving bindings)"/"\n",lambda(string s)
				{
					sscanf(s,"%*[\t]%s %[^\t]%*[\t]%[^\t]%*[\t]%s",string stat,string|object desc,string cls,string syn);
					int trainedonly = desc[0]=='+'; if (trainedonly) desc=desc[1..];
					string kwd=replace(lower_case(desc),({"*"," "}),({"","_"}));
					skillnames[kwd]=desc; foreach (cls/",",string c) class_skills[c]+=({kwd});
					//Due to a bug in charsheet.pike for about 50 commits from Dec 27th 2015 until
					//Jan 4th 2016, some data could have been mis-stored. Look for it and retrieve.
					if (string bad=m_delete(data,"+"+kwd+"_rank"))
					{
						string keep=data[kwd+"_rank"];
						if (!(int)bad) //Easy. Ignore zeroes.
							;
						if (!keep || !(int)keep) //Easy. Lift it in to replace a null entry.
							data[kwd+"_rank"] = bad;
						else say(subw,"%%%% CAUTION: Double data for %O - bad %O, keeping %O", desc, bad, keep);
						send(subw,sprintf("charsheet @%s del +%s_rank\r\n",owner,kwd));
					}
					//End retrieval. Remove when not needed.
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
							//Hack: Armor Check penalties aren't skills, but they're synergies... of a sort. Negative synergies, if you like.
							if (s=="AC") {synergies+=({({"bodyarmor_acpen",-1,"Armor penalty"}),({"shield_acpen",-1,"Shield penalty"})}); continue;}
							sscanf(s,"%s (%s)",string kw,string cond);
							//Simple synergy: 5 or more ranks gives +2, possibly conditionally.
							//If there's a condition, ignore it from the normal figure (which
							//affects the displayed rank).
							synergies+=({({replace(lower_case(kw||s),({"*"," "}),({"","_"}))+"_rank",cond && 2,s})});
						}
						synergy_desc=noex(GTK2.Button(""));
						array(array(string)) full_desc; //Shared state between the two closures, nothing more
						void recalc(mapping data,multiset beenthere)
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
							cancel->signal_connect("clicked",lambda(object self) {
								if (self->get_toplevel()->destroy) self->get_toplevel()->destroy();
								destruct(self->get_toplevel());
							});
							GTK2.Window((["title":"Synergies","transient-for":win->mainwindow]))
								->add(GTK2.Vbox(0,2)
									->add(GTK2.Frame("Synergies for "+desc)->add(GTK2Table(full_desc)))
									->add(GTK2.HbuttonBox()->add(cancel))
								)
								->show_all();
						});
						foreach (synergies,[string dep,int type,string desc])
							depends[dep]+=({recalc});
						recalc(data,(<kwd+"_synergy">));
					}
					return ({
						desc,stat,noex(calc(stat+"_mod")),noex(num(kwd+"_rank")),synergy_desc,rare(noex(num(kwd+"_other"))),
						noex(calc(sprintf("(%s_mod+%s_rank+%<s_synergy+%<s_other)*(!!%<s_rank||%d)",stat,kwd,!trainedonly),"skill_"+kwd)),
						ef(kwd+"_notes",10),
					});
				})));
	}

	GTK2.Widget Page_Feats()
	{
		return GTK2.Vbox(0,10)
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Feat name","Benefit(s)"})})
					+map(enumerate(20),lambda(int i) {return ({ef("feat_"+i,15),ef("feat_benefit_"+i,25)});})
				)))
				->add(GTK2.ScrolledWindow()->add(GTK2Table(
					({({"Special ability","Benefit(s)"})})
					+map(enumerate(15),lambda(int i) {return ({ef("ability_"+i,15),ef("ability_benefit_"+i,25)});})
				)));
	}

	GTK2.Widget Page_Token()
	{
		return GTK2.Vbox(0,0)->pack_start(GTK2Table(({
			({"Regular token", ef("token"), win->pick_token=GTK2.Button("Select")}),
			({"Large token [beta]", ef("token_large"), win->pick_large_token=GTK2.Button("Select")}),
			({"If your normal size is neither Small nor Medium, you may "
			"need to select a token manually rather than using the pickers.", 0}),
		}),(["xalign":1.0, "wrap":1])),0,0,0);
	}

	class sig_pick_token_clicked
	{
		inherit window;
		int large; //0 if regular token, 1 if large
		string minstrelhall; //IP address of Minstrel Hall's server - looked up once instead of per-image
		protected void create(object btn)
		{
			large = (btn == charsheet::win->pick_large_token);
			::create();
		}

		void select_image(object btn)
		{
			set_value("token" + "_large"*large, btn->get_label());
			closewindow();
		}

		void report_error(string err)
		{
			win->box->get_children()[0]->set_text(err);
		}

		void tokenimage(string data, string name)
		{
			if (!data) return; //Just leave it blank if we can't retrieve it
			if (!win || !win->images || !win->images[name]) return; //Window's gone.
			//I kinda want to assert that the content-type is "text/png" here
			Image.Image img = Image.PNG.decode(data);
			Image.Image mask = Image.PNG.decode_alpha(data);
			//TODO: What happens if the decode fails?
			win->images[name]->set_from_image(win->img[name]=GTK2.GdkImage(0, img), win->bmp[name]=GTK2.GdkBitmap(mask));
			destruct(img); destruct(mask);
		}

		void tokenlist(string info)
		{
			if (!info)
			{
				report_error("Unable to contact Minstrel Hall for token list.");
				return;
			}
			array table = ({ });
			win->images = ([]); win->img = ([]); win->bmp = ([]);
			int sz = large ? 52 : 25; //Pre-size as much as possible. If these numbers are wrong, the server will correct us, but the ScrolledWindow might be wrong.
			win->blank = GTK2.GdkImage(0, Image.Image(sz, sz, 240, 240, 240));
			foreach (info/"\n", string line) if (line != "")
			{
				object btn = GTK2.Button(line);
				btn->signal_connect("clicked", select_image);
				table += ({({btn, win->images[line] = GTK2.Image(win->blank)})});
				//TODO: Cache the images locally in case people click, pick, then click again.
				//Though this does bring us into the realm of hard problems. Purge cache when
				//charsheet closed and reopened maybe?
				async_download("http://"+minstrelhall+":8000/"+line, tokenimage, line);
			}
			GTK2.Hbox cols = GTK2.Hbox(0, 10);
			int per_column = (sizeof(table)+2)/3;
			cols->add(GTK2Table((table/per_column)[*])[*]);
			array excess = table % per_column;
			if (sizeof(excess)) cols->add(GTK2.Vbox(0, 0)->pack_start(GTK2Table(excess), 0,0,0));
			win->box->remove(win->box->get_children()[0]); //Remove the loading message
			win->box->add(GTK2.ScrolledWindow((["hscrollbar-policy": GTK2.POLICY_NEVER]))
				->set_size_request(-1, 400)
				->add(cols)->show_all()
			);
		}

		void start_download(object dns)
		{
			if (dns->pending) return;
			if (!sizeof(dns->ips))
			{
				report_error("Unable to locate Minstrel Hall.");
				return;
			}
			minstrelhall = dns->ips[0];
			async_download("http://"+minstrelhall+":8000/similar/greencircle" + "_large"*large, tokenlist);
		}

		void makewindow()
		{
			win->_parentwindow = charsheet::win->mainwindow;
			win->mainwindow=GTK2.Window((["title":"Select " + "enlarged "*large + "token"]))->add(win->box=GTK2.Vbox(0,0)
				->add(GTK2.Label("Loading, please wait..."))
				->pack_end(GTK2.HbuttonBox()->add(stock_close()),0,0,0)
			);
			DNS("gideon.rosuav.com", start_download);
		}

		//Force everything to be cleaned up on window close
		void closewindow() {::closewindow(); destruct();}
		protected void destroy()
		{
			destruct(win->blank);
			if (win->images)
			{
				destruct(values(win->images)[*]);
				destruct(values(win->img)[*]);
				destruct(values(win->bmp)[*]);
			}
		}
		protected void _destruct() {destroy();}
	}
	program sig_pick_large_token_clicked = sig_pick_token_clicked;

	//Subclasses can override this (or mutate it) to quickly change the spells-per-day info.
	//Keep the class names to lowercase ASCII.
	mapping spells_per_day = ([
		"bard":({"CHA",
			({2}),
			({3,0}),
			({3,1}),
			({3,2,0}),
			({3,3,1}),
			({3,3,2}),
			({3,3,2,0}),
			({3,3,3,1}),
			({3,3,3,2}),
			({3,3,3,2,0}), //10
			({3,3,3,3,1}),
			({3,3,3,3,2}),
			({3,3,3,3,2,0}),
			({4,3,3,3,3,1}),
			({4,4,3,3,3,2}),
			({4,4,4,3,3,2,0}),
			({4,4,4,4,3,3,1}),
			({4,4,4,4,4,3,2}),
			({4,4,4,4,4,4,3}),
			({4,4,4,4,4,4,4}),
		}),
		"cleric":({"WIS",
			({3,1}),
			({4,2}),
			({4,2,1}),
			({5,3,2}),
			({5,3,2,1}),
			({5,3,3,2}),
			({6,4,3,2,1}),
			({6,4,3,3,2}),
			({6,4,4,3,2,1}),
			({6,4,4,3,3,2}),
			({6,5,4,4,3,2,1}),
			({6,5,4,4,3,3,2}),
			({6,5,5,4,4,3,2,1}),
			({6,5,5,4,4,3,3,2}),
			({6,5,5,5,4,4,3,2,1}),
			({6,5,5,5,4,4,3,3,2}),
			({6,5,5,5,5,4,4,3,2,1}),
			({6,5,5,5,5,4,4,3,3,2}),
			({6,5,5,5,5,5,4,4,3,3}),
			({6,5,5,5,5,5,4,4,4,4}),
		}),
		"druid":({"WIS",
			({3,1}),
			({4,2}),
			({4,2,1}),
			({5,3,2}),
			({5,3,2,1}),
			({5,3,3,2}),
			({6,4,3,2,1}),
			({6,4,4,3,2,1}),
			({6,4,4,3,3,2}),
			({6,5,4,4,3,2,1}),
			({6,5,4,4,3,3,2}),
			({6,5,5,4,4,3,2,1}),
			({6,5,5,4,4,3,3,2}),
			({6,5,5,5,4,4,3,2,1}),
			({6,5,5,5,4,4,3,3,2}),
			({6,5,5,5,5,4,4,3,2,1}),
			({6,5,5,5,5,4,4,3,3,2}),
			({6,5,5,5,5,5,4,4,3,3}),
			({6,5,5,5,5,5,4,4,4,4}),
		}),
		"paladin":({"WIS",
			({ }),
			({ }),
			({ }), //No spells for three levels (detect evil isn't counted)
			({"",0}),
			({"",0}),
			({"",1}),
			({"",1}),
			({"",1,0}),
			({"",1,0}),
			({"",1,1}),
			({"",1,1,0}),
			({"",1,1,1}),
			({"",1,1,1}),
			({"",2,1,1,0}),
			({"",2,1,1,1}),
			({"",2,2,1,1}),
			({"",2,2,2,1}),
			({"",3,2,2,1}),
			({"",3,3,3,2}),
			({"",3,3,3,3}),
		}),
		"ranger":({"WIS", //Exact duplicate of paladin stats!
			({ }),
			({ }),
			({ }),
			({"",0}),
			({"",0}),
			({"",1}),
			({"",1}),
			({"",1,0}),
			({"",1,0}),
			({"",1,1}),
			({"",1,1,0}),
			({"",1,1,1}),
			({"",1,1,1}),
			({"",2,1,1,0}),
			({"",2,1,1,1}),
			({"",2,2,1,1}),
			({"",2,2,2,1}),
			({"",3,2,2,1}),
			({"",3,3,3,2}),
			({"",3,3,3,3}),
		}),
		"sorcerer":({"INT",
			({5,3}),
			({6,4}),
			({6,5}),
			({6,6,3}),
			({6,6,4}),
			({6,6,5,3}),
			({6,6,6,4}),
			({6,6,6,5,3}),
			({6,6,6,6,4}),
			({6,6,6,6,5,3}),
			({6,6,6,6,6,4}),
			({6,6,6,6,6,5,3}),
			({6,6,6,6,6,6,4}),
			({6,6,6,6,6,6,5,3}),
			({6,6,6,6,6,6,6,4}),
			({6,6,6,6,6,6,6,5,3}),
			({6,6,6,6,6,6,6,6,4}),
			({6,6,6,6,6,6,6,6,6}),
		}),
		"wizard":({"INT",
			({3,1}),
			({4,2}),
			({4,2,1}),
			({4,3,2}),
			({4,3,2,1}),
			({4,3,3,2}),
			({4,4,3,2,1}),
			({4,4,3,3,2}),
			({4,4,4,3,2,1}),
			({4,4,4,3,3,2}),
			({4,4,4,4,3,2,1}),
			({4,4,4,4,3,3,2}),
			({4,4,4,4,4,3,2,1}),
			({4,4,4,4,4,3,3,2}),
			({4,4,4,4,4,4,3,2,1}),
			({4,4,4,4,4,4,3,3,2}),
			({4,4,4,4,4,4,4,3,2,1}),
			({4,4,4,4,4,4,4,3,3,2}),
			({4,4,4,4,4,4,4,4,3,3}),
			({4,4,4,4,4,4,4,4,4,4}),
		}),
	]);

	GTK2.Widget spells_per_day_box()
	{
		GTK2.Vbox spells = win->spells_per_day;
		if (!spells) spells = win->spells_per_day = GTK2.Vbox(0,10)->add(GTK2.Label("Remove me"));
		spells->remove(spells->get_children()[*]);
		for (int i=1;i<10;++i)
		{
			depends["class"+i] += ({spells_per_day_box});
			depends["level"+i] += ({spells_per_day_box});
			array info=spells_per_day[lower_case(data["class"+i] || "")];
			if (info)
			{
				array desc=allocate(10,"");
				//If you're at epic level and the tables haven't been updated, use the highest available info.
				//(Not that epic level data would be hard or anything. I just haven't done it.)
				int lvl=min((int)data["level"+i], sizeof(info)-1); if (!lvl) continue;
				string stat = info[0];
				int max = (int)data[stat] - 10; //With a spell stat of 15, you can cast 5th tier spells but not 6th.
				int bonusspells = (int)data[stat+"_mod"] + 4;
				depends[stat] += ({spells_per_day_box});
				depends[stat+"_mod"] += ({spells_per_day_box});
				foreach (info[lvl];int i;string|int spells) if (intp(spells)) //A blank slot indicates complete absence of spells at that tier (but 0 means "only bonus spells")
				{
					int tierbonus = (bonusspells-i)/4;
					if (!i || tierbonus < 0) tierbonus = 0;
					desc[i] = i>max ? stat : (string)(spells + tierbonus);
				}
				spells->pack_start(GTK2.Frame(data["class"+i]+" spells per day per level/tier")->add(GTK2Table(({
					({"L0","L1","L2","L3","L4","L5","L6","L7","L8","L9"}),
					GTK2.Label(desc[*]), //Explicitly labellify the strings so they don't get noex'd
				}))),0,0,0);
			}
		}
		return spells->show_all();
	}

	GTK2.Widget Page_Spells()
	{
		return GTK2.Vbox(0,10)->pack_start(spells_per_day_box(),0,0,0)
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
					foreach (({10,10,15,15,15,15,15,15,15,8});int tier;int rowcount) //Number of slots per tier is a bit arbitrary.
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
				}())));
	}

	GTK2.Widget Page_Administrivia()
	{
		return GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Permissions")->add(GTK2.Vbox(0,0)
					->pack_start(GTK2.Label((["label":
						"Your own account always has full access. You may grant access to any other account or character here; "
						"on save, the server will translate these names into canonical account names. You will normally want to "
						"name your Dungeon Master here, unless of course you are the DM. Note that there is no provision for "
						"read-only access - you have to trust your DM anyway.","wrap":1])),0,0,0)
					->pack_start(ef("perms"),0,0,0)
				),0,0,0)
				->pack_start(GTK2.Hbox(0,10)
					->pack_start(GTK2.Label("Char sheet layout"),0,0,0)
					->pack_start(win->ddcb_cs_type=select("cs_type",cs_types),0,0,0)
					->add(win->lbl_cs_type=GTK2.Label(""))
				,0,0,0)
				->pack_start(GTK2.Hbox(0, 10)
					->add(GTK2.Frame("Default dice roll")->add(GTK2Table(({
						({noex(ef("roll_default", 8)), win->set_roll_default = noex(GTK2.Button("Use " + roll_default))}),
						({"Used with abbreviated dice roll notation\n'roll 10d' will become 'roll 10" + roll_default + "'.", 0}),
					}))))
					->add(GTK2.Frame("Attribute roll")->add(GTK2Table(({
						({noex(ef("roll_attribute", 8)), win->set_roll_attribute = noex(GTK2.Button("Use " + roll_attribute))}),
						({
							"Not currently used. It's on my fixme list.\n"
							"'roll init' will become 'roll " + roll_attribute + "'\n"
							"where # is your init value.",
							0,
						}),
					}))))
				,0,0,0)
				->pack_start(win->lbl_cs_type_changed=GTK2.Label(""),0,0,0)
				->add((object)(GTK2.Frame("Notes")->add(GTK2.ScrolledWindow()->add((object)(mle("notes")->set_wrap_mode(GTK2.WRAP_WORD))))));
	}

	void sig_set_roll_default_clicked() {set_value("roll_default", roll_default);}
	void sig_set_roll_attribute_clicked() {set_value("roll_attribute", roll_attribute);}

	GTK2.Widget Page_Help()
	{
		data["note_help_notes"]="Demo note"; //Note that the user can edit the note, and even blank it. Foot, bullet, bang.
		return GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Styles")->add(two_column(({
					"This is a string entry field. It takes words.",ef("help_ef"),
					"This entry field has notes attached. Press F2 to edit notes.",ef("help_notes"),
					"This is a numeric entry field.",num("help_num"),
					"This is a rarely-used field. You'll normally leave it blank.",rare(num("help_rare")),
					"This field is calculated as the sum of the above two.",calc("help_num+help_rare"),
					"This is something you'll want to read off.",readme("Save vs help",calc("10+help_num+help_rare")),
				}))),0,0,0)
				->add(GTK2.Label((["label":"Whenever you update something here, it can affect your roll aliases. Check 'help roll alias' in game for details.","wrap":1])));
	}

	void sig_ddcb_cs_type_changed()
	{
		string type=win->ddcb_cs_type->get_text();
		string changed="This change will take effect next time you open this sheet.";
		if ("charsheet_"+type==function_name(this_program)) {type="Current type: "+cs_descr[type]; changed="";}
		else type="Changing to: "+cs_descr[type];
		win->lbl_cs_type->set_text(type);
		win->lbl_cs_type_changed->set_text(changed);
	}

	void makewindow()
	{
		GTK2.Notebook nb=GTK2.Notebook();
		foreach (pages, string page)
			nb->append_page((object)(this["Page_"+replace(page," ","_")]()), GTK2.Label(page));
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)")]))
			->add(nb)
			->add_accel_group(GTK2.AccelGroup()
				->connect(0xFFBF,0,0,edit_notes_f2,0)
			)
		;
		::makewindow();
	}

	void sig_mainwindow_destroy()
	{
		charsheets[owner][this]=0;
		destruct();
	}

	void edit_notes_f2() {edit_notes(win->mainwindow->get_focus());}
	class edit_notes(object ef)
	{
		inherit window;
		string kwd;
		protected void create()
		{
			kwd = ef_kwd[ef];
			if (!kwd) {MessageBox(0,0,GTK2.BUTTONS_OK,"Unable to store notes there",charsheet::win->mainwindow); return;}
			::create();
		}

		void makewindow()
		{
			win->_parentwindow = charsheet::win->mainwindow;
			win->mainwindow=GTK2.Window((["title":"Notes for "+kwd]))->add(GTK2.Vbox(0,0)
				->add(win->mle=MultiLineEntryField()
					->set_text(data["note_"+kwd]||"")
					->set_size_request(200,150)
				)
				->pack_start(GTK2.HbuttonBox()->add(stock_close()),0,0,0)
			);
		}

		void closewindow()
		{
			string txt = win->mle->get_text();
			set_value("note_"+kwd, txt);
			#if constant(GTK2.ENTRY_ICON_SECONDARY)
			if (txt == "") ef->set_icon_from_pixbuf(GTK2.ENTRY_ICON_SECONDARY,0);
			else ef->set_icon_from_stock(GTK2.ENTRY_ICON_SECONDARY,GTK2.STOCK_EDIT);
			#endif
			::closewindow();
		}
	}

	//Level up assistant
	class sig_tnl_clicked
	{
		inherit window;
		protected void create() {::create();}

		//Note that the BAB and save arrays start with a 0 entry for having zero levels in that class.
		//This allows notations involving the difference between the current level and the previous.
		constant bab=([
			"Good":enumerate(21,1), //Going beyond level 20 should work easily enough if you need epic levels.
			"Avg": enumerate(21,3)[*]/4,
			"Poor":enumerate(21,1)[*]/2
		]);
		constant saves=([
			"Good": ({0})+enumerate(20,1,5)[*]/2,
			"Poor": enumerate(21)[*]/3
		]);
		mapping classes=([
			"Barbarian": (["clsskills": "Bbn",
				"hd": 12, "skills": 4, "bab": "Good",
				"fort": "Good", "refl": "Poor", "will": "Poor",
				"dontforget": "",
			]),"Bard": (["clsskills": "Brd",
				"hd": 6,  "skills": 6, "bab": "Avg",
				"fort": "Poor", "refl": "Good", "will": "Good",
				"dontforget": "",
			]),"Cleric": (["clsskills": "Clr",
				"hd": 8,  "skills": 2, "bab": "Avg",
				"fort": "Good", "refl": "Poor", "will": "Good",
				"dontforget": "",
			]),"Druid": (["clsskills": "Drd",
				"hd": 8,  "skills": 4, "bab": "Avg",
				"fort": "Good", "refl": "Poor", "will": "Good",
				"dontforget": "",
			]),"Fighter": (["clsskills": "Ftr",
				"hd": 10, "skills": 2, "bab": "Good",
				"fort": "Good", "refl": "Poor", "will": "Poor",
				"dontforget": "Don't forget: Fighter bonus feat",
			]),"Monk": (["clsskills": "Mnk",
				"hd": 8,  "skills": 4, "bab": "Avg",
				"fort": "Good", "refl": "Good", "will": "Good",
				"dontforget": "",
			]),"Paladin": (["clsskills": "Pal",
				"hd": 10, "skills": 2, "bab": "Good",
				"fort": "Good", "refl": "Poor", "will": "Poor",
				"dontforget": "",
			]),"Ranger": (["clsskills": "Rgr",
				"hd": 8,  "skills": 6, "bab": "Good",
				"fort": "Good", "refl": "Good", "will": "Poor",
				"dontforget": "",
			]),"Rogue": (["clsskills": "Rog",
				"hd": 6,  "skills": 8, "bab": "Avg",
				"fort": "Poor", "refl": "Good", "will": "Poor",
				"dontforget": "",
			]),"Sorcerer": (["clsskills": "Sor",
				"hd": 4,  "skills": 2, "bab": "Poor",
				"fort": "Poor", "refl": "Poor", "will": "Good",
				"dontforget": "Don't forget: Learn new spells",
			]),"Wizard": (["clsskills": "Wiz",
				"hd": 4,  "skills": 2, "bab": "Poor",
				"fort": "Poor", "refl": "Poor", "will": "Good",
				"dontforget": "Don't forget: Learn new spells",
			]),
			//TODO: Add some non-PHB classes, but make them invisible unless
			//already selected. Then you can put one in at level 1, and then
			//level up in them with the assistant. (You already can't take
			//level 1 with this, so the only cost is that you can't cross-class
			//to a non-PHB class this way.)
			//Even better would be to have these classes somehow exist in the
			//charsheet itself. Not sure how that would be done, though.
			//Or alternatively, let DMs register new classes???
			//For this to be practical, it needs to encode as a single simple
			//string, which people can copy/paste. That would improve the
			//readability of this code, too. We can probably ignore the class
			//skills list for now, and use a string somewhat thus:
			//"Wizard": "Wiz, 4 hd, 2 skills, Poor BAB, Poor/Poor/Good saves, Don't forget: Learn new spells"
			//This would be a very strict format. It looks human readable, but
			//it's not flexible. "%s, %d hd, %d skills, %s BAB, %s/%s/%s saves, %s"
			//to get all the information exactly as per the above.
			//Leave this until it's needed by a DM. I don't personally need it
			//(Lumina uses a different client), and this needs someone to use
			//it live before it can be depended on.
		]);
		array recalc=({ });

		//Uses sprintf args based on the currently-selected class
		GTK2.Entry prefill(string fmt,string ... args)
		{
			object obj=GTK2.Entry();
			recalc+=({({obj,fmt,args})});
			return obj;
		}
		GTK2.Label display(string fmt,string ... args)
		{
			object obj=GTK2.Label();
			recalc+=({({obj,fmt,args})});
			return obj;
		}

		void calcskills()
		{
			string cls=win->ddcb_class->get_text();
			mapping classinfo=classes[cls] || ([]);
			array sk=class_skills[classinfo->clsskills] || ({ });
			int spent=0;
			foreach (skillnames;string n;) spent += (2-has_value(sk,n)) * (int)win["skill_"+n]->get_text();
			win->skillpoints->set_text(sprintf("%d/%d",spent,classinfo->skills));
		}

		//Magic object that can sprintf as anything
		object unknown=class{protected string _sprintf(int c) {return "??";}}();
		void sig_ddcb_class_changed()
		{
			string cls=win->ddcb_class->get_text();
			mapping classinfo=classes[cls] || ([]);
			foreach (recalc,[GTK2.Widget obj,string fmt,array(string) args])
			{
				array clsargs=allocate(sizeof(args));
				foreach (args;int i;string kwd) clsargs[i]=has_index(classinfo,kwd)?classinfo[kwd]:unknown;
				obj->set_text(sprintf(fmt,@clsargs));
			}
			if (win->sk1->get_child()) {win->sk1->remove(win->sk1->get_child()); win->sk2->remove(win->sk2->get_child());}
			array sk=class_skills[classinfo->clsskills] || ({ });
			array tb=({({ }),({ })});
			foreach (sort(indices(skillnames)),string s)
			{
				(win["skill_"+s]=GTK2.Entry())->signal_connect("changed",calcskills);
				tb[has_value(sk,s)]+=({skillnames[s],win["skill_"+s]});
			}
			if (!sizeof(tb[1])) tb[1]=({"(pick a class)",0}); //Trust that tb[0] can't be empty
			win->sk1->add(two_column(tb[1])->show_all());
			win->sk2->add(two_column(tb[0])->show_all());
			calcskills();
		}

		void makewindow()
		{
			win->_parentwindow = charsheet::win->mainwindow;
			array stuff;
			int lvl=(int)data->level;
			if (!lvl)
				stuff=({"This assistant cannot be used for first level.",0});
			else if (`+(@enumerate(lvl,1000,1000))>(int)data->xp)
				stuff=({"You're not ready to level up yet. Sorry!",0});
			else
			{
				++lvl; //It's more useful to look at which level we're _gaining_, not the one we already have.

				//Start with the standard PHB classes. If the player currently has any of them,
				//move them to the top with a separator.
				array all_classes=indices(classes),cur_cls=({ });
				for (int i=1;i<10;++i) //There are only 4 entryfields up above (as of 20151024), but hey, more might be added!
				{
					string cls=String.sillycaps(data["class"+i] || "");
					if (has_value(all_classes,cls)) {cur_cls+=({cls}); all_classes-=({cls});}
					if (cls=="Fighter" && !(1&(int)data["level"+i])) classes->Fighter->dontforget=""; //Fighter bonus feat every second level only
				}
				if (sizeof(cur_cls)) all_classes=cur_cls+({""})+all_classes;
				//Precalculate some things for convenience
				foreach (classes;string cls;mapping info)
				{
					info->fixedhp = max(info->hd/2 + !((int)data->level&1) + (int)data->CON_mod, 1);
					info->skilldesc = info->skills+"+INT";
					if (data->race=="Human") {++info->skills; info->skilldesc+="+1";} //Humans get another skill point per level
					info->skills += (int)data->INT_mod;
				}
				stuff=({
					GTK2.Label("Ready to level up!"),0,
					GTK2.Label("NOTE: This is an assistant, nothing more. You\nare responsible for your own character sheet."),0,
					"Choose a class",(object)(win->ddcb_class=SelectBox(all_classes)->set_row_separator_func((function)lambda(object store,object iter) {return store->get_value(iter,0)=="";},0)),
					display("Hit points (roll d%d+"+data->CON_mod+")","hd"),win->hp=prefill("%d","fixedhp"),
					"BAB improvement",win->bab=prefill("%s","bab"),
					"Fort save improvement",win->fort=prefill("%s","fort"),
					"Refl save improvement",win->refl=prefill("%s","refl"),
					"Will save improvement",win->will=prefill("%s","will"),
					!(lvl%4) && "Stat increase", !(lvl%4) && (win->stat=SelectBox("STR INT WIS DEX CON CHA"/" ")),
					!(lvl%3) && "New feat", !(lvl%3) && (win->feat=GTK2.Entry()),
					!(lvl%3) && (win->feat_benefit=GTK2.Entry()), 0,
					display("%s","dontforget"), 0,
					display("Skill points: %s","skilldesc"), win->skillpoints=GTK2.Label("0/0"),
					GTK2.Frame("Class skills")->add(win->sk1=GTK2.ScrolledWindow((["hscrollbar-policy":GTK2.POLICY_NEVER]))->set_size_request(-1,150)),0,
					GTK2.Frame("Cross-class skills (double cost)")->add(win->sk2=GTK2.ScrolledWindow((["hscrollbar-policy":GTK2.POLICY_NEVER]))->set_size_request(-1,150)),0,
					win->pb_ding=GTK2.Button("Ding!"),0,
				});
				//If you're currently single-class, default to advancing in that class.
				//You can always drop the list down and pick something else.
				//Note that this will also pick up the case where you have one PHB
				//class and one or more other classes (eg prestige classes). It'll
				//assume that you want to advance in the PHB class. Since this tool
				//can't be used for prestige classes anyway, this shouldn't be too bad.
				if (sizeof(cur_cls)==1) win->ddcb_class->set_text(cur_cls[0]);
				sig_ddcb_class_changed();
			}
			win->mainwindow=GTK2.Window((["title":"Level up assistant"]))
				->add(two_column(stuff+({stock_close(),0})));
			::makewindow();
		}

		//Convenience function for working with integers
		int add_value(string kwd,int|string val)
		{
			val=(int)data[kwd]+(int)val;
			set_value(kwd,(string)val);
			return val;
		}

		void sig_pb_ding_clicked()
		{
			string cls=win->ddcb_class->get_text();
			int classpos;
			for (int i=1;i<10;++i)
				if (data["class"+i]==cls) {classpos=i; break;} //Found it.
				else if (!classpos && (<0,"">)[data["class"+i]]) classpos=i; //Found an empty slot - use that if no other found.
			if (!classpos) {MessageBox(0,GTK2.MESSAGE_ERROR,GTK2.BUTTONS_OK,"Cannot multiclass so broadly with this assistant!",win->mainwindow); return;}
			int level=add_value("level",1), clslevel=add_value("level"+classpos,1);
			set_value("class"+classpos,cls);
			add_value("hp",win->hp->get_text());
			array bab=bab[win->bab->get_text()] || ({0})*21;
			add_value("bab",bab[clslevel]-bab[clslevel-1]);
			foreach (({"fort","refl","will"}),string save)
			{
				array mod=saves[win[save]->get_text()] || ({0})*21;
				add_value(save+"_base",mod[clslevel]-mod[clslevel-1]);
			}
			if (win->stat)
			{
				string stat=win->stat->get_text();
				int val=stat!="" && add_value(win->stat->get_text(),1);
				if (stat=="CON" && !(val&1)) add_value("hp",level); //CON increase changes modifier? Gain 1 hp/level!
				//Note that increasing your INT modifier will permit you another skill point this level,
				//which isn't taken into account. But the skill point counting is advisory anyway.
			}
			if (win->feat) for (int i=0;i<20;++i) if ((<0,"">)[data["feat_"+i]])
			{
				set_value("feat_"+i,win->feat->get_text());
				set_value("feat_benefit_"+i,win->feat_benefit->get_text());
				break;
			}
			foreach (win;string kwd;mixed data) if (sscanf(kwd,"skill_%s",string sk) && sk)
				if (int value=(int)data->get_text()) add_value(sk+"_rank",value);
			closewindow();
		}
	}
}

//To create new charsheet designs, copy existing pages where possible, or
//create new pages that use the same data where possible. Use unique names
//for unique fields, and common names for broadly common fields, like stats.
class charsheet_35ed
{
	inherit charsheet;
	constant desc="3.5th Ed";
	constant roll_default = "d20";
	constant roll_attribute = "d20 + #";
}

class charsheet_npc
{
	inherit charsheet;
	constant desc="Cut-down NPC sheet";
	constant pages = ({"Vital Stats", "Gear", "Feats", "Spells", "Administrivia"});
	//TODO: Also simplify some of the pages themselves (by overriding)
}

class charsheet_exalted
{
	inherit charsheet;
	constant desc = "Exalted";
	constant pages = ({"Vital Stats", "Gear", "Inven", "Description", "Skills", "Token", "Administrivia", "Help"});
	constant roll_default = "d7/10";
	constant roll_attribute = "#d";

	GTK2.Widget Page_Vital_Stats()
	{
		return GTK2.Vbox(0,20)
				->pack_start(GTK2.Hbox(0,10)
					->add(GTK2Table(({
						({"Name", ef("name", 8), 0}),
						({"Caste", ef("caste", 8), 0}),
						({"XP", num("xp"), num("xp_tot")}),
					})))
					->add(GTK2Table(({
						({"Essence", "Cur", "Max"}),
						({"Personal", num("snc_pers_cur"), num("snc_pers_max")}),
						({"Peripheral", num("snc_peri_cur"), num("snc_peri_max")}),
						({"Committed", rare(num("snc_commit")), 0}),
					})))
					->add(GTK2Table(({
						({"Anima", ef("anima", 8)}),
						({"Supernal", ef("supernal", 8)}),
					})))
				,0,0,0)
				->add(GTK2.Hbox(0,20)
					->add(GTK2.Frame("Attributes")->add(GTK2Table(
						map("STR DEX STA CHA MAN APP PER INT WIT" / " ", lambda(string stat) {return ({
							stat, num(stat + "_mod"),
						});})
					)))
					->add(GTK2.Vbox(0,10)
						->pack_start(GTK2.Frame("Health")->add(GTK2Table(({
							({"Ox Body", rare(num("oxbody"))}),
							({"Bashing", spinner("dmg_bashing", 0.0, 100.0, 1.0)}),
							({"Lethal", spinner("dmg_lethal", 0.0, 100.0, 1.0)}),
							({"Aggravated", spinner("dmg_aggravated", 0.0, 100.0, 1.0)}),
							({"Penalty", readme(0, calc("exalted_damage(oxbody, dmg_bashing, dmg_lethal, dmg_aggravated)", "wound"))}),
						}))), 0, 0, 0)
						->pack_start(GTK2.Frame("Willpower")->add(GTK2Table(({
							({"Cur", "Max"}),
							({num("willpower_cur"), num("willpower")}),
						}))), 0, 0, 0)
					)
					->add(GTK2.Frame("Combat")->add(two_column(({
						"Parry", calc("(DEX_mod + deref(\"weapon_skill\") + 1) / 2 + weapon_def", "parry"),
						"Evasion", calc("(DEX_mod + dodge + 1) / 2 + armor_mp", "evasion"),
						"Defense", readme(0, calc("parry > evasion ? parry : evasion")),
						"Rush", calc("DEX_mod + athletics + armor_mp", "rush"),
						"Resolve", calc("(WIT_mod + integrity + 1) / 2", "resolve"),
						"Guile", calc("(MAN_mod + socialize + 1) / 2", "guile"),
						"Disengage", calc("DEX_mod + dodge + armor_mp", "disengage"),
						"Join Battle", readme(0, calc("WIT_mod + awareness", "init")),
					}))))
				)
				->add(GTK2.Hbox(0,20)
					->add(GTK2.Frame("Soak")->add(GTK2Table(({
						({"Nat", "Armor", "Total"}),
						({calc("STA_mod"), calc("armor_soak"), calc("STA_mod + armor_soak", "soak")}),
					}))))
					->add(GTK2.Frame("Hardness")->add(GTK2Table(({
						({"Nat","Armor","Total"}),
						({num("hardness_intrinsic"), calc("armor_hard"), calc("hardness_intrinsic + armor_hard", "hardness")}),
					}))))
				);
	}

	GTK2.Widget Page_Gear()
	{
		array armor = ({({"Name", "Soak", "Hard", "MP", "Tags"})});
		array weapons = ({({"Name", "Acc", "Dmg", "Def", "Ovw", "Skill", "Tags", "Wth", "Dcs"})});
		string total = "";
		array(string) weaponfields = ({ }), weapondefaults = ({ });
		for (int i = 1; i <= 3; ++i)
		{
			armor += ({({
				ef("armor_" + i, 10),
				noex(num("armor_" + i + "_soak")),
				noex(num("armor_" + i + "_hard")),
				noex(num("armor_" + i + "_mp")),
				ef("armor_" + i + "_tags", 15),
			})});
			total += "+ armor_" + i + "_%[0]s";
			weapons += ({({
				ef("weapon_" + i, 10),
				noex(num("weapon_" + i + "_acc")),
				noex(num("weapon_" + i + "_dmg")),
				noex(num("weapon_" + i + "_def")),
				noex(num("weapon_" + i + "_ovw")),
				select("weapon_" + i + "_skill", ({"Archery", "Brawl", "Melee", "Thrown", "MartialArts"})),
				ef("weapon_" + i + "_tags", 15),
				calc("DEX_mod + deref(\"weapon_" + i + "_skill\") + weapon_" + i + "_acc", "weapon_" + i + "_wth"),
				calc("DEX_mod + deref(\"weapon_" + i + "_skill\")", "weapon_" + i + "_dcs"),
			})});
			weaponfields += ({"weapon_" + i}); weapondefaults += ({"Weapon " + i});
		}
		armor += ({({
			"Total",
			calc(sprintf(total[2..], "soak"), "armor_soak"),
			calc(sprintf(total[2..], "hard"), "armor_hard"),
			calc(sprintf(total[2..], "mp"), "armor_mp"),
			"(MP should be a negative number)",
		})});
		array active = ({picker("weapon_active", weaponfields, weapondefaults)});
		foreach ("acc dmg def ovw skill tags wth dcs" / " ", string attr)
			active += ({calc("val(\"weapon_\" + weapon_active + \"_" + attr + "\")", "weapon_" + attr, "string")});
		weapons += ({active});
		return GTK2.Vbox(0,20)
				->pack_start(GTK2.Frame("Weapons")->add(GTK2Table(weapons)), 0, 0, 0)
				->pack_start(GTK2.Frame("Armor")->add(GTK2Table(armor)), 0, 0, 0)
		;
	}

	GTK2.Widget Page_Skills()
	{
		return GTK2.ScrolledWindow()->add(GTK2.Hbox(0, 0)->pack_start(GTK2Table(
				({({"Exc", "Fav", "Name", "Skill", "Specialties"})})
				+map((
					"Archery Athletics Awareness Brawl Bureaucracy Craft Dodge "
					"Integrity Investigation Larceny Linguistics Lore Martial-Arts "
					"Medicine Melee Occult Performance Presence Resistance Ride "
					"Sail Socialize Stealth Survival Thrown War"
				) / " ", lambda(string name) {
					string id = replace(lower_case(name), "-", "");
					return ({cb(id + "_exc", ""), cb(id + "_fav", ""), replace(name, "-", " "), num(id), ef(id + "_spec", 30)});
				})
		), 0, 0, 0));
	}

	//TODO later: Specializations, merits, limit break/limit trigger
}

int output(mapping(string:mixed) subw,string line)
{
	if (sscanf(line,"===> URL: %s", string url))
	{
		//Used for the battle grid
		invoke_browser(url);
		return 0;
	}
	if (sscanf(line,"===> Charsheet @%s <===",string acct))
	{
		subw->charsheet_eax=""; subw->charsheet_acct=acct;
		return 0;
	}
	if (sscanf(line,"===> Charsheet @%s qset %s %s",string acct,string what,string|int towhat))
	{
		towhat = Standards.JSON.decode(towhat);
		if (multiset sheets=charsheets[acct]) indices(sheets)->set(what,towhat||"");
		return 1; //Suppress the spam
	}
	if (subw->charsheet_eax)
	{
		if (line=="<=== Charsheet ===>")
		{
			string raw = m_delete(subw,"charsheet_eax");
			mixed data;
			//Currently, "charsheet" emits B64+encode_value, and
			//"charsheet json" emits JSON. Accept either. Later,
			//the default will be JSON; eventually, *only* JSON.
			catch {data=decode_value(MIME.decode_base64(raw));};
			if (!data) catch {data=Standards.JSON.decode(raw);};
			if (mappingp(data))
			{
				program cs_type = this["charsheet_"+data->cs_type] || charsheet;
				cs_type(subw,m_delete(subw,"charsheet_acct"),data);
			}
			return 1;
		}
		subw->charsheet_eax+=line+"\n";
		return 1;
	}
}

protected void create(string name)
{
	::create(name);
	if (!G->G->charsheets) G->G->charsheets=([]);
	charsheets=G->G->charsheets;
}
