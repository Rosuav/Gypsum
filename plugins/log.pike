/*
Configure window-based logging. This is separate from world-based logging (done in
the Connect dialog); this log will pick up local messages (including its own at the
beginning of the log, identifying the file and the timestamp).

TODO: Make this fully configure logging. There are two ways to log, with a third
proposed, and this should be able to manage them all:
1) Window-based logging, by creating a subw->logfile. Allow this to be done for any
   current subw (showing their tabtext, maybe, and what file's open, if any).
2) Connection-based logging, by creating a conn->logfile. Again, allow this to be
   done for any current connection (has to have an open socket); this is independent
   of autologging, except for the fact that autologging will create a conn->logfile.
3) (Proposed) Filtered logging, which will probably be a subset of one of the other
   two. Or maybe it's a subset of (something)-based logging but across all subw/conn
   rather than tied to one. There are a set of "Start" triggers (probably regex) and
   a set of "Stop" triggers (ditto).
   - If current line matches a start trigger, logging becomes On.
   - If logging is On, log current line.
   - If current line matches a stop trigger, logging becomes Off.
   This way, specific lines can be logged by duplicating the start trigger into stop.
Hmm. Can I make a Notebook with three configdlg tabs? No, probably not worth it. But
this will most likely end up copying and pasting some code from configdlg. Per Rule
of Three, this is permitted; but anything that I recognize as existing elsewhere,
it's time to break out into a separate place.

20140214 [a good day to be datestamping, btw]: I'm really not happy with how this is
working out in my head. Should it put three separate entries on the plugin_menu (if
that's even made possible, which it isn't currently)? Should it make a submenu with
three items? One menu item that brings up... a notebook? A mini-window with three
buttons that bring up more windows? A single unified window with radio buttons on
each item to specify what "sort" of log it is? None feels right. So far I'm leaning
toward the notebook idea, but it's clunky. The subw log has to offer just current
tabs and nothing more; the world log would need to offer a (not necessarily proper)
subset thereof; and the regex log allows you to add your own, maybe name them, and
specify whether they're start or stop rules. Or maybe it should let you create some
log files and then bind regexes to them. In any case, it's distinctly different from
the other two. But breaking this out into three (or even two, merging subw and conn)
separately-configured plugins is definitely wrong. Really really not happy with this
and hoping someone else has some ideas.
*/
inherit command;
inherit plugin_menu;

constant plugin_active_by_default = 1;

int process(string param,mapping(string:mixed) subw)
{
	if (param=="" && !subw->logfile)
	{
		say(subw,"%% Usage: /log filename");
		say(subw,"%% Will log all text to this subwindow to the specified file.");
		return 1;
	}
	if (subw->logfile)
	{
		say(subw,"%% Closing log file at "+ctime(time()));
		m_delete(subw,"logfile")->close();
	}
	if (mixed ex=param!="" && catch
	{
		subw->logfile=Stdio.File(param,"wac");
		say(subw,"%% Logging to "+param+" - "+ctime(time()));
	}) say(subw,"%% Error opening log file:\n%% "+describe_error(ex));
	return 1;
}

constant menu_label="Logging";
void menu_clicked()
{
	say(0,"%% To enable logging for this subwindow:");
	say(0,"%% > /log filename");
	say(0,"%% (TODO: Have a file dialog on this menu item.)");
}

void create(string name) {::create(name);}
