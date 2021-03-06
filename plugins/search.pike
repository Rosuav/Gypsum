//Status bar search box - hit Ctrl-F to put the cursor in there, enter something to search.
constant plugin_active_by_default = 1;

constant docstring=#"
Provides the status-bar search box. Press Ctrl-F to put the cursor into that
box; Enter searches (repeat to search again); Esc returns the cursor
to the main input field. Ctrl-Enter to start a search at the current scroll.
";

//TODO: Alternative search modes - regex maybe? Have an easy way to switch (eg
//keystroke while focus is on the Ctrl-F box, or Shift-Enter, which currently
//is the same as Enter).

inherit statustext;
inherit plugin_menu;

//TODO: Have a "Brief Mode" config option. Currently the config_persist_key mechanic allows only strings.

void find_string(string findme,mapping(string:mixed) subw,int from_scroll)
{
	if (findme=="") {m_delete(subw,"search_last"); return;} //Blank search to reset the search pointer. (Any other search string will reset it, too.)
	int pos=(subw->search_last==findme && subw->search_pos) || sizeof(subw->lines);
	if (from_scroll) pos=(int)subw->scr->get_value()/subw->lineheight-2;
	while (--pos>0)
	{
		array line=subw->lines[pos];
		int col=search(lower_case(line_text(line)),findme);
		if (col!=-1)
		{
			//Found!
			object scr=subw->scr;
			scr->set_value(scr->get_property("upper")-scr->get_property("page-size")-subw->lineheight*(sizeof(subw->lines)-1-pos));
			subw->search_last=findme;
			subw->search_pos=pos;
			G->G->window->highlight(subw,pos,col,pos,col+sizeof(findme));
			subw->maindisplay->queue_draw();
			return;
		}
	}
	m_delete(subw,"search_last");
	MessageBox(0,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK,"Not found.",G->G->window->mainwindow);
}

int keypress(object self,array|object ev)
{
	if (arrayp(ev)) ev=ev[0];
	switch (ev->keyval)
	{
		case 0xFF0D: case 0xFF8D: //Enter/Return
			find_string(lower_case(self->get_text()),G->G->window->current_subw(),ev->state&GTK2.GDK_CONTROL_MASK);
			return 1;
		case 0xFF1B: G->G->window->current_subw()->ef->grab_focus(); return 1; //Esc - put focus back in the main EF
		default: break;
	}
}

GTK2.Widget makestatus()
{
	statustxt->lbl=GTK2.Label("Search: ");
	statustxt->ef=GTK2.Entry((["width-chars":10]))->set_has_frame(0)->set_size_request(-1,statustxt->lbl->size_request()->height);
	return two_column(({statustxt->lbl,statustxt->ef}));
}

constant menu_label="Search";
constant menu_accel_key='f';
constant menu_accel_mods=GTK2.GDK_CONTROL_MASK;
void menu_clicked() {statustxt->ef->grab_focus();}

protected void create(string name)
{
	statustxt->tooltip="Ctrl-F to search";
	::create(name);
	statustxt->signals=({gtksignal(statustxt->ef,"key_press_event",keypress,0,UNDEFINED,1)});
	//Brief mode: cut out the "Search: " label, saving some horizontal space.
	statustxt->lbl->set_text("Search: "*(!persist["search/brief"]));
}
