/* Pop-out character sheet renderer for Minstrel Hall

Carefully matched to the corresponding code on the server, this will pop out a
character sheet based on data stored on the server.

Formulas can be entered. They reference the underlying data mapping, NOT the
coordinates of the cell on some spreadsheet layout, so it's as simple as
referencing the names used. Full Pike syntax is available, but please be
aware: The code broadly assumes that the person devising the formula knows
what s/he is doing. It is entirely possible to break things by mucking that
up. So take a bit of care, and don't deploy without knowing that it's right. :)

TODO: Update notifications. Register a subscription with the server, get told
about changes. Suppress their noise, plsthx!
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
		G->G->connection->write(conn,string_to_utf8(sprintf("charsheet @%s set %s %s\r\n",owner,kwd,data[kwd]=val)));
		if (depends[kwd]) indices(depends[kwd])(data,beenthere);
	}

	void checkchanged(object self,object event,string kwd)
	{
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
		foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj)
		{
			if (stringp(obj)) obj=GTK2.Label(obj);
			tb->attach_defaults(obj,x,x+1,y,y+1);
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

	//Magic resolver. Any symbol at all can be resolved; it'll come through as 0, but the name
	//will be retained. Used in the precompilation stage to capture external references.
	multiset(string) symbols;
	mixed resolv(string symbol,string fn,object handler) {symbols[symbol]=1;}

	//Perform magic and return something that has a calculated value.
	//The formula is Pike syntax. Any unexpected variable references in it become lookups
	//into data[] and will be cast to int. (TODO: Have a way to choose either int or float.)
	GTK2.Widget calc(string formula,string|void name)
	{
		object lbl=GTK2.Label();
		catch
		{
			//Phase zero: Precompile, to get a list of used symbols
			symbols=(<>);
			program p=compile("mixed _="+formula+";",this); //Note, p must be retained or the compile() call will be optimized out!

			//Phase one: Compile the formula calculator itself.
			function f1=compile(sprintf(
				"int _(mapping data) {%{int %s=(int)data->%<s;%}return %s;}",
				(array)symbols,formula
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
	
	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)"),"type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Notebook()
			->append_page(GTK2.Vbox(0,20)
				->add(GTK2Table(({
					({"Name",ef("name",12),"Race",ef("race",8),"Character level",num("level",8)}),
					({"Class",ef("class1",12),"Level",ef("level1"),"Experience",num("xp",8)}),
					({"Class",ef("class2",12),"Level",ef("level2"),"To next level",calc("`+(@enumerate(level,1000,1000))-xp")}),
					({"Class",ef("class3",12),"Level",ef("level3"),"Alignment",ef("alignment",12)}),
				})))
				->add(GTK2.Hbox(0,20)
					->add(GTK2Table(
						({({"Stat","Score","Eq","Temp","Mod"})})+
						//For each stat (eg "str"): ({"STR",ef("str"),ef("str_eq"),ef("str_tmp"),calc("(str+str_eq+str_tmp-10)/2")})
						map(({"STR","DEX","CON","INT","WIS","CHA"}),lambda(string stat) {return ({
							stat,num(stat),num(stat+"_eq"),num(stat+"_tmp"),
							calc(sprintf("(%s+%<s_eq+%<s_tmp-10)/2",stat),stat+"_mod")
						});})
					))
					->add(GTK2Table(({
						({"","Normal","Current"}),
						({"HP",num("hp"),num("cur_hp")}),
						({"AC",num("ac")}),
						({"",""}),
						({"Touch",""}),
						({"Flat",""}),
						({"Init",""}),
					})))
				)
				->add(GTK2Table(({
					({"Saves","Base","Ability","Misc","Total"}),
					({"Fort",num("fort_base"),calc("CON_mod"),num("fort_misc"),calc("fort_base+CON_mod+fort_misc","fort_save")}),
					({"Refl",num("refl_base"),calc("DEX_mod"),num("refl_misc"),calc("refl_base+DEX_mod+refl_misc","refl_save")}),
					({"Will",num("will_base"),calc("WIS_mod"),num("will_misc"),calc("will_base+WIS_mod+will_misc","will_save")}),
				})))
			,GTK2.Label("Vital Stats"))
			->append_page(GTK2.Vbox(0,20)
				->add(GTK2Table(({
					({"Age",ef("age"),"Skin",ef("skin")}),
					({"Gender",ef("gender"),"Eyes",ef("eyes")}),
					({"Height",ef("height"),"Hair",ef("hair")}),
					({"Weight",ef("weight"),"Size",ef("size")}),
				})))
			,GTK2.Label("Description"))
			->append_page(GTK2.Vbox(0,20)
				->add(GTK2.Label((["label":"Your own account always has full access. You may grant access to any other account or character here; on save, the server will translate these names into canonical account names.","wrap":1])))
				->add(ef("perms"))
			,GTK2.Label("Access"))
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
	if (sscanf(line,"===> Charsheet @%s set %s %s",string acct,string what,string towhat))
	{
		if (multiset sheets=charsheets[acct]) indices(sheets)->set(what,towhat);
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
