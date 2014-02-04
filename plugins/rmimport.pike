/* Attempt to import settings from RosMud's .ini files

Note that this will work across platforms. Mount your RM directory from a
remote system, or archive it and copy it across, or whatever you like.

Note also that the set of importables may expand. This is why it's kept
carefully configurable; it'll never import more stuff than you tell it to.

In an inversion of the usual rules, this plugin is allowed to "reach in"
to any other plugin's memory space. Otherwise, all other plugins would be
forced to go to extra effort somewhere (the simplest would be to demand
that they place an empty mapping back into persist[], but there may be
other considerations too), which is backwards. It's the importer that has
the complexity, not everything else. Of course, this may mean that changes
to other plugins might precipitate changes here, which is a cost, but even
if that's missed somewhere, it means only that the importer is broken.
*/
inherit plugin_menu;

constant menu_label="Import settings";
class menu_clicked
{
	inherit window;

	void create() {::create("rmimport");}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Import settings from RosMud","transient-for":G->G->window->mainwindow]))->add(GTK2.Vbox(0,0)
			->add(win->notebook=GTK2.Notebook()->append_page(GTK2.Vbox(0,0)
				->add(GTK2.Label("First step: Choose a directory to import settings from."))
				->add(GTK2.Frame("Import directory")->add(GTK2.Hbox(0,0)
					->pack_start(win->pb_find=GTK2.Button("Open"),0,0,0)
					->add(win->import_dir=GTK2.Label(""))
				))
				->add(win->status=GTK2.Label(""))
				->add(GTK2.Frame("Global control")->add(GTK2.HbuttonBox()
					->add(win->pb_selectall=GTK2.Button("Select all"))
					->add(win->pb_selectnone=GTK2.Button("Select none"))
				))
			,GTK2.Label("Start")))
			->pack_start(GTK2.HbuttonBox()
				->add(win->pb_import=GTK2.Button("Import!")->set_sensitive(0))
				->add(win->pb_close=GTK2.Button("Close"))
			,0,0,0)
		);
		::makewindow();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_find,"clicked",pb_find_click),
			gtksignal(win->pb_selectall,"clicked",pb_select_click,1), //Same handler for these, just an arg
			gtksignal(win->pb_selectnone,"clicked",pb_select_click,0),
			gtksignal(win->pb_close,"clicked",pb_close_click),
		});
	}

	void pb_close_click() {win->mainwindow->destroy();}

	void pb_find_click()
	{
		win->import_dir->set_text("Stub, sorry!");
	}

	void pb_select_click(mixed ... args)
	{
		say(0,"%O",args);
	}
}
