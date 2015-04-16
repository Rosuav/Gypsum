constant docstring=#"
Interface to an external spelling checker.

While this does not currently give real-time spell-checking of your input, it
does allow you to request the checking of your current command. In many cases,
this will be all you need; for additional flexibility, consider opening up a
new subwindow just for spell-checking.

On Linux, install the GNU Aspell package from your repositories. On Windows,
install http://aspell.net/win32/ and ensure that it is in your PATH.
";
inherit plugin_menu;

constant menu_label="Spell-check word";
constant menu_accel_key=0xFFC6; //F9
void menu_clicked() {spellcheck(0);}

//Hack: A second plugin menu item.
object hack=class {
	inherit plugin_menu;
	constant menu_label="Spell-check input";
	constant menu_accel_key=0xFFC6; //Shift-F9
	constant menu_accel_mods=GTK2.GDK_SHIFT_MASK;
	void menu_clicked() {spellcheck(1);}
}("spellcheck_all");

//Determine if the given character is part of a word.
//This is a tricky thing, because it's based on user expectations, not
//strict logic. Most of it is handled by Unicode.is_wordchar(), but
//that cuts out apostrophe, so "doesn't" would count as two separate
//words. For the moment, I'm just hard-coding the ASCII apostophe as a
//special case; it may be necessary to use some other detection method.
int wordchar(int ch)
{
	return ch=='\'' || Unicode.is_wordchar(ch);
}

void spellcheck(int all)
{
	mapping subw=G->G->window->current_subw(); if (!subw) return;
	string txt=subw->ef->get_text();
	if (!all)
	{
		int pos=subw->ef->get_position();
		if (pos==sizeof(txt) || (pos && !wordchar(txt[pos]))) --pos;
		//Seek to the edges of word characters
		int start=pos,end=pos;
		while (start>=0 && wordchar(txt[start])) --start;
		while (end<sizeof(txt) && wordchar(txt[end])) ++end;
		txt=txt[start+1..end-1];
	}
	//Assume that the process won't take too long. If it does, assume it's going
	//haywire (or waiting for user input), and kill it.
	mapping rc=Process.run(({"aspell","--encoding=utf-8","pipe"}),([
		"stdin":string_to_utf8(txt),
		"timeout":1,"timeout_callback":lambda(object p) {p->kill();}, //After one second, kill the process. It should be virtually instant anyway.
	]));
	//Skip the first line and any that are just asterisks, output any others.
	foreach ((rc->stdout/"\n")[1..],string line)
	{
		line=String.trim_all_whites(line);
		if (line!="" && line!="*") say(subw,"%% "+line);
	}
	say(subw,"%% Spell check complete.");
}
