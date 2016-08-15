constant docstring=#"
Configure window-based logging. This is separate from world-based logging (done in
the Connect dialog); this log will pick up local messages (including its own at the
beginning of the log, identifying the file and the timestamp).

REQUEST: This plugin has a number of issues. If you care about logging facilities,
please consider having a look in the source code, where there are lengthy comments
detailing the known problems; answers, ideas, or general thoughts would be greatly
welcomed. Thanks!
";
/*
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
20160419: There's now facilities for notebooks inside configdlgs, but not the other
way around. Not sure if that helps.

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

20140419: This really needs something, but I'm still not sure what. The logging
facilities exist in core (that's correct), and the configuration can be a plugin
(that's fine), but I still feel as I did above, that it shouldn't be three separate
menu items, nor a notebook. But what *should* it be? Or maybe I should actually cut
the options a bit. Maybe having window and connection logging is superfluous. Can I
do the whole thing as a single logging feature, with maybe a tick box "include input
lines"???

20140511: Still very much not happy with this :( But I might just drop filtered logs
altogether, and code that later as a dedicated plugin for grabbing guild titles. It
would then just be a matter of sorting out window and connection logging, and maybe
it would be best to simplify that down to just window logging, with autolog being
"independent, and happens to be a bit different", maybe. I don't like that idea, but
it's no worse than any other ideas I've had about this. TinyFugue had world logging
and global logging, but it had only one window (at least, the version I used was a
single-window system), so there was no confusion there; and also, the difference
between global and world was far more significant (as global would interleave worlds
according to your navigation between them - NOT what you will normally want).

20140511 (also): It's probably best to do these logs in the way REXX handles open
files: any given file name will only ever be open once. So if you point two worlds
to the same log file, they will interleave by lines as the content arrives. (Note
that connection logging is already done per-line, so you don't have to worry about
interleaved partial lines.) Easiest way to do that, I think, would be to have a
'mapping(string:Stdio.File) logfiles' in global state somewhere, and continue to
reference the files directly.

20141219: But when, with the above plan, would files ever be closed? Hrm. Hrm.
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
		subw->logfile=Stdio.File("Logs/"+param,"wac");
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
