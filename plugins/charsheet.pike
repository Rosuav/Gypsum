inherit hook;

class charsheet(mapping(string:mixed) conn,mapping(string:mixed) data)
{
	inherit movablewindow;
	constant pos_key="charsheet/winpos";
	mapping(string:multiset(function)) depends=([]); //Whenever something changes, recalculate all its depends.

	void create()
	{
		::create(); //No name. Each one should be independent.
		win->mainwindow->set_skip_taskbar_hint(0)->set_skip_pager_hint(0); //Undo the hinting done by default
	}

	void set_value(string kwd,string val,multiset|void beenthere)
	{
		if (val=="0") val="";
		if (val==data[kwd] || (!data[kwd] && val=="")) return; //Nothing changed, nothing to do.
		if (!beenthere) beenthere=(<>);
		if (beenthere[kwd]) return; //Recursion trap: don't recalculate anything twice.
		beenthere[kwd]=1;
		G->G->connection->write(conn,string_to_utf8(sprintf("charsheet set %s %s\r\n",kwd,data[kwd]=val)));
		if (depends[kwd]) indices(depends[kwd])(data,beenthere);
	}
	void checkchanged(object self,object event,string kwd) {set_value(kwd,self->get_text());}

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
		win->mainwindow=GTK2.Window((["title":"Character Sheet: "+(data->name||"(unnamed)"),"type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Vbox(0,20)
			->add(GTK2.Hbox(0,20)
				->add(GTK2Table(({
					({"Name",ef("name",12),"Race",ef("race",8)}),
					({"Class",ef("class1",12),"Level",ef("level1")}),
					({"Class",ef("class2",12),"Level",ef("level2")}),
					({"Class",ef("class3",12),"Level",ef("level3")}),
				})))
				->add(GTK2Table(({
					({"Age",ef("age"),"Skin",ef("skin")}),
					({"Gender",ef("gender"),"Eyes",ef("eyes")}),
					({"Height",ef("height"),"Hair",ef("hair")}),
					({"Weight",ef("weight"),"Size",ef("size")}),
				})))
			)
			->add(GTK2.Hbox(0,20)
				->add(GTK2Table(
					({({"Stat","Score","Eq","Temp","Mod"})})+
					//For each stat (eg "str"): ({"STR",ef("str"),ef("str_eq"),ef("str_tmp"),calc("(str+str_eq+str_tmp-10)/2")})
					map(({"STR","DEX","CON","INT","WIS","CHA"}),lambda(string stat) {return ({
						stat,ef(stat),ef(stat+"_eq"),ef(stat+"_tmp"),
						calc(sprintf("(%s+%<s_eq+%<s_tmp-10)/2",stat),stat+"_mod")
					});})
				))
				->add(GTK2Table(({
					({"","Normal","Current"}),
					({"HP",ef("hp"),ef("cur_hp")}),
					({"AC",ef("ac")}),
					({"",""}),
					({"Touch",""}),
					({"Flat",""}),
					({"Init",""}),
				})))
			)
		);
		::makewindow();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
		});
	}
}

int outputhook(string line,mapping(string:mixed) conn)
{
	if (line=="===> Charsheet <===")
	{
		conn->charsheet_eax="";
		return 0;
	}
	if (conn->charsheet_eax)
	{
		if (line=="<=== Charsheet ===>")
		{
			mixed data; catch {data=decode_value(MIME.decode_base64(m_delete(conn,"charsheet_eax")));};
			if (mappingp(data)) charsheet(conn,data);
			return 0;
		}
		conn->charsheet_eax+=line+"\n";
		return 0;
	}
}
