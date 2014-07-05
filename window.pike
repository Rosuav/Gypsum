//GUI handler.

constant colnames=({"black","red","green","orange","blue","magenta","cyan","white"});
constant enumcolors=sprintf("%2d: ",enumerate(16)[*])[*]+(colnames+("bold "+colnames[*]))[*]; //Non-bold, then bold, of the same names, all prefixed with numbers.
array(array(int)) color_defs;
constant default_ts_fmt="%Y-%m-%d %H:%M:%S UTC";
array(GTK2.GdkColor) colors;

mapping(string:mapping(string:mixed)) channels=persist->setdefault("color/channels",([]));
constant deffont="Monospace 10";
mapping(string:mapping(string:mixed)) fonts=persist->setdefault("window/font",(["display":(["name":deffont]),"input":(["name":deffont])]));
mapping(string:mapping(string:mixed)) numpadnav=persist->setdefault("window/numpadnav",([])); //Technically doesn't have to be restricted to numpad.
multiset(string) numpadspecial=persist["window/numpadspecial"] || (<"look", "glance", "l", "gl">); //Commands that don't get prefixed with 'go ' in numpadnav
mapping(string:object) fontdesc=([]); //Cache of PangoFontDescription objects, for convenience (pruned on any font change even if something else was using it)
array(mapping(string:mixed)) tabs=({ }); //In the same order as the notebook's internal tab objects
GTK2.Window mainwindow;
GTK2.Notebook notebook;
#if constant(COMPAT_SIGNAL)
GTK2.Button defbutton;
#endif
GTK2.Hbox statusbar;
array(object) signals;
int paused;
mapping(GTK2.MenuItem:string) menu=([]); //Retain menu items and the names of their callback functions
inherit statustext;
int mono; //Set to 1 to paint the screen in monochrome
mapping(string:int) plugin_mtime=([]); //Map a plugin name to its file's mtime as of last update
array(GTK2.PangoTabArray) tabstops;
constant pausedmsg="<PAUSED>"; //Text used on status bar when paused; "" is used when not paused.

//Default set of worlds. Not currently actually used here - just for the setdefault().
mapping(string:mapping(string:mixed)) worlds=persist->setdefault("worlds",([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG","descr":"Threshold RPG by Frogdice, a high-fantasy game with roleplaying required."]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall","descr":"A virtual gaming shop where players gather to play Dungeons & Dragons online."]),
]));

/* I could easily add tab completion to the entry field. The only question is, what
should be added as suggestions?
1) Character names. Somehow it should figure out who's a character and who's not.
2) Objects in rooms that can be looked at.
3) Channel names, and then people on those channels
4) Other?
5) Local commands, if the user's already typed a slash. Should be easy enough.

Should it be context sensitive? It could be reconfigured in colorcheck().
*/

/* Each subwindow is defined with a mapping(string:mixed) - some useful elements are:

	//Each 'line' represents one line that came from the MUD. In theory, they might be wrapped for display, which would
	//mean taking up more than one display line, though currently this is not implemented.
	//Each entry must begin with a metadata mapping and then alternate between color and string, in that order.
	array(array(mapping|int|string)) lines=({ });
	array(mapping|int|string) prompt=({([])}); //NOTE: If this is ever reassigned, other than completely overwriting it, check pseudo-prompt handling.
	GTK2.DrawingArea display;
	GTK2.ScrolledWindow maindisplay;
	GTK2.Adjustment scr;
	GTK2.Entry ef;
	GTK2.Widget page;
	array(string) cmdhist=({ });
	int histpos=-1;
	int passwordmode; //When 1, commands won't be saved.
	int lineheight; //Pixel height of a line of text
	int totheight; //Current height of the display
	mapping connection;
	string tabtext;
	int activity=0; //Set to 1 when there's activity, set to 0 when focus is on this tab
	array(object) signals; //Collection of gtksignal objects - replaced after code reload
	int selstartline,selstartcol,selendline,selendcol; //Highlight start/end positions. If no highlight, selstartline will not even exist.
*/
mapping(string:mixed) subwindow(string txt)
{
	mapping(string:mixed) subw=(["lines":({ }),"prompt":({([])}),"cmdhist":({ }),"histpos":-1]);
	tabs+=({subw});
	//Build the subwindow
	notebook->append_page(subw->page=GTK2.Vbox(0,0)
		->add(subw->maindisplay=GTK2.ScrolledWindow((["hadjustment":GTK2.Adjustment(),"vadjustment":subw->scr=GTK2.Adjustment(),"background":"black"]))
			->add(subw->display=GTK2.DrawingArea())
			->set_policy(GTK2.POLICY_AUTOMATIC,GTK2.POLICY_ALWAYS)
		)
		->pack_end(subw->ef=GTK2.Entry(),0,0,0)
	->show_all(),GTK2.Label(subw->tabtext=txt))->set_current_page(sizeof(tabs)-1);
	//Note: It'd be nice if Ctrl-Z could do an Undo in in subw->ef. It's
	//probably impractical though - GTK doesn't offer that directly, I'd
	//have to do the work myself.
	setfonts(subw);
	#if constant(COMPAT_SIGNAL)
	subw->ef->set_activates_default(1);
	#endif
	subwsignals(subw);
	colorcheck(subw->ef,subw);
	call_out(redraw,0,subw);
	return subw;
}

/**
 * Return the subw mapping for the currently-active tab.
 */
mapping(string:mixed) current_subw() {return tabs[notebook->get_current_page()];}

/**
 * Get a suitable Pango font for a particular category. Will cache based on font name.
 *
 * @param	category	the category of font for which to collect the description
 * @return	PangoFontDescription	Font object suitable for GTK2
 */
GTK2.PangoFontDescription getfont(string category)
{
	string fontname=fonts[category]->name;
	return fontdesc[fontname] || (fontdesc[fontname]=GTK2.PangoFontDescription(fontname));
}

//Update the tabstops array based on a new pixel width
void settabs(int w)
{
	//This currently produces a spew of warnings. I don't know of a way to suppress them, and
	//everything does seem to be functioning correctly. So we suppress stderr for the moment.
	object silence_errors=redirect(Stdio.stderr);
	tabstops=(({GTK2.PangoTabArray})*8)(0,1); //Construct eight TabArrays (technically the zeroth one isn't needed)
	for (int i=1;i<20;++i) //Number of tab stops to place
		foreach (tabstops;int pos;object ta) ta->set_tab(i,GTK2.PANGO_TAB_LEFT,8*w*i-pos*w);
}

/**
 * Set/update fonts and font metrics
 *
 * @param subw Current subwindow
 */
void setfonts(mapping(string:mixed) subw)
{
	subw->display->modify_font(getfont("display"));
	subw->ef->modify_font(getfont("input"));
	mapping dimensions=subw->display->create_pango_layout("asdf")->index_to_pos(3);
	subw->lineheight=dimensions->height/1024; subw->charwidth=dimensions->width/1024;
	settabs(subw->charwidth);
}

/**
 * (Re)establish event handlers
 *
 * @param subw Current subwindow
 */
void subwsignals(mapping(string:mixed) subw)
{
	subw->signals=({
		gtksignal(subw->display,"expose_event",paint,subw),
		gtksignal(subw->scr,"changed",scrchange,subw),
		//gtksignal(subw->scr,"value_changed",lambda(mixed ... args) {write("value_changed: %O %O\n",subw->scr->get_value(),subw->scr->get_property("upper")-subw->scr->get_property("page size"));}),
		#if constant(COMPAT_SIGNAL)
		gtksignal(subw->ef,"key_press_event",keypress,subw),
		#else
		gtksignal(subw->ef,"key_press_event",keypress,subw,UNDEFINED,1),
		#endif
		gtksignal(subw->display,"button_press_event",mousedown,subw),
		gtksignal(subw->display,"button_release_event",mouseup,subw),
		gtksignal(subw->display,"motion_notify_event",mousemove,subw),
		gtksignal(subw->ef,"changed",colorcheck,subw),
		GTK2.GObject()->signal_stop && gtksignal(subw->ef,"paste_clipboard",paste,subw,UNDEFINED,1),
		gtksignal(subw->ef,"focus_in_event",focus,subw),
	});
	subw->display->add_events(GTK2.GDK_POINTER_MOTION_MASK|GTK2.GDK_BUTTON_PRESS_MASK|GTK2.GDK_BUTTON_RELEASE_MASK);
}

//Snapshot the selection bounds so the switchpage handler can reset them
int focus(object self,object ev,mapping subw) {subw->cursor_pos_last_focus_in=self->get_selection_bounds();}

/**
 * Update the scroll bar's range
 */
void scrchange(object self,mapping subw)
{
	if (paused) return;
	float upper=self->get_property("upper");
	#if constant(COMPAT_SCROLL)
	//On Windows, there's a problem with having more than 32767 of height. It seems to be resolved, though, by scrolling up to about 16K and then down again.
	//TODO: Solve this properly. Failing that, find the least flickery way to do this scrolling (would it still work if painting is disabled?)
	//Note that this is solved by updating GTK, so it may not be all that important after all.
	if (upper>32000.0) self->set_value(16000.0);
	#endif
	self->set_value(upper-self->get_property("page size"));
}

void paste(object self,mapping subw)
{
	//At this point, the clipboard contents haven't been put into the EF.
	//Preventing the normal behaviour depends on the widget having a
	//signal_stop() method, which was implemented in Pike 8.0.1+ and
	//7.8.820+. If that method is not available, the signal will not be
	//connected to (see above), so in this function, we assume that it
	//exists and can be used.
	string txt=self->get_clipboard(GTK2.Gdk_Atom("CLIPBOARD"))->wait_for_text();
	if (!txt || !has_value(txt,'\n')) return; //No text? Nothing will happen. One line of text? Let it go with the default.
	self->signal_stop("paste_clipboard"); //Prevent the full paste, we'll do it ourselves.
	array(string) lines=txt/"\n";
	sscanf(self->get_text(),"%"+self->get_position()+"s%s",string before,string after); //A bit hackish... get the text before and after the cursor :)
	enterpressed(subw,before+lines[0]);
	foreach (lines[1..<1],string l) enterpressed(subw,l);
	self->set_text(lines[-1]+after); self->set_position(sizeof(lines[-1]));
}

GTK2.Widget makestatus()
{
	statustxt->paused=GTK2.Label(pausedmsg);
	statustxt->paused->set_size_request(statustxt->paused->size_request()->width,-1)->set_text(""); //Have it consume space for the PAUSED message even without having it
	return GTK2.Hbox(0,10)->add(statustxt->lbl=GTK2.Label(""))->add(statustxt->paused);
}

//Convert (x,y) into (line,col) - yes, that switches their order.
//Depends on the current scr->pagesize.
//Note that line and col may exceed the array index limits by 1 - equalling sizeof(subw->lines) or the size of the string at that line.
//A return value equal to the array/string size represents the prompt or the (implicit) newline at the end of the string.
array(int) point_to_char(mapping subw,int x,int y)
{
	int line=(y-(int)subw->scr->get_property("page size"))/subw->lineheight;
	array l;
	if (line<0) line=0;
	if (line>=sizeof(subw->lines)) {line=sizeof(subw->lines); l=subw->prompt;}
	else l=subw->lines[line];
	string str=line_text(l);
	int pos=(x-3)/subw->charwidth;
	if (!has_value(str,'\t')) return ({line,limit(0,pos,sizeof(str))}); //There are no tabs in the line, simple.
	int realpos=0;
	foreach (str;int i;int ch)
	{
		if (ch=='\t') realpos+=8-realpos%8; else ++realpos;
		if (realpos>pos) return ({line,i});
	}
	return ({line,sizeof(str)});
}

/**
 * Clear any previous highlight, and highlight from (line1,col1) to (line2,col2)
 * Will trigger a repaint of all affected areas.
 * If line1==-1, will remove all highlight.
 */
void highlight(mapping subw,int line1,int col1,int line2,int col2)
{
	if (has_index(subw,"selstartline")) //There's a previous highlight. Clear it (by queuing draw for those lines).
	{
		//Note that the unhighlight sometimes isn't working when selstartline>selendline. Need to track down.
		int y1= min(subw->selstartline,subw->selendline)   *subw->lineheight;
		int y2=(max(subw->selstartline,subw->selendline)+1)*subw->lineheight;
		subw->display->queue_draw_area(0,subw->scr->get_property("page size")+y1,1<<30,y2-y1);
	}
	if (line1==-1) {m_delete(subw,"selstartline"); subw->display->queue_draw(); return;} //Unhighlight (with a full redraw for safety)
	subw->selstartline=line1; subw->selstartcol=col1; subw->selendline=line2; subw->selendcol=col2;
	int y1= min(line1,line2)   *subw->lineheight;
	int y2=(max(line1,line2)+1)*subw->lineheight;
	subw->display->queue_draw_area(0,subw->scr->get_property("page size")+y1,1<<30,y2-y1);
}

void mousedown(object self,object ev,mapping subw)
{
	[int line,int col]=point_to_char(subw,(int)ev->x,(int)ev->y);
	highlight(subw,line,col,line,col);
	subw->mouse_down=1;
	subw->boxsel = ev->state&GTK2.GDK_SHIFT_MASK; //Note that box-vs-stream is currently set based on shift key as mouse went down. This may change.
}

void mouseup(object self,object ev,mapping subw)
{
	int mouse_down=m_delete(subw,"mouse_down"); //Destructive query
	if (!mouse_down) return; //Mouse wasn't registered as down, do nothing.
	subw->autoscroll=0; //When the mouse comes up, we stop scrolling.
	[int line,int col]=point_to_char(subw,(int)ev->x,(int)ev->y);
	string content;
	if (mouse_down==1)
	{
		//Mouse didn't move between going down and going up. Consider it a click.
		highlight(subw,-1,0,0,0);
		//Go through the line clicked on. Find one single word in one single color, and that's
		//what was clicked on. TODO: Optionally permit the user to click on something with a
		//modifier key (eg Ctrl-Click) to execute something as a command - would play well with
		//help files highlighted in color, for instance.
		foreach ((line==sizeof(subw->lines))?subw->prompt:subw->lines[line],mixed x) if (stringp(x))
		{
			col-=sizeof(x); if (col>0) continue;
			col+=sizeof(x); //Go back to the beginning of this color block - we've found something.
			foreach (x/" ",string word)
			{
				col-=sizeof(word)+1; if (col>=0) continue;
				//We now have the exact word, delimited by color boundary and blank space.
				if (has_prefix(word,"http://") || has_prefix(word,"https://") || has_prefix(word,"www."))
					invoke_browser(word);
				return;
			}
		}
		//Couldn't find anything to click on.
		return;
	}
	if (subw->selstartline==line)
	{
		//Single-line selection: special-cased for simplicity.
		if (subw->selstartcol>col) [col,subw->selstartcol]=({subw->selstartcol,col});
		content=line_text((line==sizeof(subw->lines))?subw->prompt:subw->lines[line])+"\n";
		content=content[subw->selstartcol..col-1];
	}
	else
	{
		if (subw->selstartline>line) [line,col,subw->selstartline,subw->selstartcol]=({subw->selstartline,subw->selstartcol,line,col});
		if (subw->boxsel && subw->selstartcol>col) [col,subw->selstartcol]=({subw->selstartcol,col});
		content="";
		for (int l=subw->selstartline;l<=line;++l)
		{
			string curline=line_text((l==sizeof(subw->lines))?subw->prompt:subw->lines[l]);
			if (subw->boxsel) content+=curline[subw->selstartcol..col-1]+"\n";
			else if (l==line) content+=curline[..col-1];
			else if (l==subw->selstartline) content+=curline[subw->selstartcol..]+"\n";
			else content+=curline+"\n";
		}
	}
	highlight(subw,-1,0,0,0);
	subw->display->get_clipboard(GTK2.Gdk_Atom("CLIPBOARD"))->set_text(content);
}

string hovertext(mapping subw,int line)
{
	string txt=sprintf("Line %d of %d",line,sizeof(subw->lines));
	catch
	{
		mapping meta = (line==sizeof(subw->lines) ? subw->prompt : subw->lines[line])[0];
		if (!mappingp(meta)) break;
		//Note: If the line has no timestamp (such as the prompt after a local command),
		//this will show the epoch in either UTC or local time. This looks a bit weird,
		//but is actually less weird than omitting the timestamp altogether and having
		//the box suddenly narrow. Yes, there'll be some odd questions about why there's
		//a timestamp of 1970 (or 1969 if you're behind UTC and showing localtime), but
		//on the whole, that's going to bug people less than the flickering of width is.
		mapping ts=(persist["window/timestamp_local"]?localtime:gmtime)(meta->timestamp);
		txt+="  "+strftime(persist["window/timestamp"]||default_ts_fmt,ts);
		//Add further meta-information display here
	}; //Ignore errors
	return txt;
}

void mousemove(object self,object ev,mapping subw)
{
	[int line,int col]=point_to_char(subw,(int)ev->x,(int)ev->y);
	setstatus(hovertext(subw,line));
	if (!subw->mouse_down) return; //All below depends on having the mouse button held down.
	if (line!=subw->selendline || col!=subw->selendcol)
	{
		subw->mouse_down=2; //Mouse has moved.
		highlight(subw,subw->selstartline,subw->selstartcol,line,col);
	}
	float low=subw->scr->get_value(),high=low+subw->scr->get_property("page size");
	if (ev->y<low) subw->autoscroll=low-ev->y;
	else if (ev->y>high) subw->autoscroll=high-ev->y;
	else subw->autoscroll=0;
	if (subw->autoscroll && !subw->autoscroll_callout) subw->autoscroll_callout=call_out(autoscroll,0.1,subw);
}

void autoscroll(mapping subw)
{
	if (!subw->autoscroll || !subw->mouse_down) {m_delete(subw,"autoscroll_callout"); return;}
	subw->autoscroll_callout=call_out(autoscroll,0.1,subw);
	subw->scr->set_value(limit(0.0,subw->scr->get_value()-subw->autoscroll,subw->scr->get_property("upper")-subw->scr->get_property("page size")));
	//Optional: Trigger a mousemove with the mouse at its current location, to update highlight. Not a big deal if not (just a display oddity).
}

/**
 * Add a line of output (anything other than a prompt)
 * If msg is an array, it is assumed to be alternating colors and text.
 * Otherwise, additional arguments will be processed with sprintf().
 */
void say(mapping|void subw,string|array msg,mixed ... args)
{
	if (!subw) subw=current_subw();
	if (stringp(msg))
	{
		if (sizeof(args)) msg=sprintf(msg,@args);
		if (msg[-1]=='\n') msg=msg[..<1];
		foreach (msg/"\n",string line) say(subw,({7,line}));
		return;
	}
	if (!mappingp(msg[0])) msg=({([])})+msg;
	msg[0]->timestamp=time(1);
	//Clean up any empty strings in msg, for efficiency
	for (int i=2;i<sizeof(msg);i+=2) if (msg[i]=="") {msg=msg[..i-2]+msg[i+1..]; i-=2;}
	if (subw->logfile) subw->logfile->write(string_to_utf8(line_text(msg)+"\n"));
	array lines=({ });
	//Wrap msg into lines, making at least one entry. Note that, in current implementation,
	//it'll wrap at any color change as if it were a space. This is unideal, but it
	//simplifies the code a bit.
	int wrap=persist["window/wrap"]; string wrapindent=persist["window/wrapindent"]||"";
	int pos=0;
	if (wrap) for (int i=2;i<sizeof(msg);i+=2)
	{
		int end=pos+sizeof(msg[i]);
		if (end<=wrap) {pos=end; continue;}
		array cur=msg[..i];
		string part=msg[i];
		end=wrap-pos;
		if (sizeof(part)>end)
		{
			int wrappos=end;
			if (!persist["window/wraptochar"]) while (wrappos && part[wrappos]!=' ') --wrappos;
			//If there are no spaces, break at the color change (if there's text before it), or just break where there's no space.
			//Note that this will refuse to break at or within the wrapindent, on subsequent lines (to prevent an infinite loop).
			if ((!wrappos || (sizeof(lines) && wrappos<=sizeof(wrapindent))) && !pos) wrappos=wrap;
			cur[-1]=part[..wrappos-1];
			msg=({msg[0]+([]),msg[i-1],wrapindent+String.trim_all_whites(part[wrappos..])})+msg[i+1..];
		}
		lines+=({cur});
		i=pos=0;
	}
	subw->lines+=lines+({msg});
	subw->activity=1;
	if (!mainwindow->is_active()) switch (persist["notif/activity"])
	{
		case 1: if (subw!=current_subw()) break; //Play with fall-through. If the config option is 2, present the window regardless of current_page; if it's one, present only if current page; otherwise, don't present.
		case 2: if (paused) break; //Present the window only if we're not paused.
			//Okay, so let's present ourselves.
			if (persist["notif/present"]) mainwindow->present();
			else mainwindow->set_urgency_hint(1);
	}
	redraw(subw);
}

/**
 * Connect to a world
 */
void connect(mapping info,string world,mapping|void subw)
{
	if (!subw) subw=current_subw();
	if (!info)
	{
		//Disconnect
		if (!subw->connection || !subw->connection->sock) return; //Silent if nothing to dc
		subw->connection->sock->close(); G->G->connection->sockclosed(subw->connection);
		return;
	}
	subw->world=world;
	if (subw->connection && subw->connection->sock) {say(subw,"%% Already connected."); return;}
	subw->connection=G->G->connection->connect(subw,info);
	subw->tabtext=info->tabtext || info->name || "(unnamed)";
}

void redraw(mapping subw)
{
	int height=(int)subw->scr->get_property("page size")+subw->lineheight*(sizeof(subw->lines)+1);
	if (height!=subw->totheight) subw->display->set_size_request(-1,subw->totheight=height);
	if (subw==current_subw()) subw->activity=0;
	//Check the current tab text before overwriting, to minimize flicker
	string tabtext="* "*subw->activity+subw->tabtext;
	if (notebook->get_tab_label_text(subw->page)!=tabtext) notebook->set_tab_label_text(subw->page,tabtext);
	subw->maindisplay->queue_draw();
}

int mkcolor(int fg,int bg)
{
	return fg | (bg<<16);
}

//Paint one piece of text at (x,y), returns the x for the next text.
void painttext(array state,string txt,GTK2.GdkColor fg,GTK2.GdkColor bg)
{
	if (txt=="") return;
	[GTK2.DrawingArea display,GTK2.GdkGC gc,int x,int y,int tabpos]=state;
	object layout=display->create_pango_layout(txt);
	if (has_value(txt,'\t'))
	{
		if (tabpos) layout->set_tabs(tabstops[tabpos]); //else the defaults will work fine
		state[4]=sizeof((txt/"\t")[-1])%8;
	}
	else state[4]=(tabpos+sizeof(txt))%8;
	mapping sz=layout->index_to_pos(sizeof(txt)-1);
	if (bg!=colors[0]) //Why can't I just set_background and then tell draw_text to cover any background pixels? Meh.
	{
		gc->set_foreground(bg); //(sic)
		display->draw_rectangle(gc,1,x,y,(sz->x+sz->width)/1024,sz->height/1024);
	}
	gc->set_foreground(fg);
	display->draw_text(gc,x,y,layout);
	destruct(layout);
	state[2]=x+(sz->x+sz->width)/1024;
}

//Paint one line of text at the given 'y'. Will highlight from hlstart to hlend with inverted fg/bg colors.
void paintline(GTK2.DrawingArea display,GTK2.GdkGC gc,array(mapping|int|string) line,int y,int hlstart,int hlend)
{
	array state=({display,gc,3,y,0}); //State passed on to painttext() and modifiable by it. Could alternatively be done as a closure.
	for (int i=mappingp(line[0]);i<sizeof(line);i+=2) if (sizeof(line[i+1]))
	{
		GTK2.GdkColor fg,bg;
		if (mono) {fg=colors[0]; bg=colors[15];} //Override black on white for pure readability
		else {fg=colors[line[i]&15]; bg=colors[(line[i]>>16)&15];} //Normal
		string txt=replace(line[i+1],"\n","\\n");
		if (hlend<0) hlstart=sizeof(txt); //No highlight left to do.
		if (hlstart>0) painttext(state,txt[..hlstart-1],fg,bg); //Draw the leading unhighlighted part (which might be the whole string).
		if (hlstart<sizeof(txt))
		{
			painttext(state,txt[hlstart..min(hlend,sizeof(txt))],bg,fg); //Draw the highlighted part (which might be the whole string).
			if (hlend<sizeof(txt)) painttext(state,txt[hlend+1..],fg,bg); //Draw the trailing unhighlighted part.
		}
		hlstart-=sizeof(txt); hlend-=sizeof(txt);
	}
	if (hlend>=0 && hlend<1<<29) //In block selection mode, draw highlight past the end of the string, if necessary
	{
		if (hlstart>0) {painttext(state," "*hlstart,colors[7],colors[0]); hlend-=hlstart;}
		if (hlend>=0) painttext(state," "*(hlend+1),colors[0],colors[7]);
	}
}

int paint(object self,object ev,mapping subw)
{
	int start=ev->y-subw->lineheight,end=ev->y+ev->height+subw->lineheight; //We'll paint complete lines, but only those lines that need painting.
	GTK2.DrawingArea display=subw->display; //Cache, we'll use it a lot
	display->set_background(colors[mono && 15]); //In monochrome mode, background is all white.
	GTK2.GdkGC gc=GTK2.GdkGC(display);
	int y=(int)subw->scr->get_property("page size");
	int ssl=subw->selstartline,ssc=subw->selstartcol,sel=subw->selendline,sec=subw->selendcol;
	if (zero_type(ssl)) ssl=sel=-1;
	else if (ssl>sel || (ssl==sel && ssc>sec)) [ssl,ssc,sel,sec]=({sel,sec,ssl,ssc}); //Get the numbers forward rather than backward
	if (subw->boxsel && ssc>sec) [ssc,sec]=({sec,ssc}); //With box selection, row and column are independent.
	int endl=min((end-y)/subw->lineheight,sizeof(subw->lines));
	for (int l=max(0,(start-y)/subw->lineheight);l<=endl;++l)
	{
		array(mapping|int|string) line=(l==sizeof(subw->lines)?subw->prompt:subw->lines[l]);
		int hlstart=-1,hlend=-1;
		if (l>=ssl && l<=sel)
		{
			if (subw->boxsel) {hlstart=ssc; hlend=sec-1;}
			else
			{
				if (l==ssl) hlstart=ssc;
				if (l==sel) hlend=sec-1; else hlend=1<<30;
			}
		}
		paintline(display,gc,line,y+l*subw->lineheight,hlstart,hlend);
	}
}

void settext(mapping subw,string text)
{
	subw->ef->set_text(text);
	subw->ef->set_position(sizeof(text));
}

int keypress(object self,array|object ev,mapping subw)
{
	if (arrayp(ev)) ev=ev[0];
	switch (ev->keyval)
	{
		case 0xFF0D: case 0xFF8D: enterpressed(subw); return 1; //Enter (works only when COMPAT_SIGNAL not needed)
		case 0xFF52: //Up arrow
		{
			if (subw->histpos==-1)
			{
				subw->histpos=sizeof(subw->cmdhist);
				subw->last_ef=subw->ef->get_text();
			}
			if (!subw->histpos) return 1;
			int pos = (ev->state&GTK2.GDK_CONTROL_MASK) && subw->ef->get_position();
			string txt = subw->ef->get_text();
			string pfx = txt[..pos-1];
			int hp=subw->histpos;
			while (hp && (!has_prefix(subw->cmdhist[--hp],pfx) || subw->cmdhist[hp]==txt));
			if (has_prefix(subw->cmdhist[hp],pfx)) settext(subw,subw->cmdhist[subw->histpos=hp]);
			if (ev->state&GTK2.GDK_CONTROL_MASK) subw->ef->set_position(pos);
			return 1;
		}
		case 0xFF54: //Down arrow
		{
			if (subw->histpos==-1) switch (persist["window/downarr"])
			{
				case 2: //Save into history
					string cmd=subw->ef->get_text();
					if (cmd!="" && (!sizeof(subw->cmdhist) || cmd!=subw->cmdhist[-1])) subw->cmdhist+=({cmd});
					subw->histpos=-1;
				case 1: subw->ef->set_text(""); //Blank the EF
				default: return 1;
			}
			int pos = (ev->state&GTK2.GDK_CONTROL_MASK) && subw->ef->get_position();
			string txt = subw->ef->get_text();
			string pfx = txt[..pos-1];
			int hp=subw->histpos;
			while (++hp<sizeof(subw->cmdhist) && (!has_prefix(subw->cmdhist[hp],pfx) || subw->cmdhist[hp]==txt));
			if (hp<sizeof(subw->cmdhist)) settext(subw,subw->cmdhist[subw->histpos=hp]);
			//Note that the handling of this feature of the up arrow is actually here in the *down* arrow's code.
			else if (pfx=="" && persist["window/uparr"]) {settext(subw,subw->last_ef); subw->histpos=-1;}
			else {subw->ef->set_text(pfx); subw->histpos=-1;}
			if (ev->state&GTK2.GDK_CONTROL_MASK) subw->ef->set_position(pos);
			return 1;
		}
		case 0xFF1B: //Esc
			if (has_index(subw,"selstartline")) {highlight(subw,-1,0,0,0); subw->mouse_down=0;}
			else subw->ef->set_text(""); //Clear EF if there's nothing to unhighlight
			return 1;
		case 0xFF09: case 0xFE20: //Tab and shift-tab
		{
			if (ev->state&GTK2.GDK_CONTROL_MASK)
			{
				//Not using notebook->{next|prev}_page() as they don't cycle.
				int page=notebook->get_current_page();
				if (ev->state&GTK2.GDK_SHIFT_MASK) {if (--page<0) page=notebook->get_n_pages()-1;}
				else {if (++page>=notebook->get_n_pages()) page=0;}
				notebook->set_current_page(page);
				return 1;
			}
			subw->ef->set_position(subw->ef->insert_text("\t",1,subw->ef->get_position()));
			return 1;
		}
		case 0xFF55: //PgUp
		{
			if (ev->state&GTK2.GDK_CONTROL_MASK)
			{
				//Scroll up to last activity. Note that this is stored by scrollbar
				//position, not line index, so a change of font/size might disrupt it.
				//The value will be clamped to the range, so the worst effect is that
				//it'll take an extra hit of PgUp to get to normality. Not a big deal.
				if (subw->last_activity) subw->scr->set_value(subw->last_activity);
				subw->paused=1; statustxt->paused->set_text(pausedmsg);
				return 1;
			}
			object scr=subw->scr; scr->set_value(scr->get_value()-scr->get_property("page size"));
			return 1;
		}
		case 0xFF56: //PgDn
		{
			object scr=subw->scr;
			float pg=scr->get_property("page size");
			if (ev->state&GTK2.GDK_CONTROL_MASK)
			{
				//Snap down to the bottom and unpause.
				scr->set_value(scr->get_property("upper")-pg);
				paused=0;
				statustxt->paused->set_text("");
				return 1;
			}
			scr->set_value(min(scr->get_value()+pg,scr->get_property("upper")-pg));
			return 1;
		}
		#if constant(DEBUG)
		case 0xFFE1: case 0xFFE2: //Shift
		case 0xFFE3: case 0xFFE4: //Ctrl
		case 0xFFE7: case 0xFFE8: //Windows keys
		case 0xFFE9: case 0xFFEA: //Alt
			break;
		default: say(subw,"%%%% keypress: %X",ev->keyval); break;
		#endif
	}
	if (mapping numpad=numpadnav[sprintf("%x",ev->keyval)])
	{
		string cmd=numpad->cmd;
		//Should *all* slash commands be permitted? That might be clean.
		if (cmd=="/lastnav") {G->G->commands->lastnav("",subw); return 1;}
		if (!numpadspecial[cmd] && !has_prefix(cmd,"go ")) cmd="go "+cmd;
		if (!subw->lastnav) subw->lastnav=({ });
		if (has_prefix(cmd,"go ")) subw->lastnav+=({cmd[3..]});
		if (persist["window/numpadecho"]) enterpressed(subw,cmd);
		else send(subw->connection,cmd+"\r\n");
		return 1;
	}
}

void enterpressed(mapping subw,string|void cmd)
{
	if (!cmd) {cmd=subw->ef->get_text(); subw->ef->set_text("");}
	subw->histpos=-1;
	subw->prompt[0]->timestamp=time(1);
	m_delete(subw->prompt[0],"text"); //Wipe the cached text version of the line, which is now going to be wrong
	if (!persist["window/hideinput"])
	{
		if (!subw->passwordmode)
		{
			if (cmd!="" && (!sizeof(subw->cmdhist) || cmd!=subw->cmdhist[-1])) subw->cmdhist+=({cmd});
			say(subw,subw->prompt+({6,cmd}));
		}
		else subw->lines+=({subw->prompt});
	}
	subw->prompt[0]=([]); //Reset the info mapping (which gets timestamp and such) but keep the prompt itself; it's execcommand's job to remove it.
	subw->last_activity=subw->scr->get_property("upper")-subw->scr->get_property("page size");
	if (has_prefix(cmd,"//")) cmd=cmd[1..];
	else if (has_prefix(cmd,"/"))
	{
		redraw(subw);
		sscanf(cmd,"/%[^ ] %s",cmd,string args);
		if (G->G->commands[cmd] && G->G->commands[cmd](args||"",subw)) return;
		say(subw,"%% Unknown command.");
		return 0;
	}
	if (array nav=m_delete(subw,"lastnav")) subw->lastnav_desc=nav*", ";
	execcommand(subw,cmd,0);
}

/**
 * Execute a command, passing it via hooks
 * If skiphook is nonzero, will skip all hooks up to and including that name.
 * If the subw is in password mode, hooks will not be called at all.
 */
void execcommand(mapping subw,string cmd,string|void skiphook)
{
	if (!subw->passwordmode)
	{
		array names=indices(G->G->hooks),hooks=values(G->G->hooks); sort(names,hooks); //Sort by name for consistency
		for (int i=0;i<sizeof(hooks);++i) if (!skiphook || skiphook<names[i])
			if (mixed ex=catch {if (hooks[i]->inputhook(cmd,subw)) {redraw(subw); return;}}) say(subw,"Error in input hook: "+describe_backtrace(ex));
	}
	subw->prompt=({([])}); redraw(subw);
	send(subw->connection,cmd+"\r\n");
}

/**
 * Engage/disengage password mode
 */
void   password(mapping subw) {subw->passwordmode=1; subw->ef->set_visibility(0);}
void unpassword(mapping subw) {subw->passwordmode=0; subw->ef->set_visibility(1);}

constant file_addtab=({"_New Tab",'t',GTK2.GDK_CONTROL_MASK});
void addtab() {subwindow("New tab");}

/**
 * Actually close a tab - that is, assume the user has confirmed the closing or doesn't need to
 */
void real_closetab(int removeme)
{
	if (sizeof(tabs)<2) addtab();
	tabs[removeme]->signals=0; connect(0,0,tabs[removeme]);
	tabs=tabs[..removeme-1]+tabs[removeme+1..];
	notebook->remove_page(removeme);
	if (!sizeof(tabs)) addtab();
}

/**
 * First-try at closing a tab. May call real_closetab() or raise a prompt.
 */
constant file_closetab=({"Close Tab",'w',GTK2.GDK_CONTROL_MASK});
void closetab()
{
	int removeme=notebook->get_current_page();
	if (persist["window/confirmclose"]==-1 || !tabs[removeme]->connection || !tabs[removeme]->connection->sock) real_closetab(removeme); //TODO post 7.8: Use ?->sock for this
	else confirm(0,"You have an active connection, really close this tab?",mainwindow,real_closetab,removeme);
}

/* This is called "zadvoptions" rather than "advoptions" to force its menu item
to be at the end of the Options menu. It's a little odd, but that's the only
one that needs to be tweaked to let the menu simply be in funcname order. */
constant options_zadvoptions="Ad_vanced options";
class zadvoptions
{
	inherit configdlg;
	mapping(string:mapping(string:mixed)) items=([
		//Keep these in alphabetical order for convenience - they'll be shown in that order anyway
		"Activity alert":(["path":"notif/activity","type":"int","default":0,"desc":"The Gypsum window can be 'presented' to the user in a platform-specific way. When should this happen?","options":([0:"Never present the window",1:"Present on activity in current tab",2:"Present on any activity"])]),
		"Beep":(["path":"notif/beep","type":"int","default":0,"desc":"When the server requests a beep, what should be done?\n\n0: Try both the following, in order\n1: Call on an external 'beep' program\n2: Use the GTK2 beep() action\n99: Suppress the beep entirely"]),

		//Compat note (about COMPAT(), yes, I am aware of the irony): The ?: check is to cope with having been booted with a driver pre 6e7681.
		#define COMPAT(x) " Requires restart."+(has_index(all_constants(),"COMPAT_"+upper_case(x))?"\n\nCurrently active.":"\n\nCurrently inactive.")+"\n\nYou do NOT normally need to change this.","type":"int","default":0,"path":"compat/"+x,"options":([0:"Autodetect"+(G->compat?({" (disable)"," (enable)"})[G->compat[x]]:""),1:"Enable compatibility mode",2:"Disable compatibility mode"])
		"Compat: Scroll":(["desc":"Some platforms have display issues with having more than about 2000 lines of text. The fix is a slightly ugly 'flicker' of the scroll bar."COMPAT("scroll")]),
		"Compat: Events":(["desc":"Older versions of Pike cannot do 'before' events. The fix involves simulating them in various ways, with varying levels of success."COMPAT("signal")]),
		"Compat: Boom2":(["desc":"Older versions of Pike have a bug that can result in a segfault under certain circumstances."COMPAT("boom2")]),
		"Compat: Pause key":(["desc":"On some systems, the Pause key generates the wrong key code. If pressing Pause doesn't pause scrolling, try toggling this."COMPAT("pausekey")]),

		"Confirm on Close":(["path":"window/confirmclose","type":"int","default":0,"desc":"Normally, Gypsum will prompt before closing, in case you didn't mean to close.","options":([0:"Confirm if there are active connections",1:"Always confirm",-1:"Never confirm, incl when closing a tab"])]),
		"Down arrow":(["path":"window/downarr","type":"int","default":0,"desc":"When you press Down when you haven't been searching back through command history, what should be done?","options":([0:"Do nothing, leave the text there",1:"Clear the input field",2:"Save into history and clear input"])]),
		"Hide input":(["path":"window/hideinput","type":"int","default":0,"desc":"Local echo is active by default, but set this to disable it and hide all your commands.","options":([0:"Disabled (show commands)",1:"Enabled (hide commands)"])]),
		"Keep-Alive":(["path":"ka/delay","default":240,"desc":"Number of seconds between keep-alive messages. Set this to a little bit less than your network's timeout. Note that this should not reset the server's view of idleness and does not violate the rules of Threshold RPG.","type":"int"]),
		"Numpad Nav echo":(["path":"window/numpadecho","default":0,"desc":"Enable this to have numpad navigation commands echoed as if you'd typed them; disabling gives a cleaner display.","type":"int","options":([0:"Disabled",1:"Enabled"])]),
		"Present action":(["path":"notif/present","type":"int","default":0,"desc":"Activity alerts can present the window in one of two ways. Note that the exact behaviour depends somewhat on your window manager.","options":([0:"Mark the window as 'urgent'",1:"Request immediate presentation"])]),
		"Timestamp":(["path":"window/timestamp","default":default_ts_fmt,"desc":"Display format for line timestamps as shown when the mouse is hovered over them. Uses strftime markers. TODO: Document this better."]),
		"Timestamp localtime":(["path":"window/timestamp_local","default":0,"desc":"Line timestamps can be displayed in your local time rather than in UTC, if you wish.","type":"int","options":([0:"Normal - use UTC",1:"Use your local time"])]),
		"Up arrow":(["path":"window/uparr","type":"int","default":0,"desc":"When you press Up to begin searching back through command history, should the current text be saved and recalled when you come back down to it?","options":([0:"No",1:"Yes"])]),
		"Wrap":(["path":"window/wrap","default":0,"desc":"Wrap text to the specified width (in characters). 0 to disable.","type":"int"]),
		"Wrap indent":(["path":"window/wrapindent","default":"","desc":"Indent/prefix wrapped text with the specified text - a number of spaces works well."]),
		"Wrap to chars":(["path":"window/wraptochar","type":"int","desc":"Normally it makes sense to wrap at word boundaries (spaces) where possible, but you can disable this if you wish.","options":([0:"Default - wrap to words",1:"Wrap to characters"])]),
	]);
	constant allow_new=0;
	constant allow_rename=0;
	constant allow_delete=0;
	mapping(string:mixed) windowprops=(["title":"Advanced Options"]);
	void create() {::create();}

	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10)
			->pack_start(win->kwd=GTK2.Label((["yalign":1.0])),0,0,0)
			->pack_start(win->value=GTK2.Entry()->set_no_show_all(1),0,0,0)
			->pack_start(win->select=SelectBox(({}))->set_no_show_all(1),0,0,0)
			->pack_end(win->desc=GTK2.Label((["xalign":0.0,"yalign":0.0]))->set_size_request(300,150)->set_line_wrap(1),1,1,0)
		;
	}

	void save_content(mapping(string:mixed) info)
	{
		mixed value=win->value->get_text();
		if (info->options) value=search(info->options,win->select->get_text());
		if (info->type=="int") value=(int)value; else value=(string)value;
		persist[info->path]=value;
	}

	void load_content(mapping(string:mixed) info)
	{
		mixed val=persist[info->path]; if (zero_type(val) && !zero_type(info->default)) val=info->default;
		if (mapping opt=info->options)
		{
			win->value->hide(); win->select->show();
			win->select->set_strings(sort(values(opt)));
			win->select->set_text(opt[val]);
		}
		else
		{
			win->select->hide(); win->value->show();
			win->value->set_text((string)val);
		}
		win->desc->set_text(info->desc);
	}
}

constant options_channelsdlg="_Channel Colors";
class channelsdlg
{
	inherit configdlg;
	constant ints=({"r","g","b"});
	constant persist_key="color/channels";
	mapping(string:mixed) windowprops=(["title":"Channel colors"]);
	void create() {::create();} //Pass on no args to the parent

	GTK2.Widget make_content()
	{
		return two_column(({
			"Channel name",win->kwd=GTK2.Entry(),
			"Color (0-255)",GTK2.Hbox(0,10)
				->add(GTK2.Label("Red"))
				->add(win->r=GTK2.Entry()->set_size_request(40,-1))
				->add(GTK2.Label("Green"))
				->add(win->g=GTK2.Entry()->set_size_request(40,-1))
				->add(GTK2.Label("Blue"))
				->add(win->b=GTK2.Entry()->set_size_request(40,-1))
		}));
	}

	void load_content(mapping(string:mixed) info)
	{
		if (zero_type(info["r"])) {info->r=info->g=info->b=255; ({win->r,win->g,win->b})->set_text("255");}
	}
}

constant options_colorsdlg="Co_lors";
class colorsdlg
{
	inherit configdlg;
	constant ints=({"r","g","b"});
	constant allow_new=0,allow_delete=0,allow_rename=0;
	mapping(string:mixed) windowprops=(["title":"Channel colors"]);
	void create()
	{
		items=([]);
		foreach (color_defs;int i;[int r,int g,int b]) items[enumcolors[i]]=(["r":r,"g":g,"b":b]);
		::create();
	}

	GTK2.Widget make_content()
	{
		win->kwd=GTK2.Label("13: bold magenta"); //The longest name in the list
		win->kwd->set_size_request(win->kwd->size_request()->width,-1)->set_text("");
		return two_column(({
			"Color",noex(win->kwd),
			"Red",noex(win->r=GTK2.Entry()->set_size_request(40,-1)),
			"Green",noex(win->g=GTK2.Entry()->set_size_request(40,-1)),
			"Blue",noex(win->b=GTK2.Entry()->set_size_request(40,-1)),
			"Colors range from 0 to 255.\nNote that all colors set\nhere are ignored in\nmonochrome mode.",0,
		}));
	}

	void save_content(mapping(string:mixed) info)
	{
		int idx=(int)win->kwd->get_text(); //Will ignore a leading space and everything from the colon on.
		array val=({info->r,info->g,info->b});
		if (equal(val,color_defs[idx])) return; //No change.
		color_defs[idx]=val;
		colors[idx]=GTK2.GdkColor(@val);
		persist["colors/sixteen"]=color_defs; //This may be an unnecessary mutation, but it's simpler to leave this out of persist[] until it's actually changed.
		redraw(current_subw());
	}
}

constant options_fontdlg="_Font";
class fontdlg
{
	inherit configdlg;
	constant persist_key="window/font";
	constant allow_new=0;
	void create() {::create();}

	GTK2.Widget make_content()
	{
		win->list->set_enable_search(0); //Disable the type-ahead search, which is pretty useless when there are this few items
		return GTK2.Vbox(0,0)
			->add(win->kwd=GTK2.Label((["label":"Section","xalign":0.5])))
			->add(win->fontsel=GTK2.FontSelection())
		;
	}

	void save_content(mapping(string:mixed) info)
	{
		string name=win->fontsel->get_font_name();
		if (info->name==name) return; //No change, no need to dump the cached object
		info->name=name;
		m_delete(fontdesc,name);
		setfonts(tabs[*]);
		redraw(tabs[*]);
		tabs->display->set_background(colors[0]); //For some reason, failing to do this results in the background color flipping to grey when fonts are changed. Weird.
	}

	void load_content(mapping(string:mixed) info)
	{
		if (info->name) win->fontsel->set_font_name(info->name);
	}
}

//TODO: For the standard ones (0xffb[0-9]), show a more friendly description, not just the hex code
//This may require a generalized system of model changes, where the TreeModel doesn't simply report
//the keys of the mapping, but does some processing on them. Experimentation required.
constant options_keyboard="_Keyboard";
class keyboard
{
	inherit configdlg;
	constant strings=({"cmd"});
	constant persist_key="window/numpadnav";
	mapping(string:mixed) windowprops=(["title":"Numeric keypad navigation"]);
	void create() {::create("keyboard");}

	GTK2.Widget make_content()
	{
		return two_column(({
			"Key (hex code)",win->kwd=GTK2.Entry(),
			"Press key here ->",win->key=GTK2.Entry(),
			"Command",win->cmd=GTK2.Entry(),
		}));
	}

	void makewindow()
	{
		::makewindow();
		//Add a button to the bottom row. Note that this is coming up at the far right,
		//which I'm not happy with; I'd rather put it in the middle somewhere. But packing
		//buttons from the start/end doesn't seem to make any difference to an HbuttonBox.
		win->buttonbox->add(win->pb_std=GTK2.Button((["label":"Standard","use-underline":1])));
	}

	int keypress(object self,array|object ev)
	{
		if (arrayp(ev)) ev=ev[0];
		switch (ev->keyval) //Let some keys through untouched
		{
			case 0xFFE1..0xFFEE: //Modifier keys
			case 0xFF09: case 0xFE20: //Tab/shift-tab
				return 0;
		}
		win->kwd->set_text(sprintf("%x",ev->keyval));
		return 1;
	}

	void stdkeys()
	{
		object store=win->list->get_model();
		foreach (({"look","southwest","south","southeast","west","glance","east","northwest","north","northeast"});int i;string cmd)
		{
			if (!numpadnav["ffb"+i])
			{
				numpadnav["ffb"+i]=(["cmd":cmd]);
				store->set_value(store->append(),0,"ffb"+i);
			}
			else numpadnav["ffb"+i]->cmd=cmd;
		}
		persist->save();
		selchanged();
	}

	void pb_std()
	{
		confirm(0,"Adding/updating standard nav keys will overwrite anything you currently have on those keys. Really do it?",win->mainwindow,stdkeys);
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			#if constant(COMPAT_SIGNAL)
			gtksignal(win->key,"key_press_event",keypress),
			#else
			gtksignal(win->key,"key_press_event",keypress,0,UNDEFINED,1),
			#endif
			gtksignal(win->pb_std,"clicked",pb_std),
		});
	}
}

constant help_aboutdlg="_About";
class aboutdlg
{
	inherit window;
	void create() {::create();}

	void makewindow()
	{
		string ver=gypsum_version();
		if (ver!=INIT_GYPSUM_VERSION) ver=sprintf("%s (upgraded from %s)",ver,INIT_GYPSUM_VERSION);
		win->mainwindow=GTK2.Window((["title":"About Gypsum","transient-for":G->G->window->mainwindow]))->add(GTK2.Vbox(0,0)
			->add(GTK2.Label(#"Pike MUD client for Windows/Linux/Mac (and others)

Free software - see README for license terms

By Chris Angelico, rosuav@gmail.com

Version "+ver+", as far as can be ascertained :)"))
			->add(GTK2.HbuttonBox()->add(stock_close()))
		);
		::makewindow();
	}
}

constant options_promptsdlg="_Prompts";
class promptsdlg
{
	inherit window;
	void create() {::create();}

	string wrap(string txt)
	{
		//return noex(GTK2.Label(replace(txt,({"\n","\t"}),({" ",""})))->set_line_wrap(1)->set_justify(GTK2.JUSTIFY_LEFT));
		return replace(txt,({"\n","\t"}),({" ",""}));
	}

	void makewindow()
	{
		win->mainwindow=GTK2.Window((["title":"Configure prompts","transient-for":G->G->window->mainwindow]))->add(GTK2.Vbox(0,20)
			->add(GTK2.Label("Prompts from the server are easy for a human to\nrecognize, but not always for the computer."))
			->add(GTK2.Frame("TELNET codes")
				->add(GTK2.Label("The ideal is for prompts to be marked with\nIAC GA. This works perfectly and is guaranteed."))
			)
			->add(GTK2.Frame("Magic prompt marker")->add(GTK2Table(({
				({"Next best is a special marker from the server. If this\nends a socket-read, it is treated as a prompt.",0}),
				({"Marker:",win->promptsuffix=GTK2.Entry()->set_text(persist["prompt/suffix"]||"==> ")}),
				({"Blank this to suppress this feature.",0}),
			}))))
			->add(GTK2.Frame("Pseudo-prompts")->add(GTK2Table(({
				({wrap(#"Finally, a piece of text that ends a socket-read may be interpreted as a pseudo-prompt if it ends
				with a typical marker. For most MUDs this would be a colon or a greater-than symbol - :> - but you may
				want to either add to or remove from that list. The marker character may be followed by whitespace
				but nothing else; it may be preceded by anything (the entire line will become the prompt)."),0}),
				({"Pseudo-prompt tail characters:",
					win->promptpseudo = GTK2.Entry()->set_text((stringp(persist["prompt/pseudo"]) && persist["prompt/pseudo"]) || ":>")
				}),
				({"Again, blank this list to suppress this feature.",0}),
				({wrap(#"Alternatively, you could treat every partial line as a pseudo-prompt, regardless of what it ends
				with. This tends to be ugly, but will work; rather than key in every possible ending character above,
				simply tick this box."),0}),
				({win->allpseudo=GTK2.CheckButton("All partial lines are pseudo-prompts"),0}),
				({wrap(#"Since pseudo-prompts are often going to be incorrectly recognized, you may prefer to have
				inputted commands not remove them from the subsequent line. With a guess that can have as many false
				positives as false negatives, it's a judgement call whether to aim for the positive or aim for the
				negative, so take your pick which one you find less ugly. With this option unticked (the default),
				a false positive will result in a broken line if you happen to type a command right at that moment;
				with it ticked, every pseudo-prompt will end up being duplicated into the next line of normal text."),0}),
				({win->retainpseudo=GTK2.CheckButton("Retain pseudo-prompts after commands"),0}),
			}),(["wrap":1,"justify":GTK2.JUSTIFY_LEFT,"xalign":0.0]))))
			->add(GTK2.HbuttonBox()
				->add(win->pb_ok=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_OK])))
				->add(stock_close())
			)
		);
		win->allpseudo->set_active(persist["prompt/pseudo"]==1.0);
		win->retainpseudo->set_active(persist["prompt/retain_pseudo"]);
	}

	void pb_ok_click()
	{
		if (win->allpseudo->get_active()) persist["prompt/pseudo"]=1.0;
		else persist["prompt/pseudo"]=win->promptpseudo->get_text();
		persist["prompt/suffix"]=win->promptsuffix->get_text();
		persist["prompt/retain_pseudo"]=win->retainpseudo->get_active();
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_ok,"clicked",pb_ok_click),
		});
	}
}

/* The official key value (GDK_KEY_Pause) is 0xFF13, but Windows produces 0xFFFFFF (GDK_KEY_VoidSymbol)
instead - and also produces it for other keys, eg Caps Lock. */
constant options_pause=({"Pause scroll",all_constants()["COMPAT_PAUSEKEY"]?0xFFFFFF:0xFF13,0});
void pause()
{
	paused=!paused;
	statustxt->paused->set_text(pausedmsg*paused);
}

constant options_monochrome="_Monochrome";
void monochrome()
{
	mono=!mono;
	call_out(redraw,0,current_subw());
}

/**
 *
 */
void colorcheck(object self,mapping subw)
{
	array(int) col=({255,255,255});
	if (mapping c=channels[(self->get_text()/" ")[0]]) col=({c->r,c->g,c->b});
	if (equal(subw->cur_fg,col)) return;
	subw->cur_fg=col;
	self->modify_base(GTK2.STATE_NORMAL,GTK2.GdkColor(0,0,0));
	self->modify_text(GTK2.STATE_NORMAL,GTK2.GdkColor(@col));
}

/*
Policy note on core plugins (this belongs somewhere, but I don't know where): Unlike
RosMud, where plugins were the bit you could reload separately and the core required
a shutdown, there's no difference here between window.pike and plugins/timer.pike.
The choice of whether to make something core or plugin should now be made on the basis
of two factors. Firstly, anything that should be removable MUST be a plugin; core code
is always active. That means that anything that creates a window, statusbar entry, or
other invasive or space-limited GUI content, should be a plugin. And secondly, the
convenience of the code. If it makes good sense to have something create a command of
its own name, for instance, it's easier to make it a plugin; but if something needs
to be called on elsewhere, it's better to make it part of core (maybe globals). The
current use of plugins/update.pike by other modules is an unnecessary dependency; it
may still be convenient to have /update handled by that file, but the code that's
called on elsewhere should be broken out into core.
*/
void discover_plugins(string dir)
{
	mapping(string:mapping(string:mixed)) plugins=persist["plugins/status"];
	foreach (get_dir(dir),string fn)
	{
		fn=combine_path(dir,fn);
		if (file_stat(fn)->isdir) discover_plugins(fn);
		else if (has_suffix(fn,".pike") && !plugins[fn])
		{
			//Try to compile the plugin. If that succeeds, look for a constant plugin_active_by_default;
			//if it's found, that's the default active state. (Normally, if it's present, it'll be 1.)
			add_constant("COMPILE_ONLY",1);
			program compiled; catch {compiled=compile_file(fn);};
			add_constant("COMPILE_ONLY");
			plugins[fn]=(["active":compiled && compiled->plugin_active_by_default]);
		}
	}
}

constant plugins_configure_plugins="_Configure";
class configure_plugins
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Activate/deactivate plugins"]);
	constant allow_rename=0;
	constant persist_key="plugins/status";
	//NOTE: Cannot use simple bindings as it needs to know the previous state
	//Note also: This does not unload plugins on deactivation. Maybe it should?

	void create() {discover_plugins("plugins"); ::create("plugins/configure");}

	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10) //Note that the "useless" Vbox here means that two_column doesn't expand to fill the height, which looks tidier.
			->pack_start(two_column(({
				"Filename",win->kwd=GTK2.Entry(),
				"",win->active=GTK2.CheckButton("Active"),
				"NOTE: Deactivating a plugin will not unload it.\nUse the /unload command or restart Gypsum.",0,
			})),0,0,0);
	}

	void load_content(mapping(string:mixed) info)
	{
		win->active->set_active(info->active);
	}

	void save_content(mapping(string:mixed) info)
	{
		int nowactive=win->active->get_active();
		if (!info->active && nowactive)
		{
			string param=selecteditem();
			say(0,"%% Compiling "+param+"...");
			program compiled; catch {compiled=compile_file(param);};
			if (!compiled) {say(0,"%% Compilation failed.\n"); return 0;}
			say(0,"%% Compiled.");
			compiled(param);
		}
		info->active=nowactive;
	}
}

void create(string name)
{
	add_gypsum_constant("say",say);
	G->G->connection->say=say;
	if (!G->G->window)
	{
		GTK2.setup_gtk();
		mainwindow=GTK2.Window(GTK2.WindowToplevel);
		mainwindow->set_title("Gypsum");
		if (array pos=persist["window/winpos"])
		{
			pos+=({800,600}); mainwindow->set_default_size(pos[2],pos[3]);
			mainwindow->move(pos[0],pos[1]);
		}
		else mainwindow->set_default_size(800,500);
		GTK2.AccelGroup accel=G->G->accel=GTK2.AccelGroup();
		G->G->plugin_menu=([]);
		mainwindow->add_accel_group(accel)->add(GTK2.Vbox(0,0)
			->pack_start(GTK2.MenuBar()
				//Note these odd casts: set_submenu() expects a GTK2.Widget, and for some
				//reason won't accept a GTK2.Menu, which is a subclass of Widget.
				->add(GTK2.MenuItem("_File")->set_submenu((object)GTK2.Menu()))
				->add(GTK2.MenuItem("_Options")->set_submenu((object)GTK2.Menu()))
				->add(GTK2.MenuItem("_Plugins")->set_submenu((object)(G->G->plugin_menu[0]=GTK2.Menu())))
				->add(GTK2.MenuItem("_Help")->set_submenu((object)GTK2.Menu()))
			,0,0,0)
			->add(notebook=GTK2.Notebook())
			->pack_end(statusbar=GTK2.Hbox(0,0),0,0,0)
			#if constant(COMPAT_SIGNAL)
			->pack_end(defbutton=GTK2.Button()->set_size_request(0,0)->set_flags(GTK2.CAN_DEFAULT),0,0,0)
			#endif
		)->show_all();
		#if constant(COMPAT_SIGNAL)
		defbutton->grab_default();
		#endif
		addtab();
		call_out(mainwindow->present,0); //After any plugin windows have loaded, grab - or attempt to grab - focus back to the main window.
	}
	else
	{
		object other=G->G->window;
		colors=other->colors; color_defs=other->color_defs; notebook=other->notebook; mainwindow=other->mainwindow;
		#if constant(COMPAT_SIGNAL)
		defbutton=other->defbutton;
		#endif
		tabs=other->tabs; statusbar=other->statusbar;
		if (other->signals) other->signals=0; //Clear them out, just in case.
		if (other->menu) menu=other->menu;
		if (other->plugin_mtime) plugin_mtime=other->plugin_mtime;
		foreach (tabs,mapping subw) subwsignals(subw);
	}
	G->G->window=this;
	statustxt->tooltip="Hover a line to see when it happened";
	::create(name);

	if (!color_defs)
	{
		color_defs=persist["color/sixteen"]; //Note: Assumed to be exactly sixteen arrays of exactly three ints each.
		if (!color_defs)
		{
			//Default color definitions: the standard ANSI colors.
			array bits = map(enumerate(8),lambda(int x) {return ({x&1,!!(x&2),!!(x&4)});});
			color_defs = (bits[*][*]*127) + (bits[*][*]*255);
			//The strict bitwise definition would have bold black looking black. It should be a bit darker than nonbold white, so we change it.
			color_defs[8] = color_defs[7]; color_defs[7] = ({192,192,192});
		}
	}
	if (!colors) colors = Function.splice_call(color_defs[*],GTK2.GdkColor); //Note that the @ short form can't replace splice_call here.

	/* Not quite doing what I want, but it's a start...

	GTK2.ListStore ls=GTK2.ListStore(({"string"}));
	GTK2.EntryCompletion compl=GTK2.EntryCompletion()->set_model(ls)->set_text_column(0)->set_minimum_key_length(2);
	foreach (sort(indices(G->G->commands)),string kwd) ls->set_value(ls->append(),0,"/"+kwd);
	tabs[0]->ef->set_completion(compl);
	*/

	//Build or rebuild the menus
	//Note that this code depends on there being four menus: File, Options, Plugins, Help.
	//If that changes, compatibility code will be needed.
	array(GTK2.Menu) submenus=mainwindow->get_child()->get_children()[0]->get_children()->get_submenu();
	foreach (submenus,GTK2.Menu submenu) foreach (submenu->get_children(),GTK2.MenuItem w) {w->destroy(); destruct(w);}
	//Neat hack: Build up a mapping from a prefix like "options" (the part before the underscore
	//in the constant name) to the submenu object it should be appended to.
	mapping(string:GTK2.Menu) menus=([]);
	[menus->file,menus->options,menus->plugins,menus->help] = submenus;
	foreach (sort(indices(this_program)),string const) if (object menu=sscanf(const,"%s_%s",string pfx,string name) && name && menus[pfx])
	{
		program me=this_program; //Note that this_program[const] doesn't work in Pike 7.8.700 due to a bug fixed in afa24a.
		array|string info=me[const]; //The workaround is to assign this_program to a temporary and index that instead.
		GTK2.MenuItem item=arrayp(info)
			? GTK2.MenuItem(info[0])->add_accelerator("activate",G->G->accel,info[1],info[2],GTK2.ACCEL_VISIBLE)
			: GTK2.MenuItem(info); //String constants are just labels; arrays have accelerator key and modifiers.
		item->show()->signal_connect("activate",this[name]);
		menu->add(item);
	}
	//Recreate plugin menu items in name order
	foreach (sort(indices(G->G->plugin_menu)),string name) if (mapping mi=name && G->G->plugin_menu[name])
		if (!mi->menuitem) mi->self->make_menuitem(name);

	mainwsignals();

	//Scan for plugins now that everything else is initialized.
	mapping(string:mapping(string:mixed)) plugins=persist->setdefault("plugins/status",([]));
	//Compat: Pull in the list from plugins/more.pike's config
	if (mapping old=persist["plugins/more/list"])
	{
		foreach (old;string fn;mapping info) plugins[fn-"-more"]=info; //Cheat a bit, remove any instance of -more from the filename
		m_delete(persist,"plugins/more/list"); //Delete at the end, just in case something goes wrong
	}
	//Prune the plugins list to only what actually exists
	foreach (plugins;string fn;) if (!file_stat(fn)) m_delete(plugins,fn);
	discover_plugins("plugins");
	persist->save(); //Autosave (even if nothing's changed, currently)
	foreach (sort(indices(plugins)),string fn)
	{
		//TODO: Should the configure_plugins dlg also manipulate plugin_mtime?
		if (plugins[fn]->active)
		{
			int mtime=file_stat(fn)->mtime;
			if (mtime!=plugin_mtime[fn] && !catch {G->bootstrap(fn);}) plugin_mtime[fn]=mtime;
		}
		else m_delete(plugin_mtime,fn);
	}
	settabs(tabs[0]->charwidth);
}

int window_destroy() {exit(0);}

constant file_save_html="Save as _HTML";
void save_html()
{
	object dlg=GTK2.FileChooserDialog("Save scrollback as HTML",mainwindow,
		GTK2.FILE_CHOOSER_ACTION_SAVE,({(["text":"Save","id":GTK2.RESPONSE_OK]),(["text":"Cancel","id":GTK2.RESPONSE_CANCEL])})
	)->show_all();
	dlg->signal_connect("response",save_html_response);
	dlg->set_filename(".");
}

void save_html_response(object self,int btn)
{
	string fn=self->get_filename();
	self->destroy();
	if (btn!=GTK2.RESPONSE_OK) return;
	mapping(string:mixed) subw=current_subw();
	Stdio.File f=Stdio.File(fn,"wct");
	//TODO: Batch up the writes for efficiency
	f->write("<!doctype html><html><head><meta charset=\"UTF-8\"><title>Gypsum session - Save as HTML</title><style type=\"text/css\">\n");
	//Write out styles, foreground and background
	foreach (colors;int i;object col) f->write(sprintf("%%{.%%sg%d {%%scolor: #%02X%02X%02X}\n%%}",i,@col->rgb()),({({"f",""}),({"b","background-"})}));
	f->write("</style></head><body class=bg0><hr><pre><code>\n");
	foreach (subw->lines;int lineno;array line)
	{
		f->write("<span title=\"%s\">",hovertext(subw,lineno));
		for (int i=1;i<sizeof(line);i+=2)
			f->write("<span class='fg%d bg%d'>%s</span>",line[i]&15,(line[i]>>16)&15,string_to_utf8(Parser.encode_html_entities(line[i+1])));
		f->write("</span>\n");
	}
	f->write("</code></pre><hr></body></html>\n");
	f->close();
	MessageBox(0,GTK2.MESSAGE_INFO,GTK2.BUTTONS_OK,"Saved to "+fn,mainwindow);
}

constant file_window_close="E_xit";
int window_close()
{
	int confirmclose=persist["window/confirmclose"];
	if (confirmclose==-1) exit(0);
	int conns=sizeof((tabs->connection-({0}))->sock-({0})); //Number of active connections (would look tidier with ->? but I need to support 7.8).
	if (!conns && !confirmclose) exit(0);
	confirm(0,"You have "+conns+" active connection(s), really quit?",mainwindow,exit,0);
	return 1; //Used as the delete-event, so it should return 1 for that.
}

constant file_connect_menu="_Connect";
class connect_menu
{
	inherit configdlg;
	constant strings=({"name","host","logfile","descr","writeme"});
	constant ints=({"port"});
	constant bools=({"use_ka"});
	constant persist_key="worlds";

	mapping(string:mixed) windowprops=(["title":"Connect to a world"]);
	void create() {::create();} //Pass on no args

	void load_content(mapping(string:mixed) info)
	{
		if (!info->port) {info->port=23; win->port->set_text("23");}
		if (zero_type(info->use_ka)) win->use_ka->set_active(1);
	}

	void save_and_connect()
	{
		pb_save();
		string kwd=selecteditem();
		if (!kwd) return;
		mapping info=items[kwd];
		G->G->window->connect(info,kwd,0);
		win->mainwindow->destroy();
	}

	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10)
			->pack_start(two_column(({
				"Keyword",win->kwd=GTK2.Entry(),
				"Name",win->name=GTK2.Entry(),
				"Host name",win->host=GTK2.Entry(),
				"Port",win->port=GTK2.Entry(),
				"Auto-log",win->logfile=GTK2.Entry(),
				"",win->use_ka=GTK2.CheckButton("Use keep-alive"), //No separate label
			})),0,0,0)
			->add(GTK2.Frame("Description")->add(
				win->descr=MultiLineEntryField()->set_size_request(250,70)
			))
			->add(GTK2.Frame("Text to output upon connect")->add(
				win->writeme=MultiLineEntryField()->set_size_request(250,70)
			))
			->pack_start(GTK2.HbuttonBox()->add(
				win->pb_connect=GTK2.Button((["label":"Save and C_onnect","use-underline":1]))
			),0,0,0)
		;
	}

	void dosignals()
	{
		::dosignals();
		win->signals+=({
			gtksignal(win->pb_connect,"clicked",save_and_connect),
		});
	}
}

constant file_disconnect_menu="_Disconnect";
void disconnect_menu(object self) {connect(0,0,0);}

int showev(object self,array ev,int dummy) {werror("%O->%O\n",self,(mapping)ev[0]);}

#if constant(COMPAT_SIGNAL)
/**
 * COMPAT_SIGNAL bouncer
 */
int enterpressed_glo(object self)
{
	object focus=mainwindow->get_focus();
	if (function f=G->G->enterpress[focus]) return f();
	object parent=focus->get_parent();
	while (parent->get_name()!="GtkNotebook") parent=(focus=parent)->get_parent();
	enterpressed(tabs[parent->page_num(focus)]);
	return 1;
}

/**
 * COMPAT_SIGNAL window position saver hack
 */
constant options_savewinpos="Save all window positions";
void savewinpos()
{
	windowmoved();
	values(G->G->windows)->save_position_hook();
}
#endif

int switchpage(object self,mixed segfault,int page,mixed otherarg)
{
	//CAUTION: The first GTK-supplied parameter is a pointer to a GtkNotebookPage, and it
	//comes through as a Pike object - which it isn't. Doing *ANYTHING* with that value
	//is liable to segfault Pike. However, since it's a pretty much useless value anyway,
	//ignore it and just use 'page' (which is the page index). I'm keeping this here as
	//sort of documentation, hence it includes an 'otherarg' arg (which I'm not using -
	//an additional argument to signal_connect/gtksignal would provide that value here)
	//and names all the arguments. All I really need is 'page'. End caution.
	mapping subw=tabs[page];
	subw->activity=0;
	//Reset the cursor pos based on where it was last time focus entered the EF. This is
	//distinctly weird, but it prevents the annoying default behaviour of selecting all.
	if (subw->cursor_pos_last_focus_in) subw->ef->select_region(@subw->cursor_pos_last_focus_in);
	call_out(lambda(int page,mapping subw) {
		//NOTE: Doing this work inside the signal handler can segfault Pike, so do it
		//on the backend. (Probably related to the above caution.) The same applies
		//if the args are omitted (making this a closure).
		notebook->set_tab_label_text(subw->page,subw->tabtext);
		if (notebook->get_current_page()==page) subw->ef->grab_focus();
		if (subw->cursor_pos_last_focus_in) subw->ef->select_region(@subw->cursor_pos_last_focus_in);
	},0,page,subw);
}

mapping(string:int) pos;
void windowmoved()
{
	if (!pos) call_out(savepos,0.1); //Save a moment after the window moves. "Sweep" movement creates a spew of these events, don't keep saving.
	pos=mainwindow->get_position(); //Will return x and y
}

void savepos()
{
	mapping sz=mainwindow->get_size();
	persist["window/winpos"]=({pos->x,pos->y,sz->width,sz->height});
	pos=0;
	redraw(current_subw()); //Update the scroll bar in case the height changed
}

//Reset the urgency hint when focus arrives.
//Ideally I want to do this at the exact moment when mainwindow->is_active()
//changes from 0 to 1, but I can't find that. In lieu of such an event, I'm
//going for something that fires on various focus movements within the main
//window; it'll never fire when we don't have window focus, so it's safe.
void window_focus() {mainwindow->set_urgency_hint(0);}

void mainwsignals()
{
	signals=({
		gtksignal(mainwindow,"destroy",window_destroy),
		gtksignal(mainwindow,"delete_event",window_close),
		gtksignal(notebook,"switch_page",switchpage),
		#if constant(COMPAT_SIGNAL)
		gtksignal(defbutton,"clicked",enterpressed_glo),
		#else
		gtksignal(mainwindow,"configure_event",windowmoved,0,UNDEFINED,1),
		#endif
		gtksignal(mainwindow,"focus_in_event",window_focus),
	});
	#if constant(COMPAT_SIGNAL)
	if (!G->G->enterpress) G->G->enterpress=([]);
	#endif
}
