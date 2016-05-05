//By popular request: Triggers.
//At its core, a trigger is a request that, when something comes from the
//server, an action be performed. That action could be to play a sound,
//set or clear some internal state (messing with anything Gypsum itself
//cares about would be unsupported, of course), send a string back to the
//server, or anything else.

inherit hook;
inherit plugin_menu;

constant docstring=#"
Triggers let you perform some action whenever a specified message comes
from the server. The action can be incredibly flexible.
";

//Leaving room for a future triggers/worldname
mapping(string:mapping(string:mixed)) triggers = persist->setdefault("triggers/global", ([]));

int output(mapping(string:mixed) subw,string line)
{
	foreach (triggers;;mapping tr)
	{
		switch (tr->match)
		{
			case "Substring": if (!has_value(line, tr->text)) continue; break;
			case "Entire": if (line != tr->text) continue; break;
			case "Prefix": if (!has_prefix(line, tr->text)) continue; break;
			default: continue;
		}
		//If we get here, the trigger matches. Do the actions.
		if (tr->message != "") say(subw, "%% "+tr->message);
		if (tr->sound != "") Process.create_process(({"cvlc", tr->sound})); //Asynchronous
		if (tr->response != "") send(subw, tr->response+"\r\n"); //Not officially supported by core - may have to change later.
		if (tr->counter != "") G->G["counter_" + tr->counter]++; //On par with HQ9++, there's no way to actually do anything with this.
	}
}

constant menu_label = "Triggers";
class menu_clicked
{
	inherit configdlg;
	constant persist_key = "triggers/global";
	constant elements = ({
		"kwd:Name", "text:Trigger text",
		"@Match style", ({"Substring", "Entire", "Prefix"}), //And maybe regex and others, as needed
		"'Actions - leave blank if not applicable:",
		"sound:Play sound file",
		"message:Display message locally",
		"response:Send command to server",
		"counter:Increment counter [keyword]", //Experimental
		"'counter_status:",
	});

	void load_content(mapping(string:mixed) info)
	{
		if (!info->match || info->match == "") win->match->set_text("Substring");
		int val = G->G["counter_" + info->counter]; //Yes, even if it's 0 or "". They'll just be zero themselves.
		win->counter_status->set_text(val ? (string)val : "");
	}
}

void create(string name) {::create(name);}
