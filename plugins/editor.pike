inherit hook;

class editor(mapping(string:mixed) conn)
{
	inherit movablewindow;
	constant pos_key="editor/winpos";
	constant load_size=1;

	void create(string initial)
	{
		win->initial=initial;
		::create(); //No name. Each one should be independent.
	}

	void makewindow()
	{
		object ls=GTK2.ListStore(({"string"}));
		win->mainwindow=GTK2.Window((["title":"Pop-Out Editor","transient-for":G->G->window->mainwindow]))->add(GTK2.Vbox(0,0)
			->add(GTK2.ScrolledWindow()
				->add(win->mle=GTK2.TextView(win->buf=GTK2.TextBuffer()->set_text(win->initial)))
			)
			->pack_end(GTK2.HbuttonBox()
				->add(win->pb_send=GTK2.Button((["label":"_Send","use-underline":1,"focus-on-click":0])))
				->add(win->pb_close=GTK2.Button((["label":"_Close","use-underline":1,"focus-on-click":0])))
			,0,0,0)
		);
		win->mle->modify_font(G->G->window->getfont("input"));
		win->buf->set_modified(0);
		::makewindow();
	}

	void pb_send_click()
	{
		G->G->connection->write(conn,string_to_utf8(replace(String.trim_all_whites(
			win->buf->get_text(win->buf->get_start_iter(),win->buf->get_end_iter(),0)
		),"\n","\r\n"))+"\r\n");
		win->buf->set_modified(0);
	}

	void close_response(object self,int response)
	{
		self->destroy();
		if (response==GTK2.RESPONSE_OK) {win->buf->set_modified(0); pb_close_click();}
	}

	void pb_close_click()
	{
		if (win->buf->get_modified())
		{
			GTK2.MessageDialog(0,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK_CANCEL,"File has been modified, close without sending/saving?",win->mainwindow)
				->show()
				->signal_connect("response",close_response);
			return;
		}
		win->signals=0;
		win->mainwindow->destroy();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_send,"clicked",pb_send_click),
			gtksignal(win->pb_close,"clicked",pb_close_click),
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
		if (line=="<=== Editor ===>") {editor(conn,m_delete(conn,"editor_eax")); return 0;}
		conn->editor_eax+=line+"\n";
		return 0;
	}
}
