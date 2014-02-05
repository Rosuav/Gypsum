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
			win->filedlg && gtksignal(win->filedlg,"response",filedlg_response),
		});
	}

	void pb_close_click() {win->mainwindow->destroy();}

	void pb_find_click()
	{
		win->filedlg=GTK2.FileChooserDialog("Locate RosMud directory to import from",win->mainwindow,
			GTK2.FILE_CHOOSER_ACTION_SELECT_FOLDER,({(["text":"Import","id":GTK2.RESPONSE_OK]),(["text":"Cancel","id":GTK2.RESPONSE_CANCEL])})
		)->show_all();
		win->filedlg->set_filename("."); //This doesn't chain. What's the integer it returns? Meh.
		dosignals();
	}

	void pb_select_click(object self,int state)
	{
		say(0,"Set checkboxes to "+state); // state == GTK2.STUN?
	}

	void filedlg_response(object self,int response)
	{
		if (response==GTK2.RESPONSE_OK)
		{
			win->import_dir->set_text(win->dir=self->get_filename());
			for (int i=win->notebook->get_n_pages()-1;i>1;--i) win->notebook->remove_page(i);
			foreach (indices(this),string func) if (has_prefix(func,"import_")) this[func]();
		}
		m_delete(win,"filedlg")->destroy();
		dosignals();
	}
}
