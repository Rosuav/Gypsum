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
mapping(string:string) aliases=([
	"init":"d20+{init}",
	"STR":"d20+{STR_mod}", //etc
	"grapple":"d20+{grapple}",
	"Fort save":"d20+{fort_save}", //etc
	//plus skills and attacks
]);

class charsheet(mapping(string:mixed) subw,string owner,mapping(string:mixed) data)
{
	inherit movablewindow;
	constant is_subwindow=0;
	constant pos_key="charsheet/winpos";
	mapping(string:array(function)) depends=([]); //Whenever something changes, recalculate all its depends.

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
		if (!send(subw,sprintf("charsheet @%s qset %s %q\r\n",owner,kwd,data[kwd]=val)))
		{
			win->mainwindow->set_title("UNSAVED CHARACTER SHEET");
			return; //Can't do much :( But at least warn the user.
		}
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
	GTK2.Widget calc(string formula,string|void name,string|void type)
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

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)"),"type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Notebook()
			->append_page(GTK2.Vbox(0,20)
				->pack_start(GTK2.Hbox(0,10)
					->add(GTK2Table(({
						({"Name",ef("name",12),0,0,"Char level",num("level",8)}),
						({"Race",ef("race",8),"HD",rare(ef("race_hd")),"Experience",num("xp",8)}),
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
				)
			,GTK2.Label("Vital Stats"))
			->append_page(GTK2.Hbox(0,20)
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
				,0,0,0)
			,GTK2.Label("Gear"))
			->append_page(GTK2.ScrolledWindow()->add(GTK2Table(({
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
			))
			,GTK2.Label("Inven"))
			->append_page(GTK2.Vbox(0,20)
				->pack_start(GTK2Table(({
					({"Age",ef("age"),"Skin",ef("skin")}),
					({"Gender",ef("gender"),"Eyes",ef("eyes")}),
					({"Height",ef("height"),"Hair",ef("hair")}),
					({"Weight",ef("weight"),"Carried",calc("inven_tot_weight",0,"float")}),
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
					WIS Heal
					DEX Hide	AC
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
				}())))
			,GTK2.Label("Spells"))
			->append_page(GTK2.Vbox(0,10)
				->pack_start(GTK2.Frame("Permissions")->add(GTK2.Vbox(0,0)
					->pack_start(GTK2.Label((["label":
						"Your own account always has full access. You may grant access to any other account or character here; "
						"on save, the server will translate these names into canonical account names. You will normally want to "
						"name your Dungeon Master here, unless of course you are the DM. Note that there is no provision for "
						"read-only access - you have to trust your DM anyway.","wrap":1])),0,0,0)
					->pack_start(ef("perms"),0,0,0)
				),0,0,0)
				->add(GTK2.Frame("Notes")->add(mle("notes")))
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
