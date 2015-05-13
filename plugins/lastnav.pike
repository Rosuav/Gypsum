constant docstring=#"
Extremely simple and rudimentary command to show the numpad nav cache
See window.pike for what this is actually accomplishing :)

TODO: Make this more discoverable somehow. It doesn't want to be on the
status bar, nor does it need a menu item. Would it be good to have this
in a window?? Probably a bit costly in real-estate.

Note that since this is looking at something maintained elsewhere, it'd
be perfectly reasonable to have an entirely different plugin that looks
at the same information (and could then have a window, or whatever). It
could even be possible to have quite a few ways of looking at the info,
with the user able to enable any or all as desired.
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
