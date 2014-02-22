inherit plugin_menu;

/* TODO: "Active-by-default" plugins

When this starts up, if there's no persist list, compile every plugin in plugins-more
and see if it has a constant plugin_active_by_default (don't actually instantiate,
just compile to program - a non-protected constant will be visible in the program).
If it does, create an entry with active=1; if not, create an entry with active=0.
In fact, this can be done on startup to look for any unrecognized ones, which would
allow new plugins to be loaded up by default.
*/

constant menu_label="More plugins";
class menu_clicked
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Load more plugins"]);
	constant allow_rename=0;

	void create()
	{
		items=persist["plugins/more/list"]||([]);
		foreach (get_dir("plugins-more"),string fn)
			if (has_suffix(fn,".pike") && !items["plugins-more/"+fn]) items["plugins-more/"+fn]=([]);
		foreach (items;string fn;mapping plg) if (!file_stat(fn)) m_delete(items,fn);
		::create("plugins/moreplugins");
		showwindow();
	}

	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10)
			->pack_start(two_column(({
				"Filename",win->kwd=GTK2.Entry(),
				"",win->active=GTK2.CheckButton("Active"),
			})),0,0,0);
	}

	void load_content(mapping(string:mixed) info)
	{
		win->active->set_active(info->active);
	}

	void save_content(mapping(string:mixed) info)
	{
		int nowactive=win->active->get_active();
		if (!info->active && nowactive) function_object(G->G->commands->update)->build(selecteditem());
		info->active=nowactive;
		persist["plugins/more/list"]=items;
	}

	void delete_content(string kwd,mapping(string:mixed) info)
	{
		persist["plugins/more/list"]=items;
	}
}

void load_all()
{
	if (!G->G->commands->update) {call_out(load_all,0); return;} //Can't load other plugins without the /update command
	function build=function_object(G->G->commands->update)->build;
	foreach (persist["plugins/more/list"]||([]);string fn;mapping plg)
		if (plg->active) build(fn);
}

void create(string name)
{
	::create(name);
	load_all();
}
