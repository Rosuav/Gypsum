inherit hook;
//inherit command;
inherit window;

int outputhook(string line,mapping(string:mixed) conn)
{
	//Resync
}

void makewindow()
{
	win->mainwindow=GTK2.Window(([]))->set_transient_for(G->G->window->mainwindow)->set_type_hint(GTK2.GDK_WINDOW_TYPE_HINT_SPLASHSCREEN);
	win->mainwindow->set_title("Threshold time");
	win->mainwindow->add(
		win->display=GTK2.Label("Twilight 26th, 379 at 13:30")
	)->show_all();
	int x,y; catch {[x,y]=persist["threshtime/winpos"];}; //If errors, let 'em sit at the defaults (0,0 since I haven't set any other default)
	win->x=1; call_out(lambda() {m_delete(win,"x");},1);
	win->mainwindow->move(x,y);
}

void configevent(object self,object ev)
{
	if (ev->type!="configure") return;
	if (!has_index(win,"x")) call_out(savepos,2);
	win+=self->get_position();
}

void savepos()
{
	werror("%d,%d\n",win->x,win->y);
	persist["threshtime/winpos"]=({m_delete(win,"x"),m_delete(win,"y")});
}

void mousedown(object self,object ev)
{
	self->begin_move_drag(ev->button,ev->x_root,ev->y_root,ev->time);
}

void dosignals()
{
	win->signals=({
		gtksignal(win->mainwindow,"event",configevent),
		gtksignal(win->mainwindow,"button_press_event",mousedown),
	});
	win->mainwindow->add_events(GTK2.GDK_BUTTON_PRESS_MASK);
}

void create(string name)
{
	::create(name);
}
