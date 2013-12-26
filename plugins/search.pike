#if !constant(COMPAT_SIGNAL)
//This plugin works properly only if Enter inside random entryfields works.
//Making it work with the enterpressed_glo bouncer is left as an exercise for
//whoever cares to do it.

inherit statustext;
inherit plugin_menu;

void find_string(string findme,mapping(string:mixed) subw)
{
	int pos=(subw->search_last==findme && subw->search_pos) || sizeof(subw->lines);
	while (--pos>0)
	{
		array line=subw->lines[pos];
		string text=line[0]->text; if (!text) line[0]->text=text=filter(line,stringp)*"";
		int col=search(text,findme);
		if (col!=-1)
		{
			//Found!
			object scr=subw->scr;
			scr->set_value(scr->get_property("upper")-scr->get_property("page size")-subw->lineheight*(sizeof(subw->lines)-1-pos));
			subw->search_last=findme;
			subw->search_pos=pos;
			G->G->window->highlight(subw,pos,col,pos,col+sizeof(findme));
			subw->maindisplay->queue_draw();
			return;
		}
	}
	m_delete(subw,"search_last");
	GTK2.MessageDialog(0,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK,"Not found.")
				->show()
				->signal_connect("response",lambda(object x) {x->destroy();});
}

int keypress(object self,array|object ev)
{
	if (arrayp(ev)) ev=ev[0];
	switch (ev->keyval)
	{
		case 0xFF0D: case 0xFF8D: find_string(self->get_text(),G->G->window->current_subw()); return 1; //Enter
		case 0xFF1B: G->G->window->current_subw()->ef->grab_focus(); return 1; //Esc - put focus back in the main EF
		default: break;
	}
}

GTK2.Widget makestatus()
{
	GTK2.Label lbl=GTK2.Label("Search: ");
	return GTK2.Table(2,1,0)
		->attach_defaults(lbl,0,1,0,1)
		->attach_defaults(statustxt->ef=GTK2.Entry()->set_has_frame(0)->set_size_request(-1,lbl->size_request()->height),1,2,0,1);
}

constant menu_label="Search";
constant menu_accel_key='f';
constant menu_accel_mods=GTK2.GDK_CONTROL_MASK;
void menu_clicked() {statustxt->ef->grab_focus();}

void create(string name)
{
	::create(name);
	statustxt->signals=({gtksignal(statustxt->ef,"key_press_event",keypress,0,UNDEFINED,1)});
}
#endif
