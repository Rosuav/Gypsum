//Cluedo Detective Notes
inherit plugin_menu;
inherit hook;

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

Note that you can use the up and down arrow keys to move vertically within the
table structure, but you'll need tab and shift-tab to move horizontally (as the
left and right arrows will move the cursor within the current field).
";

multiset(GTK2.Widget) lastchals=(<>);

int outputhook(string line,mapping(string:mixed) conn)
{
	if (!sizeof(lastchals)) return 0; //No notes up, don't bother checking anything
	if (sscanf(line,"%[^ ] challenges: %s with the %s in the %s",string player,string person,string weapon,string room)==4)
	{
		//TODO: Verify that person, weapon, and room are valid, otherwise it's a false positive
		indices(lastchals)->set_text(line); //Overwrite them all - easy.
		return 0;
	}
	if (sscanf(line,"%s shows a Cluedo card to %s.",string shower,string showee)==2
		|| sscanf(line,"%s shows you a Cluedo card.",shower)==1
		|| sscanf(line,"This Cluedo card represents %s.",string card)==1
		|| sscanf(line,"You show a Cluedo card to %s.",showee)==1
		|| sscanf(line,"%s declares that %s has no card to show.",shower,string pron)==2
		|| line=="You declare that you have no card to show.")
	{
		//TODO (maybe): highlight the sscanf'd strings (with the exception of 'pron', which doesn't matter)
		foreach (lastchals;GTK2.Widget lbl;)
			lbl->set_text(lbl->get_text()+"\n"+line);
	}
}

constant menu_label="Cluedo _Detective Notes";
class menu_clicked
{
	inherit movablewindow;
	constant is_subwindow=0;
	void create() {::create();}
	void destroy() {lastchals[win->lastchal]=0;}

	int currow=0,curcol=0;
	array(array(GTK2.Widget)) rows=({({ })}),cols=({({ })});
	void focus(object self,object ev,array pos)
	{
		[int row,int col]=pos;
		array(GTK2.Widget) unhighlight=rows[currow]+cols[curcol];
		array(GTK2.Widget) highlight=rows[currow=row]+cols[curcol=col];
		unhighlight-=highlight; //Prevent flicker
		unhighlight->modify_base(GTK2.STATE_NORMAL);
		highlight->modify_base(GTK2.STATE_NORMAL,GTK2.GdkColor(255,255,192));
	}
	GTK2.Entry entry(mapping props)
	{
		GTK2.Entry ef=GTK2.Entry(props);
		++curcol;
		if (curcol>=sizeof(cols)) cols+=({({ })});
		cols[curcol]+=({ef});
		ef->signal_connect("focus_in_event",focus,({currow,curcol}));
		return ef;
	}
	GTK2.Widget owner() {return entry((["width-chars":15]));}
	GTK2.Widget gridslot() {return entry((["width-chars":2]));}
	array(string|GTK2.Widget) row(string|GTK2.Widget heading)
	{
		++currow; curcol=0;
		rows+=({({owner()})+(({gridslot})*14)()});
		return ({heading})+rows[-1];
	}
	GTK2.Widget bighead(string label) {return GTK2.Label(label)->modify_font(GTK2.PangoFontDescription("Bold 12"));}
	GTK2.Widget subhead(string label) {return GTK2.Label(label)->modify_font(GTK2.PangoFontDescription("Bold"));}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Cluedo Detective Notes","type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Vbox(0,0)
			->add(GTK2Table(({
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
			}),(["xalign":1.0])))
			->add(bighead("Last challenge:")->set_alignment(0.0,0.5))
			->add(win->lastchal=GTK2.Label("(none)")->set_alignment(0.0,0.0))
		);
		lastchals[win->lastchal]=1;
		currow=curcol=0;
		::makewindow();
	}

	int closewindow()
	{
		confirm(0,"This doesn't save anywhere - when you close, it will all be lost. Really close?",win->mainwindow,::closewindow);
		return 1;
	}
}

void create(string name) {::create(name);}
