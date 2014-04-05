inherit plugin_menu;

/* Magic: "Active-by-default" plugins

When this starts up, if there's no persist list, it compiles every plugin in
plugins-more to see if it has a constant 'plugin_active_by_default'. If it does,
it creates an entry with active=1; if not, it creates an entry with active=0.

Don't apply plugin_active_by_default to anything where there's really no downside to
having it active. Keep 'em in the main section. Use this only for plugins where it's
normal to have it, but might be logical to remove it - like statusbar entries, which
have to compete for space.

Note that the discovery does involve compiling, though not instantiating, each
plugin (once). This is unavoidable without switching to a separate parse step.
(Although it could be solved by hash-iffing stuff, maybe. Tell it that it's being
compiled-only.)

Idea: Move this functionality into window.pike, have the initial detection done in
gypsum.pike (instead of bootstrap_all("plugins")), and push plugins-more and plugins
back together. That'd also remove the oddity that most plugin loads get reported to
the console, but -more plugins get echoed to... whichever subw is active at the time.
This would also mean that the "active_by_default" feature is no longer magic, but a
documented part of the plugin protocol.

Putting everything into trunk will mean that a persist key of plugins/more/list will
be inappropriate, but it can stay around as legacy as there's no real reason to be
changing it. It'd have to query both, as anyone who upgrades would be highly surprised
to find the set of active plugins suddenly changing.

Policy note on core plugins (this belongs somewhere, but I don't know where): Unlike
RosMud, where plugins were the bit you could reload separately and the core required
a shutdown, there's no difference here between window.pike and plugins/timer.pike.
The choice of whether to make something core or plugin should now be made on the basis
of two factors. Firstly, anything that should be removable MUST be a plugin; core code
is always active. That means that anything that creates a window, statusbar entry, or
other invasive or space-limited GUI content, should be a plugin. And secondly, the
convenience of the code. If it makes good sense to have something create a command of
its own name, for instance, it's easier to make it a plugin; but if something needs
to be called on elsewhere, it's better to make it part of core (maybe globals). The
current use of plugins/update.pike by other modules is an unnecessary dependency; it
may still be convenient to have /update handled by that file, but the code that's
called on elsewhere should be broken out into core.
*/

//Prune the list of plugins to only what can be statted, and add any from plugins-more
void prune()
{
	mapping(string:mapping(string:mixed)) items=persist->setdefault("plugins/more/list",([]));
	foreach (items;string fn;mapping plg) if (!file_stat(fn)) m_delete(items,fn);
	foreach (get_dir("plugins-more"),string fn) if (has_suffix(fn,".pike") && !items["plugins-more/"+fn])
	{
		//Try to compile the plugin. If that succeeds, look for a constant plugin_active_by_default;
		//if it's found, that's the default active state. (Normally, if it's present, it'll be 1.)
		program compiled; catch {compiled=compile_file("plugins-more/"+fn);};
		items["plugins-more/"+fn]=(["active":compiled && compiled->plugin_active_by_default]);
	}
	persist->save(); //Autosave (even if nothing's changed, currently)
}

constant menu_label="More plugins";
class menu_clicked
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title":"Load more plugins"]);
	constant allow_rename=0;
	constant persist_key="plugins/more/list";
	//NOTE: Cannot use simple bindings as it needs to know the previous state
	//Note also: This does not unload plugins on deactivation. Maybe it should?

	void create()
	{
		prune();
		::create("plugins/moreplugins");
	}

	GTK2.Widget make_content()
	{
		return GTK2.Vbox(0,10) //Note that the "useless" Vbox here means that two_column doesn't expand to fill the height, which looks tidier.
			->pack_start(two_column(({
				"Filename",win->kwd=GTK2.Entry(),
				"",win->active=GTK2.CheckButton("Active"),
				"NOTE: Deactivating a plugin will not unload it.\nUse the /unload command or restart Gypsum.",0,
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
	}
}

void load_all()
{
	if (!G->G->commands->update) {call_out(load_all,0); return;} //Can't load other plugins without the /update command
	function build=function_object(G->G->commands->update)->build;
	foreach (sort(indices(persist["plugins/more/list"])),string fn)
		if (persist["plugins/more/list"][fn]->active) build(fn);
}

void create(string name)
{
	::create(name);
	prune();
	load_all();
}
