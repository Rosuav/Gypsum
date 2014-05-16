inherit hook;
//To enable auto-wrapping: /x persist["editor/wrap"]=80
//TODO: Config dialog.

constant plugin_active_by_default = 1;

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
				#if !constant(COMPAT_BOOM2)
				->add(GTK2.Frame("Cursor")->add(win->curpos=GTK2.Label("")))
				#elif constant(COMPAT_SIGNAL)
				->add(win->pb_savepos=GTK2.Button("Save pos"))
				#else
				->add(GTK2.Label("(cursor pos)"))
				#endif
				->add(win->pb_wrap=GTK2.Button("Wrap"))
				->add(stock_close()->set_focus_on_click(0))
			,0,0,0)
		);
		win->mle->modify_font(G->G->window->getfont("input"));
		win->buf->set_modified(0);
		::makewindow();
	}

	string wrap_text(string txt,int wrap)
	{
		array lines=txt/"\n";
		foreach (lines;int i;string l)
		{
			if (sizeof(l)<wrap && !has_value(l,'\t')) continue; //Trivially short enough
			array(string) sublines=({ });
			while (1)
			{
				int pos,wrappos;
				for (int p=0;p<sizeof(l) && pos<wrap;++p) switch (l[p])
				{
					case '\t': pos+=8-pos%8; break;
					case ' ': wrappos=p; //p, not pos, and fall through
					default: ++pos;
				}
				if (pos<wrap) {sublines+=({l}); break;} //No more wrapping to do.
				sublines+=({l[..wrappos-1]});
				l=l[wrappos+1..];
			}
			lines[i]=sublines*"\n"; //Optional: Indent subsequent lines, by multiplying by "\n  " or similar.
		}
		return lines*"\n";
	}

	void pb_send_click()
	{
		//Note that we really need the conn, but are retaining the subw in case
		//the connection breaks and is reconnected. Alternatively, we could use
		//current_subw(), or maybe a check (subw if valid else current_subw) to
		//catch other cases.
		string txt=String.trim_all_whites(win->buf->get_text(win->buf->get_start_iter(),win->buf->get_end_iter(),0));
		if (int wrap=persist["editor/wrap"]) txt=wrap_text(txt,wrap);
		send(subw,replace(txt,"\n","\r\n")+"\r\n");
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

	void wrap_input()
	{
		int wrap=persist["editor/wrap"] || 80; //Default to 80 chars here; clicking Wrap should always wrap, even if autowrap isn't happening.
		string txt=String.trim_all_whites(win->buf->get_text(win->buf->get_start_iter(),win->buf->get_end_iter(),0));
		string newtxt=wrap_text(txt,wrap);
		if (newtxt!=txt) win->buf->set_text(newtxt+"\n");
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_send,"clicked",pb_send_click),
			//NOTE: This currently crashes Pike, due to over-freeing of the top stack object
			//(whatever it is). Am disabling this code until a patch is deployed.
			//The solution is deep inside the Pike GTK support code and can't be worked
			//around, so this depends on a Pike patch. For want of a better name, I'm calling
			//this the 'boom2' issue (after the crash test script I wrote... yeah, I'm really
			//imaginative), so that's what the COMPAT marker is called.
			win->curpos && gtksignal(win->buf,"mark_set",cursorpos),
			win->pb_savepos && gtksignal(win->pb_savepos,"clicked",windowmoved),
			gtksignal(win->pb_wrap,"clicked",wrap_input),
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
