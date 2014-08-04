//Cluedo Detective Notes
//Currently not at all integrated with the MUD session, but might later on grow
//an output hook - for instance, when someone shows you a card, it could catch
//and record that.
inherit plugin_menu;

constant menu_label="Cluedo _Detective Notes";
class menu_clicked
{
	inherit window;
	void create() {::create();}

	GTK2.Widget owner() {return GTK2.Entry((["width-chars":15]));}
	GTK2.Widget gridslot() {return GTK2.Entry((["width-chars":2]));}
	array(string|GTK2.Widget) row(string|GTK2.Widget heading) {return ({heading,owner()})+(({gridslot})*14)();}
	GTK2.Widget bighead(string label) {return GTK2.Label(label)->modify_font(GTK2.PangoFontDescription("Bold 12"));}
	GTK2.Widget subhead(string label) {return GTK2.Label(label)->modify_font(GTK2.PangoFontDescription("Bold"));}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Cluedo Detective Notes","type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2Table(({
			({bighead("Element"),bighead("Owner"),bighead("Notes")->set_alignment(0.0,0.5),0,0,0}),
			({subhead("Persons"),"",""}),
			row("Miss Scarlett"),
			row("Col Mustard"),
			row("Mrs White"),
			row("Mrs Peacock"),
			row("Prof Plum"),
			row("Rev Green"),
			({""}),
			({subhead("Weapons")}),
			row("Lead pipe [pipe]"),
			row("Revolver"),
			row("Spanner"),
			row("Rope"),
			row("Candlestick"),
			row("Dagger"),
			({""}),
			({subhead("Rooms")}),
			row("Hall"),
			row("Conservatory"),
			row("Ballroom"),
			row("Billiard room [billiard]"),
			row("Dining room [dining]"),
			row("Kitchen"),
			row("Study"),
			row("Library"),
			row("Lounge"),
		}),(["xalign":1.0])));
		::makewindow();
	}

	int closewindow()
	{
		confirm(0,"This doesn't save anywhere - when you close, it will all be lost. Really close?",win->mainwindow,::closewindow);
		return 1;
	}
}
