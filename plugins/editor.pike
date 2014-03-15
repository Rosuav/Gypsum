inherit hook;

class editor(mapping(string:mixed) subw)
{
	inherit movablewindow;
	constant pos_key="editor/winpos";
	constant load_size=1;

	void create(string initial)
	{
		win->initial=initial;
		::create(); //No name. Each one should be independent. Note that this breaks compat-mode window position saving.
		win->mainwindow->set_skip_taskbar_hint(0)->set_skip_pager_hint(0); //Undo the hinting done by default
	}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Pop-Out Editor","type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Vbox(0,0)
			->add(GTK2.ScrolledWindow()
				->add(win->mle=GTK2.TextView(win->buf=GTK2.TextBuffer()->set_text(win->initial)))
			)
			->pack_end(GTK2.HbuttonBox()
				->add(win->pb_send=GTK2.Button((["label":"_Send","use-underline":1,"focus-on-click":0])))
				->add(GTK2.Frame("Cursor")->add(win->curpos=GTK2.Label("")))
				->add(stock_close()->set_focus_on_click(0))
			,0,0,0)
		);
		win->mle->modify_font(G->G->window->getfont("input"));
		win->buf->set_modified(0);
		::makewindow();
	}

	void pb_send_click()
	{
		//Note that we really need the conn, but are retaining the subw in case
		//the connection breaks and is reconnected. Alternatively, we could use
		//current_subw(), or maybe a check (subw if valid else current_subw) to
		//catch other cases.
		send(subw,replace(String.trim_all_whites(
			win->buf->get_text(win->buf->get_start_iter(),win->buf->get_end_iter(),0)
		),"\n","\r\n")+"\r\n");
		win->buf->set_modified(0);
	}

	int closewindow()
	{
		if (win->buf->get_modified())
		{
			confirm(0,"File has been modified, close without sending/saving?",win->mainwindow,::closewindow);
			return 1;
		}
		return ::closewindow();
	}

	void cursorpos(object self,mixed iter1,object mark,mixed foo)
	{
		if (mark->get_name()!="insert") return;
		GTK2.TextIter iter=win->buf->get_iter_at_mark(mark);
		win->curpos->set_text(iter->get_line()+","+iter->get_line_offset());
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_send,"clicked",pb_send_click),
			//NOTE: This currently crashes Pike, due to over-freeing of the top stack object
			//(whatever it is). Am disabling this code until a patch is deployed.
			//The solution is deep inside the Pike GTK support code and can't be worked
			//around, so this will depend on some way of recognizing a fixed Pike - probably
			//a COMPAT option that will default to unconditionally active until there's an
			//official Pike build that incorporates it. It's a minor convenience anyway.
			//gtksignal(win->buf,"mark_set",cursorpos),
		});
	}
}

int outputhook(string line,mapping(string:mixed) conn)
{
	if (line=="===> Editor <===")
	{
		conn->editor_eax="";
		return 0;
	}
	if (conn->editor_eax)
	{
		if (line=="<=== Editor ===>") {editor(conn->display,m_delete(conn,"editor_eax")); return 0;}
		conn->editor_eax+=line+"\n";
		return 0;
	}
}
