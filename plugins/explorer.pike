/* Stub for notes.

Pop up a window to explore global state. Start with G or G->G, and drill down as far as you want.

GTK2.TreeView, add subentries for key in indices(cur). If it's a mapping/array, let it be plussed out.
Preferably, don't actually load up the next level until it's needed.

Simple types other than mappings and arrays can be rendered simply. (Maybe %O, maybe not.)
Objects get %O by default, but maybe there should be a UI way to show "as if cast to mapping".
(Note that this shouldn't *actually* cast the object to mapping, as that's not available in
all supported Pikes. It should just use indices() and subscripting, as if it were a mapping.)

Will probably use test-expand-row signal.
*/

inherit plugin_menu;

constant menu_label = "Explore Gypsum's internals";
class menu_clicked
{
	inherit movablewindow;
	constant is_subwindow=0;
	void create() {::create();}
	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Cluedo Detective Notes"]))->add(GTK2.Vbox(0,0)
			->add(GTK2.Label(#"CAUTION: This will reveal a lot of deep internals
which are of interest only to developers, and may be confusing even to
ubernerds. Changing anything here may break Gypsum in ways which may not
even be obvious at first. Click the button below when you have understood
the consequences of this."))
			->add(GTK2.HbuttonBox()->add(stock_close()))
		);
	}
	//Yes, that's right. While it's a stub, you have to click Close when you understand. :)
}
