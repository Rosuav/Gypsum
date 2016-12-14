inherit plugin_menu;

constant docstring=#"
Find words with lotsa vowels - maybe character names.
";

constant menu_label="Vowel finder";
void menu_clicked()
{
	mapping subw = G->G->window->current_subw();
	multiset(string) all_vowels = (<>);
	object re = Regexp.PCRE.StudiedWidestring("^[A-Z][a-z]+$");
	foreach (subw->lines, array l)
	{
		foreach (line_text(l)/" ", string w)
		{
			if (!re->match(w)) continue;
			string l = lower_case(w);
			if (!has_value(l, 'a') || !has_value(l, 'e') || !has_value(l, 'i') || !has_value(l, 'o') || !has_value(l, 'u')) continue;
			all_vowels[w] = 1;
		}
	}
	say(subw, "%% Done checking");
	MessageBox(0,0,GTK2.BUTTONS_OK,"All vowels: " + indices(all_vowels)*", ",G->G->window->mainwindow);
}
