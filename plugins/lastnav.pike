inherit command;

int process(string param,mapping(string:mixed) subw)
{
	if (subw->lastnav_desc) say(subw,"%% You travelled: "+subw->lastnav_desc);
	if (subw->lastnav) say(subw,"%% You just travelled: "+subw->lastnav*", ");
	if (!subw->lastnav && !subw->lastnav_desc) say(subw,"%% You haven't numpad travelled recently.");
	return 1;
}
