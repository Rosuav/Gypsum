//Cluedo Detective Notes
//Currently not at all integrated with the MUD session, but might later on grow
//an output hook - for instance, when someone shows you a card, it could catch
//and record that.
inherit plugin_menu;

constant instructions=#"TODO: Put these somewhere user-facing.

When the game begins, you're dealt some cards. Start by putting your own name
as 'Owner' for each of those cards. If you want to keep track of who you've
shown each card to, you have the other columns available, otherwise they'll
stay blank for your own cards.

Any time you get shown a card, you obviously know the owner of that card, so
you can record that person's name. Again, you probably won't need the other
columns for these cards; you know all you need to.

When someone proclaims an inability to show a card, any unknown-location cards
used in the current challenge can be recorded as 'Not so-and-so'. It's helpful
to use initials here; personally, I use ~X to mean 'Not X'. Once you find an
owner, obviously any negative information is superseded (as the card's in only
one place), so the Owner field can be used for these.

The complicated stuff happens when a card is shown, but neither to nor by you.
There are a few possibilities. If you know that one of the three cards (person,
weapon, and room) is held by the showing player, then there's nothing to be
learned from this challenge. Conversely, if you know that two of the three are
owned by other players, then clearly the remaining card is the one that was
shown, and you can record that just as surely as if you'd been shown it.

But if there are multiple possible cards that could have been shown, you can
still glean some information from this. This is where those other columns come
in handy. Allocate a column to this challenge, and put the showing player's
initial into the fields for the two or three possible cards. You can't use this
information yet, but later on, you'll learn more about those same cards. If you
learn that the original showing player holds one of those cards, then you can
clear out this column; there's nothing more to learn. But if you learn that
some other player holds a card, you can remove it from the set. And once the
set is reduced to just one card, you know for sure that that player has that
card!

Note that the murder set is an owner, just like any other. If, for instance,
you have figured out where five of the weapons are, you can deduce that the
sixth must be the murder weapon - and therefore can't have been shown in any
previous showing, which may tell you that it must have been the room that was
shown. Beyond that, though, everything's a head-to-head among the players -
good luck, and have fun!
";

//TODO: Highlight the row/column the cursor's in

constant menu_label="Cluedo _Detective Notes";
class menu_clicked
{
	inherit movablewindow;
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
