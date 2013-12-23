/*
Configure window-based logging. This is separate from world-based logging (done in
the Connect dialog); this log will pick up local messages (including its own at the
beginning of the log, identifying the file and the timestamp).
*/
inherit command;

int process(string param,mapping(string:mixed) subw)
{
	if (param=="" && !subw->logfile)
	{
		say("%% Usage: /log filename",subw);
		say("%% Will log all text to this subwindow to the specified file.",subw);
		return 1;
	}
	if (subw->logfile)
	{
		say("%% Closing log file at "+ctime(time()),subw);
		m_delete(subw,"logfile")->close();
	}
	if (mixed ex=param!="" && catch
	{
		subw->logfile=Stdio.File(param,"wac");
		say("%% Logging to "+param+" - "+ctime(time()));
	}) say("%% Error opening log file:\n%% "+describe_error(ex));
	return 1;
}
