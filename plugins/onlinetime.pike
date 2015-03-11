constant docstring=#"
Track your online time for statistical purposes.
";

inherit tabstatus;

GTK2.Widget maketabstatus(mapping(string:mixed) subw)
{
	mapping statustxt=subw->onlinetime=([]);
	return GTK2.Vbox(0,2)
		->add(statustxt->day=GTK2.Label())
		->add(statustxt->week=GTK2.Label())
		->add(statustxt->year=GTK2.Label())
	;
}

void connected(mapping(string:mixed) subw,string world)
{
	subw->onlinetime->day->set_text(world||"(d/c)");
}
