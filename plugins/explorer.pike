//Pop up a window to explore global state. Start with G or G->G, and drill down as far as you want.
inherit plugin_menu;

constant menu_label = "Explore Gypsum's internals";
class menu_clicked
{
	inherit window;
	constant is_subwindow=0;
	void create() {::create();}

	multiset(int) no_recursion = (<>);
	void add_to_store(mixed thing, string name, GTK2.TreeIter parent)
	{
		GTK2.TreeIter row = win->store->append(parent);
		if (name) name += ": "; else name = "";
		//Figure out how to represent the 'thing'.
		//Firstly, if we've already seen it, put a marker - don't
		//infinitely recurse.
		int hash = hash_value(thing); //Snapshot the hash - we may reassign 'thing' for convenience
		if (no_recursion[hash])
		{
			win->store->set_value(row, 0, name + "[recursive]");
			return;
		}
		no_recursion[hash] = 1;
		//Next up: Recognized types of nested structures.
		if (arrayp(thing) || multisetp(thing))
		{
			win->store->set_value(row, 0, sprintf("%s%t", name, thing));
			thing = (array)thing;
			foreach (thing[..99], mixed subthing)
				add_to_store(subthing, 0, row);
			if (sizeof(thing) > 100)
				win->store->set_value(win->store->append(row), 0,
					sprintf("... %d more entries...", sizeof(thing)-100));
		}
		else if (mappingp(thing))
		{
			//TODO: Maybe support objectp too - might not be helpful (drilling
			//into indices() of a Stdio.File is not particularly interesting).
			win->store->set_value(row, 0, name + "mapping");
			int count = 0;
			foreach (sort(indices(thing)), mixed key)
			{
				if (!stringp(key)) key = sprintf("%O", key);
				add_to_store(thing[key], key, row);
				if (++count >= 100) break;
			}
			if (sizeof(thing) > count)
				win->store->set_value(win->store->append(row), 0,
					sprintf("... %d more entries...", sizeof(thing)-count));
		}
		//Finally, non-nesting objects.
		else
		{
			if (!stringp(thing)) thing = sprintf("%O", thing);
			if (sizeof(thing) >= 256)
			{
				//Abbreviate it some
				win->store->set_value(row, 0, name + thing[..250] + "...");
				GTK2.TreeIter full = win->store->append(row);
				win->store->set_value(full, 0, thing);
			}
			else win->store->set_value(row, 0, name + thing);
		}
		no_recursion[hash] = 0;
	}

	void makewindow()
	{
		if (!persist["explorer_active"])
		{
			win->mainwindow=GTK2.Window((["title":"Explore Gypsum internals"]))->add(GTK2.Vbox(0,0)
				->add(GTK2.Label(#"CAUTION: This will reveal a lot of deep internals
which are of interest only to developers, and may be confusing even to
ubernerds. Changing anything here may break Gypsum in ways which may not
even be obvious at first. Click the button below when you have understood
the consequences of this."))
				->add(GTK2.HbuttonBox()
					->add(win->do_as_i_say=GTK2.Button("Yes, do as I say"))
					->add(stock_close())
				)
			);
			return;
		}
		win->store = GTK2.TreeStore(({"string"}));
		add_to_store(G->G, "G", UNDEFINED);
		add_to_store(G->globals, "constants", UNDEFINED);
		add_to_store(persist->data, "persist", UNDEFINED);
		win->mainwindow=GTK2.Window((["title":"Explore Gypsum internals"]))->add(GTK2.Vbox(0,0)
			->add(GTK2.ScrolledWindow()
				->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_AUTOMATIC)
				->add(win->treeview=GTK2.TreeView(win->store)->set_size_request(400,250)
					->append_column(GTK2.TreeViewColumn("",GTK2.CellRendererText(),"text",0))
				)
			)
			->add(GTK2.HbuttonBox()->add(stock_close()))
		);
	}

	void sig_do_as_i_say_clicked()
	{
		persist["explorer_active"] = 1;
		closewindow();
		menu_clicked();
	}
}
