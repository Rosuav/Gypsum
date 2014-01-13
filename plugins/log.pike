/*
Configure window-based logging. This is separate from world-based logging (done in
the Connect dialog); this log will pick up local messages (including its own at the
beginning of the log, identifying the file and the timestamp).
*/
inherit command;
inherit plugin_menu;

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
