constant docstring=#"
Pop-out character sheet renderer for Minstrel Hall

Carefully matched to the corresponding code on the server, this will pop out a
character sheet based on data stored on the server.
";

inherit hook;

constant plugin_active_by_default = 1;

mapping(string:multiset(object)) charsheets;

//TODO: Figure out why this is sometimes disgustingly laggy on Sikorsky. Is it because
//I update code so much? Are old versions of the code getting left around? Worse, is it
//that the window isn't getting properly disposed of when it closes? I've never managed
//to actually recreate the problem in a stress-test. :(
//May not be happening any more - not sure. At any rate, it's not so laggy, and I've had
//Gypsum up for the past month-ish.

//TODO: Figure out a way to have multiple completely different character sheet designs.
//This is the 3.5ed one; a new 5ed one may be coming along, and any others should then
//be easy. The server shouldn't mind (it cares about very few identifiers), so this
//can basically be client-selectable. Ideally, it should be possible to have multiple
//different charsheets active simultaneously; this may require something that saves to
//a special type flag or something on the server. How do you choose when doing up a
//brand new charsheet though?? Hmm.
//Maybe the mode-switch should be done client-side. When you change it, it closes and
//reopens, and you see a completely new layout... UI nightmare or elegant hack?
//Also, to what extent should distinct charsheets share content? As much as possible,
//or only where it truly has the exact same semantics?

//Should roll aliases be controlled by the server or the client? I could give full
//control to the client, and then it'd all be in one logical place (and they could be
//done by sending the regular 'roll alias' command, even); then things like saves
//could use different dice rolls for different systems, without hacks.
/* Current server-side roll alias creation looks like this; ra is roll aliases, cs is
charsheet, and both are aliases for existing mappings.
				ra->init=sprintf("d20%+d",(int)cs->init);
				foreach ("STR DEX INT WIS CON CHA"/" ",string kwd)
					ra[kwd]=sprintf("d20%+d",(int)cs[kwd+"_mod"]);
				ra->grapple=replace("d20+"+cs->grapple,"+-","-");
				ra["Fort save"]=sprintf("d20%+d",(int)cs->fort_save);
				ra["Refl save"]=ra["Reflex save"]=sprintf("d20%+d",(int)cs->refl_save);
				ra["Will save"]=sprintf("d20%+d",(int)cs->will_save);
				multiset(string) done_kwd=(<>);
				foreach (sort(indices(cs)),string kwd)
				{
					if (sscanf(kwd,"attack_%s",string kw) && !has_value(kw,"_"))
					{
						if (done_kwd[kw]) continue; done_kwd[kw]=1; //First one found wins.
						string rollkw=cs[kwd]||""; if (rollkw!="") rollkw+=" ";
						foreach (({"hit","dmg","crit"}),string mode)
							if (string val=cs[kwd+"_"+mode]) ra[rollkw+mode]=val;
						if (string val=cs[kwd+"_hit"]) ra[rollkw+"to-hit"]=ra[rollkw+"to-crit"]=val;
					}
					else if (sscanf(kwd,"skill_%s",string kw))
						ra[kw]=sprintf("d20%+d",(int)cs[kwd]);
				}
*/
//Alias definitions could be done like this. Each braced token becomes a dependency; if it
//changes, the alias is rewritten. Any instance of "+-" gets replaced with "-" for readability.
//Alternatively: Handle aliases by keeping a local record of what we think the server has. Any
//time anything gets changed, zip through the alias definitions, see if any appears to be now
//different from what it was, and if so, submit the change. Would require either querying the
//server on charsheet opening, or assuming no aliases at first, and updating lots of them on
//first edit. Querying would be better; we need a machine-readable dump of aliases - or maybe
//they should simply be auto-provided as part of the charsheet load blob. Alternatively, _only_
//update them when something changes, which means you won't get a bunch of pointless aliases
//the moment you use the charsheet for anything.
//NOTE: As of 20151108, the MH roll engine has been upgraded to better handle charsheet entries
//automatically. Some aliases may therefore be unnecessary; for instance, instead of "roll STR"
//you could use "roll d20+STR", which works without any extra effort.
mapping(string:string) aliases=([
	"init":"d20+{init}",
	"grapple":"d20+{grapple}",
	"Fort save":"d20+{fort_save}", //Renamings might help
	//plus skills and attacks
]);

class charsheet(mapping(string:mixed) subw,string owner,mapping(string:mixed) data)
{
	inherit movablewindow;
	constant is_subwindow=0;
	constant pos_key="charsheet/winpos";
	mapping(string:array(function)) depends=([]); //Whenever something changes, recalculate all its depends.
	mapping(string:string) skillnames=([]); //For the convenience of the level-up assistant, map skill keywords to their names.
	mapping(string:array(string)) class_skills=([]); //Parsed from the primary skill table - which skills are class skills for each class?

	void create()
	{
		if (!charsheets[owner]) charsheets[owner]=(<>);
		charsheets[owner][this]=1;
		::create(); //No name. Each one should be independent.
		foreach (aliases;string alias;string expansion)
		{
			if (sscanf(expansion,"%{%*s{%s}%}",array deps)) foreach (deps,[string dep])
			{
				//TODO: Add a dependency - update 'alias' whenever 'dep' changes
				//Maybe aliases should be callable objects, rather than lambda functions - might be easier.
			}
		}
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
		if (!send(subw,sprintf("charsheet @%s qset %s %q\r\n",owner,kwd,data[kwd])))
			//Can't do much :( But at least warn the user.
			win->mainwindow->set_title("UNSAVED CHARACTER SHEET");
		writepending[kwd]=0;
	}

	void set_value(string kwd,string val,multiset|void beenthere)
	{
		//TODO: Calculate things more than once if necessary, in order to resolve refchains,
		//but without succumbing to refloops (eg x: "y+1", y: "x+1"). Currently, depends are
		//recalculated in the order they were added, which may not always be perfect.
		//Consider using C3 linearization on the graph of deps - if it fails, error out.
		//Or use Kahn 1962: https://en.wikipedia.org/wiki/Topological_sorting
		if (val=="0") val="";
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
		//layout manager or a Frame or something).
		for (GTK2.Widget par=self->get_parent();par;par=par->get_parent())
		{
			if (par->get_hscrollbar) //Is there a better way to detect a GTK2.ScrolledWindow?
			//if (par->get_name()=="GtkScrolledWindow") //Is this reliable?
			//As long as nobody calls set_name(), the default name should be the type name.
			//Lance Dillon proposed adding a function which would retrieve the type name
			//directly, but it wouldn't be in older Pikes anyway, so it's not worth adding.
			//It may be worth putting in a version trap; on the other hand, I've yet to see
			//any false positives from checking for the presence of get_hscrollbar, so while
			//it may not be the clearest way to do things, it does work. No other source file
			//in pike/src/post_modules/GTK2/source/*.pre has get_hscrollbar, so I don't
			//expect any other type of object in the hierarchy to give a false positive.
			{
				mapping alloc=self->allocation();
				par->get_hadjustment()->clamp_page(alloc->x,alloc->x+alloc->width);
				par->get_vadjustment()->clamp_page(alloc->y,alloc->y+alloc->height);
				return;
			}
		}
	}

	/* TODO: Make these entryfields able to record notes.
	If a note is recorded against a field, it needs to have a marker (maybe a colored
	triangle on one corner, like GDocs?), and pressing F2 should show that note. Also
	notes can be created with F2, so what it really means is that a non-blank note is
	represented in some way. Ideally, the note should record who put it there and, if
	possible, when (and/or when it was last edited).

	One possible implementation would be to put the Entry inside an Alignment, inside
	an EventBox, inside an enigma. The Alignment supports padding (EventBoxes don't),
	the EventBox supports color changing (the Alignment doesn't), so the sum total is
	an Entry with a bit of color beside it (as many pixels as the Alignment's padding
	requests). The color of that padding could say "has note" etc. This would consume
	a lot of space if used everywhere, but if it's used only when something has notes
	attached to it, it would be reasonable. On the flip side, that would relayout the
	window completely when a note is added, which is ugly. Hrm. It'd really be better
	to consume a top corner. Can I draw over an entry field somehow? Have another GTK
	object on the same location (maybe one without an X window, and a child of the EF
	if that's possible), on which I draw the overlay??
	*/
	GTK2.Entry ef(string kwd,int|mapping|void width_or_props)
	{
		if (!width_or_props) width_or_props=5;
		if (intp(width_or_props)) width_or_props=(["width-chars":width_or_props]);
		object ret=win[kwd]=GTK2.Entry(width_or_props)->set_text(data[kwd]||"");
		ret->signal_connect("focus-out-event",checkchanged,kwd);
		ret->signal_connect("focus-in-event",ensurevisible);
		return ret;
	}

	//Force a field to be numeric, if at all possible. Formats it differently, and
	//allows summation evaluation.
	GTK2.Entry num(string kwd,int|mapping|void width_or_props)
	{
		numerics[kwd]=1; //Flag it for summation formatting
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

	//Mark that an entry field or MLE is rarely used. Currently done with bg color.
	GTK2.Widget rare(GTK2.Widget wid)
	{
		return wid->modify_base(GTK2.STATE_NORMAL,GTK2.GdkColor(224,192,224));
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
	/* Notes formerly in the docstring:
	Formulas can be entered. They reference the underlying data mapping, NOT the
	coordinates of the cell on some spreadsheet layout, so it's as simple as
	referencing the names used. Full Pike syntax is available, but please be
	aware: The code broadly assumes that the person devising the formula knows
	what s/he is doing. It is entirely possible to break things by mucking that
	up. So take a bit of care, and don't deploy without knowing that it's right. :)
	*/
	GTK2.Widget calc(string formula,string|void name,string|void type,multiset|void dep_collector)
	{
		object lbl=GTK2.Label();
		catch
		{
			if (!type) type="int";
			//Phase zero: Precompile, to get a list of used symbols
			symbols=(<>);
			program p=compile("mixed _="+formula+";",this); //Note: As of Pike 8.1, p must be retained or the compile() call will be optimized out.

			//Phase one: Compile the formula calculator itself.
			function f1=compile(sprintf(
				"%s _(mapping data) {%{"+type+" %s=("+type+")data->%<s;%}return %s;}",
				type,(array)symbols,formula
			))()->_;
			//Phase two: Snapshot a few extra bits of info via a closure.
			void f2(mapping data,multiset beenthere)
			{
				string val=(string)f1(data);
				if (name) set_value(name,val,beenthere);
				lbl->set_text(val);
			};
			if (dep_collector) {dep_collector[f2]=1; return lbl;}
			//if (name) say(0,"%%%% %O: %{%O %}",name,sort((array)symbols)); //Note that nameless calc() blocks don't need to be slotted into the evaluation order.
			foreach ((array)symbols,string dep)
				if (!depends[dep]) depends[dep]=({f2});
				else depends[dep]+=({f2});
			f2(data,(<name>));
		};
		return lbl;
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

	void fixsizes(GTK2.Widget wid)
	{
		mapping sz=wid->size_request();
		wid->set_size_request(sz->width,sz->height);
		fixsizes(wid->get_children()[*]);
	}

	GTK2.Widget Page_Vital_Stats()
	{
		return GTK2.Vbox(0,20)
				->pack_start(GTK2.Hbox(0,10)
					->add(GTK2Table(({
						({"Name",ef("name",12),0,0,"Char level",num("level",8)}),
						({"Race",ef("race",8),"HD",rare(ef("race_hd")),"Experience",num("xp",8)}),
						({"Class",ef("class1",12),"Level",num("level1"),"To next lvl",win->tnl=GTK2.Button()->add(calc("`+(@enumerate(level,1000,1000))-xp"))}),
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
							stat,num(stat),num(stat+"_eq"),rare(num(stat+"_tmp")),
							calc(sprintf("min((%s+%<s_eq+%<s_tmp-10)/2,%<s_max||1000)",stat),stat+"_mod") //TODO: Distinguish DEX_max=="" from DEX_max=="0", and don't cap the former. Not currently possible as DEX_max is just an integer.
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
							({"","Base","Ability","Misc","Total"}),
							({"Fort",num("fort_base"),calc("CON_mod"),rare(num("fort_misc")),calc("fort_base+CON_mod+fort_misc","fort_save")}),
							({"Refl",num("refl_base"),calc("DEX_mod"),rare(num("refl_misc")),calc("refl_base+DEX_mod+refl_misc","refl_save")}),
							({"Will",num("will_base"),calc("WIS_mod"),rare(num("will_misc")),calc("will_base+WIS_mod+will_misc","will_save")}),
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
						"({400,460,520,600,700,800,920,1040,1200,1400})[STR_mod%10] * pow(4,STR/10-2)" //Tremendous strength
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
				->add(GTK2.Frame("Languages known")->add(mle("languages")));
	}

	GTK2.Widget Page_Skills()
	{
		return GTK2.ScrolledWindow()->add(GTK2Table(
				({({"Name","Stat","Mod","Rank","Synergy","Other","Total","Notes"})})
				//	Stat and skill name	Class skill for these classes	Synergies, including Armor Check penalty and conditionals.
				+map(#"INT Appraise		Brd,Rog				Craft 1 (if related), Craft 2 (if related), Craft 3 (if related)
					DEX Balance		Brd,Mnk,Rog			AC, Tumble
					CHA Bluff		Brd,Rog,Sor
					STR Climb		Bbn,Brd,Ftr,Mnk,Rgr,Rog		AC, Use Rope (if climbing rope)
					CON Concentration	Brd,Clr,Drd,Mnk,Pal,Rgr,Sor,Wiz
					INT *Craft 1		Bbn,Brd,Clr,Drd,Ftr,Mnk,Pal,Rgr,Rog,Sor,Wiz
					INT *Craft 2		Bbn,Brd,Clr,Drd,Ftr,Mnk,Pal,Rgr,Rog,Sor,Wiz
					INT *Craft 3		Bbn,Brd,Clr,Drd,Ftr,Mnk,Pal,Rgr,Rog,Sor,Wiz
					INT Decipher Script	Brd,Rog,Wiz
					CHA Diplomacy		Brd,Clr,Drd,Mnk,Pal,Rog		Bluff, Knowledge Local, Sense Motive
					INT Disable Device	Rog
					CHA Disguise		Brd,Rog				Bluff (if acting in character)
					DEX Escape Artist	Brd,Mnk,Rog			AC, Use Rope (if involving ropes)
					INT Forgery		Rog
					CHA Gather Info		Brd,Rog				Knowledge Local
					CHA Handle Animal	Bbn,Drd,Ftr,Pal,Rgr
					WIS Heal		Clr,Drd,Pal,Rgr
					DEX Hide		Bbn,Mnk,Rgr,Rog			AC
					CHA Intimidate		Bbn,Ftr,Rog			Bluff
					STR Jump		Bbn,Brd,Ftr,Mnk,Rgr,Rog		AC, Tumble
					INT Knowledge Arcana	Bbn,Clr,Mnk,Sor,Wiz
					INT Knowledge Local	Brd,Rog,Wiz
					INT Knowledge Nobility	Brd,Pal,Wiz
					INT Knowledge Nature	Brd,Drd,Rgr,Wiz			Survival
					INT *Knowledge 1	Brd,Wiz
					INT *Knowledge 2	Brd,Wiz
					INT *Knowledge 3	Brd,Wiz
					INT *Knowledge 4	Brd,Wiz
					INT *Knowledge 5	Brd,Wiz
					INT *Knowledge 6	Brd,Wiz
					WIS Listen		Bbn,Brd,Drd,Mnk,Rgr,Rog
					DEX Move Silently	Brd,Mnk,Rgr,Rog	AC
					DEX Open Lock		Rog
					CHA *Perform 1		Brd,Mnk,Rog
					CHA *Perform 2		Brd,Mnk,Rog
					CHA *Perform 3		Brd,Mnk,Rog
					WIS *Profession 1	Brd,Clr,Drd,Mnk,Pal,Rgr,Rog,Sor,Wiz
					WIS *Profession 2	Brd,Clr,Drd,Mnk,Pal,Rgr,Rog,Sor,Wiz
					DEX Ride		Bbn,Drd,Ftr,Pal,Rgr		Handle Animal
					INT Search		Rgr,Rog
					WIS Sense Motive	Brd,Mnk,Pal,Rog
					DEX Sleight of Hand	Brd,Rog	AC, Bluff
					INT Spellcraft		Brd,Clr,Drd,Sor,Wiz		Knowledge Arcana, Use Magic Device (if deciphering scroll)
					WIS Spot		Drd,Mnk,Rgr,Rog
					WIS Survival		Bbn,Drd,Rgr			Search (if following tracks)
					STR Swim		Bbn,Brd,Drd,Ftr,Mnk,Rgr,Rog	AC, AC
					DEX Tumble		Brd,Mnk,Rog			AC, Jump
					CHA Use Magic Device	Brd,Rog				Decipher Script (if involving scrolls), Spellcraft (if involving scrolls)
					DEX Use Rope		Rgr,Rog				Escape Artist (if involving bindings)"/"\n",lambda(string s)
				{
					sscanf(s,"%*[\t]%s %[^\t]%*[\t]%[^\t]%*[\t]%s",string stat,string|object desc,string cls,string syn);
					string kwd=replace(lower_case(desc),({"*"," "}),({"","_"}));
					skillnames[kwd]=desc; foreach (cls/",",string c) class_skills[c]+=({kwd});
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
							cancel->signal_connect("clicked",lambda(object self) {self->get_toplevel()->destroy();});
							GTK2.Window((["title":"Synergies","transient-for":win->mainwindow]))
								->add(GTK2.Vbox(0,2)
									->add(GTK2.Frame("Synergies for "+desc)->add(GTK2Table(full_desc)))
									->add(GTK2.HbuttonBox()->add(cancel))
								)
								->show_all();
						});
						foreach (synergies,[string dep,int type,string desc])
							if (!depends[dep]) depends[dep]=({recalc});
							else depends[dep]+=({recalc});
						recalc(data,(<kwd+"_synergy">));
					}
					return ({
						desc,stat,noex(calc(stat+"_mod")),noex(num(kwd+"_rank")),synergy_desc,rare(noex(num(kwd+"_other"))),
						noex(calc(sprintf("%s_mod+%s_rank+%<s_synergy+%<s_other",stat,kwd),"skill_"+kwd)),
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

	GTK2.Widget Page_Spells()
	{
		return GTK2.Vbox(0,10)
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

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)"),"type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Notebook()
			->append_page(Page_Vital_Stats(),GTK2.Label("Vital Stats"))
			->append_page(Page_Gear(),GTK2.Label("Gear"))
			->append_page(Page_Inven(),GTK2.Label("Inven"))
			->append_page(Page_Description(),GTK2.Label("Description"))
			->append_page(Page_Skills(),GTK2.Label("Skills"))
			->append_page(Page_Feats(),GTK2.Label("Feats"))
			->append_page(Page_Spells(),GTK2.Label("Spells"))
			->append_page(GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Permissions")->add(GTK2.Vbox(0,0)
					->pack_start(GTK2.Label((["label":
						"Your own account always has full access. You may grant access to any other account or character here; "
						"on save, the server will translate these names into canonical account names. You will normally want to "
						"name your Dungeon Master here, unless of course you are the DM. Note that there is no provision for "
						"read-only access - you have to trust your DM anyway.","wrap":1])),0,0,0)
					->pack_start(ef("perms"),0,0,0)
				),0,0,0)
				->add(GTK2.Frame("Notes")->add(GTK2.ScrolledWindow()->add(mle("notes")->set_wrap_mode(GTK2.WRAP_WORD))))
			,GTK2.Label("Administrivia"))
			->append_page(GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Styles")->add(two_column(({
					"This is a string entry field. It takes words.",ef("help_ef"),
					"This is a numeric entry field.",num("help_num"),
					"This is a rarely-used field. You'll normally leave it blank.",rare(num("help_rare")),
					"This field is calculated as the sum of the above two.",calc("help_num+help_rare"),
					"This is something you'll want to read off.",readme("Save vs help",calc("10+help_num+help_rare")),
				}))),0,0,0)
				->add(GTK2.Label((["label":"Whenever you update something here, it can affect your roll aliases. Check 'help roll alias' in game for details.","wrap":1])))
			,GTK2.Label("Help"))
		);
		::makewindow();
		//call_out(fixsizes,0,win->mainwindow);
	}

	void sig_mainwindow_destroy()
	{
		charsheets[owner][this]=0;
		destruct();
	}

	//Level up assistant
	class sig_tnl_clicked
	{
		inherit window;
		void create() {::create();}

		//Note that the BAB arrays start with a 0 entry for having zero levels in that class.
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
			"Barbarian": (["abbr": "Brb",
				"hd": 12, "skills": 4, "bab": "Good",
				"fort": "Good", "refl": "Poor", "will": "Poor",
				"dontforget": "",
			]),"Bard": (["abbr": "Brd",
				"hd": 6,  "skills": 6, "bab": "Avg",
				"fort": "Poor", "refl": "Good", "will": "Good",
				"dontforget": "",
			]),"Cleric": (["abbr": "Clr",
				"hd": 8,  "skills": 2, "bab": "Avg",
				"fort": "Good", "refl": "Poor", "will": "Good",
				"dontforget": "",
			]),"Druid": (["abbr": "Drd",
				"hd": 8,  "skills": 4, "bab": "Avg",
				"fort": "Good", "refl": "Poor", "will": "Good",
				"dontforget": "",
			]),"Fighter": (["abbr": "Ftr",
				"hd": 10, "skills": 2, "bab": "Good",
				"fort": "Good", "refl": "Poor", "will": "Poor",
				"dontforget": "Don't forget: Fighter bonus feat",
			]),"Monk": (["abbr": "Mnk",
				"hd": 8,  "skills": 4, "bab": "Avg",
				"fort": "Good", "refl": "Good", "will": "Good",
				"dontforget": "",
			]),"Paladin": (["abbr": "Pal",
				"hd": 10, "skills": 2, "bab": "Good",
				"fort": "Good", "refl": "Poor", "will": "Poor",
				"dontforget": "",
			]),"Ranger": (["abbr": "Rgr",
				"hd": 8,  "skills": 6, "bab": "Good",
				"fort": "Good", "refl": "Good", "will": "Poor",
				"dontforget": "",
			]),"Rogue": (["abbr": "Rog",
				"hd": 6,  "skills": 8, "bab": "Avg",
				"fort": "Poor", "refl": "Good", "will": "Poor",
				"dontforget": "",
			]),"Sorcerer": (["abbr": "Sor",
				"hd": 4,  "skills": 2, "bab": "Poor",
				"fort": "Poor", "refl": "Poor", "will": "Good",
				"dontforget": "Don't forget: Learn new spells",
			]),"Wizard": (["abbr": "Wiz",
				"hd": 4,  "skills": 2, "bab": "Poor",
				"fort": "Poor", "refl": "Poor", "will": "Good",
				"dontforget": "Don't forget: Learn new spells",
			]),
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
			array sk=class_skills[classinfo->abbr] || ({ });
			int spent=0;
			foreach (skillnames;string n;) spent += (2-has_value(sk,n)) * (int)win["skill_"+n]->get_text();
			win->skillpoints->set_text(sprintf("%d/%d",spent,classinfo->skills));
		}

		//Magic object that can sprintf as anything
		object unknown=class{string _sprintf(int c) {return "??";}}();
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
			array sk=class_skills[classinfo->abbr] || ({ });
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
					if (cls=="Fighter" && !(1&(int)data["level"+i])) classes->Fighter->dontforget="";
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
					"Choose a class",win->ddcb_class=SelectBox(all_classes)->set_row_separator_func(lambda(object store,object iter) {return store->get_value(iter,0)=="";},0),
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
				//which isn't taken into account. But the skill point counting is just estimates anyway.
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

int output(mapping(string:mixed) subw,string line)
{
	if (sscanf(line,"===> Charsheet @%s <===",string acct))
	{
		subw->charsheet_eax=""; subw->charsheet_acct=acct;
		return 0;
	}
	if (sscanf(line,"===> Charsheet @%s qset %s %O",string acct,string what,string|int towhat))
	{
		if (multiset sheets=charsheets[acct]) indices(sheets)->set(what,towhat||"");
		return 1; //Suppress the spam
	}
	if (subw->charsheet_eax)
	{
		if (line=="<=== Charsheet ===>")
		{
			mixed data; catch {data=decode_value(MIME.decode_base64(m_delete(subw,"charsheet_eax")));};
			if (mappingp(data)) charsheet(subw,m_delete(subw,"charsheet_acct"),data);
			return 0;
		}
		subw->charsheet_eax+=line+"\n";
		return 1;
	}
}

void create(string name)
{
	::create(name);
	if (!G->G->charsheets) G->G->charsheets=([]);
	charsheets=G->G->charsheets;
}
