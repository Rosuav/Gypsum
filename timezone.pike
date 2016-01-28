/* Stand-alone driver for the timezone converter

Most of the 'guts' of the code is in plugins/zoneinfo.pike; some important code is
also in globals.pike.
*/
mapping G=(["window":([])]);

int main()
{
	add_constant("add_gypsum_constant",add_constant);
	add_constant("G",this);
	add_constant("MICROKERNEL",1);
	GTK2.setup_gtk();
	object p=(object)"persist";
	object g=(object)"globals";
	add_constant("plugin_menu",class{});
	add_constant("statusevent",class{mapping statustxt=([]); void setstatus(string txt) {}});
	object o=((program)"plugins/zoneinfo")("plugins/zoneinfo.pike");
	//TODO: Find some other way to detect "no more windows" so we don't need to inject a signal
	o->menu_clicked()->win->mainwindow->signal_connect("destroy",lambda() {exit(0);});
	return -1;
}
