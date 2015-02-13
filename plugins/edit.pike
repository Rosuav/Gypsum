//Pop-out editor - triggered by a special marker line from the server.
inherit hook;
inherit plugin_menu;
inherit command;
//To enable auto-wrapping: /x persist["editor/wrap"]=80
//TODO: Config dialog. Though it wouldn't really be much of one - just
//the wrap size - so maybe there ought to be a general plugin config
//system like Advanced Options. Ideally, plugins could register both a
//persist key and a function "call me if this changes"... or else the
//plugin just gets reloaded when that config entry is saved.

constant docstring=#"
Pop-out editor for server-side content

With help from the server, it can be possible to use a GUI editor for something
stored on the server. Without the server's help, it's still possible to bring
up an editor and manipulate text, prior to sending it. This can be used for
character descriptions, notes, board posts, or anything else that consists of
paragraphs of text.
";

constant plugin_active_by_default = 1;

class editor(mapping(string:mixed) subw,string initial)
{
	inherit movablewindow;
	constant is_subwindow=0;
	constant pos_key="editor/winpos";
	constant load_size=1;
	mapping(string:string) params;

	void create()
	{
		//Parameters, not part of the editable.
		//This is minorly incompatible with the RosMud editor; it would be majorly incompatible to put these params onto the initial
		//or final marker line, so this is the preferable form. Normally the edited content will begin with a command, so this should
		//be safe from false positives, but it does mean that the RosMud editor will send those back to the server. Hopefully a hash
		//followed by a space will never be a problem to any server (both Threshold RPG and Minstrel Hall respond with just "What?").
		//And of course, the hash line will be sent back only if the server sent it, so that really means only MH has to deal with it.
		//Currently-recognized parameters:
		//	line - line number for initial cursor position, default 0 ie first line of file
		//	col - column for initial cursor pos, default to 0 ie beginning of line; -1 for end of line
		//	once_use - if present (value is ignored), the Send button becomes Save/Quit, and will be used once only
		//Note that the parameter values are all strings, despite several of them looking like integers. Explicitly intify if needed.
		//Absence of a parameter is the only way to have an integer 0 in the mapping.
		//TODO: "framing" parameters - start command, end command - which will then be kept out of the actual popup
		//Hmm. Downside: Since this framing would be used by the server to say "save to this file name", it'd be harder
		//to hack a "save as" feature by editing the target file name. Is that a problem?
		sscanf(initial,"#%{ %s=%[^\n ]%}\n%s",array(array(string)) parm,initial);
		params=(mapping)(parm||([]));
		::create(); //No name. Each one should be independent. Note that this breaks compat-mode window position saving.
	}

	void makewindow()
	{
		//When we don't have a subw, 'initial' is actually a file name. Normally it's a block of text.
		string txt=subw && initial;
		if (mixed ex=!txt && catch {txt=String.trim_all_whites(utf8_to_string(Stdio.read_file(initial)||""))+"\n";})
			txt="Error reading "+initial+" - this editor works solely with UTF-8 encoded files.\n\n"+describe_error(ex);
		win->mainwindow=GTK2.Window((["title":"Pop-Out Editor","type":GTK2.WINDOW_TOPLEVEL]))->add(GTK2.Vbox(0,0)
			->add(GTK2.ScrolledWindow()
				->add(win->mle=GTK2.TextView(win->buf=GTK2.TextBuffer()->set_text(txt)))
			)
			->pack_end(GTK2.HbuttonBox()
				->add(win->pb_send=GTK2.Button((["label":params->once_use?"_Save/quit":subw?"_Send":"_Save","use-underline":1,"focus-on-click":0])))
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
		int line=(int)params->line,col=(int)params->col;
		GTK2.TextIter iter;
		if (col==-1)
		{
			iter=win->buf->get_iter_at_line(line+1);
			iter->backward_cursor_position();
		}
		else iter=win->buf->get_iter_at_line_offset(line,col);
		win->buf->select_range(iter,iter);
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

	void sig_pb_send_clicked()
	{
		//Note that we really need the conn, but are retaining the subw in case
		//the connection breaks and is reconnected. Alternatively, we could use
		//current_subw(), or maybe a check (subw if valid else current_subw) to
		//catch other cases.
		string txt=String.trim_all_whites(win->buf->get_text(win->buf->get_start_iter(),win->buf->get_end_iter(),0));
		if (!subw)
		{
			//Save to file instead of sending to the server.
			Stdio.write_file(initial,string_to_utf8(txt+"\n"));
			if (has_suffix(initial,".pike")) build(initial);
			else say(0,"%%%% Saved %s.",initial);
			win->buf->set_modified(0);
			return;
		}
		if (int wrap=persist["editor/wrap"]) txt=wrap_text(txt,wrap);
		send(subw,replace(txt,"\n","\r\n")+"\r\n");
		if (params->once_use) ::closewindow(); else win->buf->set_modified(0);
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

	void sig_pb_wrap_clicked()
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
			//This can crash old Pikes, due to over-freeing of the top stack object (whatever
			//it is). It's fixed in the latest, but not in 7.8.866, which I support - eg that
			//is what there's a Windows installer for. For want of a better name, I'm calling
			//this the 'boom2' issue (after the crash test script I wrote... yeah, I'm really
			//imaginative), so that's what the COMPAT marker is called.
			win->curpos && gtksignal(win->buf,"mark_set",cursorpos),
			win->pb_savepos && gtksignal(win->pb_savepos,"clicked",windowmoved),
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

//Note that the empty editor window brought up is tied to whichever subw was active when you hit it.
//This may be a bit surprising, so it might be better to go with the current subw as of when you hit
//Send, although that too can be surprising. Which is going to be less so?
constant menu_label="_Editor";
void menu_clicked()
{
	editor(G->G->window->current_subw(),"");
}

int process(string param,mapping(string:mixed) subw)
{
	if (param=="") {menu_clicked(); return 1;}
	if (mixed ex=catch {param=fn(param);}) {say(subw,"%% "+describe_error(ex)); return 1;}
	say(subw,"%%%% Pop-out editing %s",param);
	editor(0,param);
	return 1;
}

void create(string name) {::create(name);}
