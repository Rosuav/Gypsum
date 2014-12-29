/* Failed attempt to make a miniature plugin-runner kernel.

Currently it's attuned specifically to zoneinfo, and may not even be all that
useful there. Probably not something worth using at all, but it's here as a
proof of concept. A more useful zoneinfo stand-alone would probably have to be
ported to Python anyway, as "get a Pike interpreter" isn't an easy prereq for
most people.

TODO: Neuter persist[] so it won't save to disk, for safety.
*/
mapping G=(["window":([])]);

int main()
{
	add_constant("add_gypsum_constant",add_constant);
	add_constant("G",this);
	GTK2.setup_gtk();
	object p=(object)"persist";
	object g=(object)"globals";
	add_constant("plugin_menu",class{});
	add_constant("statusevent",class{mapping statustxt=([]); void setstatus(string txt) {}});
	object o=((program)"plugins/zoneinfo")("plugins/zoneinfo.pike");
	o->menu_clicked()->win->mainwindow->signal_connect("destroy",lambda() {exit(0);});
	return -1;
}
