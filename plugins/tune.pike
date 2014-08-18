/*
Tune people out on Threshold. Ported from C++; some code modelled off Hurkle's oocbox.
Way WAY simpler than the C++ version, though it doesn't (bother to) keep stats.
*/

inherit command;
inherit hook;
inherit plugin_menu;

constant plugin_active_by_default = 1;

mapping(string:mapping(string:mixed)) tuned = persist->setdefault("tune/thresholdrpg", ([])); //Persist key permits other systems to be added.
constant channels=(<"-{Citizen}-","[court]","[trivia]","[sports]">); //TODO: Make configurable, now that it's easy

int outputhook(string line,mapping(string:mixed) conn)
{
    /* Hurkle's Pascal code:
  if (strpos(line, '[court]') <> nil) then
    LastlineType := LINETYPE_COURT
  else if (strpos(line, '{Citizen}') <> nil) then
    LastlineType := LINETYPE_CITIZEN
  else if (strpos(line, '[trivia]') <> nil) then
    LastlineType := LINETYPE_TRIVIA
  else if (strpos(line, '[sports]') <> nil) then
    LastlineType := LINETYPE_SPORTS
  else if (LastlineType = LINETYPE_CITIZEN) and
          (strlcomp(line, '            ', 12) = 0) and (line[12]<>' ') then
    LastlineType := LINETYPE_CITIZEN
  else if (LastlineType = LINETYPE_TRIVIA) and
          (strlcomp(line, '     ', 5) = 0) and (line[5]<>' ') then
    LastlineType := LINETYPE_TRIVIA
  else if (LastlineType = LINETYPE_SPORTS) and
          (strlcomp(line, '     ', 5) = 0) and (line[5]<>' ') then
    LastlineType := LINETYPE_SPORTS
  else if (LastlineType = LINETYPE_COURT) and
          (strlcomp(line, '     ', 5) = 0) and (line[5]<>' ') then
    LastlineType := LINETYPE_COURT
  else
    LastlineType := LINETYPE_IC;
    */
	sscanf(line,"%*[ ]%n%s",int spaces,line);
	//Continuation line: Citizen has twelve spaces, the others have five.
	if ((spaces==12 && conn->tune_lastline=="-{Citizen}-") || (spaces==5 && conn->tune_lastline)) return 1;
	[string word1,string word2]=(line/" "+({0}))[..1]; //Could be channel and name, or name and channel
	if (word1=="-{Citizen}-" && word2[-1]==':') word2=word2[..<1]; //Citizen is special. The name might be terminated by a colon.
	if ((channels[word1] && tuned[lower_case(word2)]) || (channels[word2] && tuned[lower_case(word1)]))
	{
		//NOTE: As long as tune_lastline is nonzero, everything will work.
		//It doesn't matter whether it's the channel name or the character,
		//except for the special case of Citizen, which has more spaces in
		//its continuation text - and which will always have citizen in
		//word1, never in word2. So unless the char name is "-{Citizen}-",
		//this will never be wrong.
		conn->tune_lastline=word1;
		return 1;
	}
	else m_delete(conn,"tune_lastline");
}

int process(string param,mapping(string:mixed) subw)
{
	if (param=="" || has_value(param," "))
	{
		if (sizeof(tuned)) say(subw,"%% The following persons are tuned: "+sort(indices(tuned))*", ");
		say(subw,"%% To tune someone out: /tune name");
		say(subw,"%% Repeat to tune them back in.");
		//say(subw,"%% Stats are kept since the last tuning out."); //TODO: Implement. (Maybe.)
	}
	else
	{
		param=lower_case(param);
		if (tuned[param]) 
		{
			m_delete(tuned,param);
			say(subw,"%% Tuning back in.");
		}
		else 
		{
			say(subw,"%% Tuning out.");
			tuned[param] = ([]);
		}
		persist["tune/thresholdrpg"]=tuned;
	}
	return 1;
}

//Plugin menu takes us straight into the config dlg
constant menu_label="Tune people out";
class menu_clicked
{

	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Tune Threshold RPG characters","modal":1]);
	constant persist_key="tune/thresholdrpg";
	void create() {::create("Tune");}

	GTK2.Widget make_content() 
	{
		return two_column(({
			"Character",win->kwd=GTK2.Entry(),
			"Tune out one or more characters\non Threshold RPG OOC channels.\nEveryone listed here will be muted.",0,
		}));
	}
}

void create(string name) {::create(name);}
