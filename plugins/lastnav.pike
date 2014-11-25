constant docstring=#"
Extremely simple and rudimentary command to show the numpad nav cache
See window.pike for what this is actually accomplishing :)

TODO: Make this more discoverable somehow. It doesn't want to be on the
status bar, nor does it need a menu item. Would it be good to have this
in a window?? Probably a bit costly in real-estate.
";
inherit command;

constant plugin_active_by_default = 1;

int process(string param,mapping(string:mixed) subw)
{
	if (subw->lastnav_desc) say(subw,"%% You travelled: "+subw->lastnav_desc);
	if (subw->lastnav) say(subw,"%% You just travelled: "+subw->lastnav*", ");
	if (!subw->lastnav && !subw->lastnav_desc) say(subw,"%% You haven't numpad travelled recently.");
	return 1;
}
