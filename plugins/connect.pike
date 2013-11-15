inherit command;
inherit configdlg;

/**
 * List of worlds aviable by default.
 */
mapping(string:mapping(string:mixed)) worlds=persist["worlds"] || ([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG","descr":"Threshold RPG by Frogdice, a high-fantasy game with roleplaying required."]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall","descr":"A virtual gaming shop where players gather to play Dungeons & Dragons online."]),
]);

mapping(string:mapping(string:mixed)) items=worlds;
mapping(string:mixed) windowprops=(["title":"Connect to a world","modal":1,"no-show-all":1]);
string actionbtn="Save and C_onnect";

/**
 * Displays the connection window dialog or attempts a connection to a world.
 *
 * @param 	param The world to which to connect, or dlg option.
 * @return 	always returns 1
 */
int process(string param,mapping(string:mixed) subw)
{
	if (param=="dlg")
	{
		showwindow();
		return 1;
	}
	if (param=="" && !(param=G->G->window->recon(subw))) return listworlds("",subw);
	mapping info=worlds[param];
	if (!info)
	{
		if (sscanf(param,"%s%*[ :]%d",string host,int port) && port) info=(["host":host,"port":port,"name":sprintf("%s : %d",host,port)]);
		else {say("%% Connect to what?"); return 1;}
	}
	info->recon=param;
	G->G->window->connect(info,subw || G->G->window->subwindow("New tab"));
	return 1;
}

/**
 * 
 *
 */
int dc(string param,mapping(string:mixed) subw) {G->G->window->connect(0,subw); return 1;}

/**
 * List all the worlds in the global list to the provided sub window
 *
 * @param param Unused
 * @param subw	The window in which to print the world list.
 * @return 		always returns 1
 */
int listworlds(string param,mapping(string:mixed) subw)
{
	say("%% The following worlds are recognized:",subw);
	say(sprintf("%%%%   %-14s %-20s %-20s %4s","Keyword","Name","Host","Port"),subw);
	foreach (sort(indices(worlds)),string kwd)
	{
		mapping info=worlds[kwd];
		say(sprintf("%%%%   %-14s %-20s %-20s %4d",kwd,info->name,info->host,info->port),subw);
	}
	say("%% Connect to any of the above worlds with: /connect keyword",subw);
	say("%% Connect to any other MUD with: /connect host:port",subw);
	return 1;
}

//---------------- Config dialog ----------------
/**
 * Save the contents of the connect window to the info mapping
 *
 * @param info	The mapping to which to save the dialog info
 */
void save_content(mapping(string:mixed) info)
{
	info->name=win->name->get_text();
	info->host=win->hostname->get_text();
	info->port=(int)win->port->get_text();
	info->logfile=win->logfile->get_text();
	info->descr=get_text(win->descr);
	info->writeme=get_text(win->writeme);
	info->use_ka=win->use_ka->get_active();
	persist["worlds"]=worlds;
}

/**
 * Loads the contents of the of the info mapping to connect window, else loads empty values
 *
 * @param info	The mapping with which to load the dialog
 */
void load_content(mapping(string:mixed) info)
{
	win->name->set_text(info->name || "");
	win->hostname->set_text(info->host || "");
	win->port->set_text((string)(info->port||"23"));
	win->logfile->set_text(info->logfile || "");
	win->descr->get_buffer()->set_text(info->descr || "",-1);
	win->writeme->get_buffer()->set_text(info->writeme || "",-1);
	win->use_ka->set_active(info->use_ka || zero_type(info->use_ka));
}

/**
 * A callback that that handles the selection of a world for connection.
 *
 */
void action_callback()
{
	pb_save();
	string kwd=selecteditem();
	if (!kwd) return;
	mapping info=worlds[kwd];
	info->recon=kwd;
	G->G->window->connect(info,0);
	win->mainwindow->destroy();
}

/**
 * Creates the connect window
 *
 */
GTK2.Widget make_content()
{
	return GTK2.Vbox(0,10)
		->pack_start(GTK2.Table(6,2,0)
			->attach(GTK2.Label((["label":"Keyword","xalign":1.0])),0,1,0,1,GTK2.Fill,GTK2.Fill,5,0)
			->attach_defaults(win->kwd=GTK2.Entry(),1,2,0,1)
			->attach(GTK2.Label((["label":"Name","xalign":1.0])),0,1,1,2,GTK2.Fill,GTK2.Fill,5,0)
			->attach_defaults(win->name=GTK2.Entry(),1,2,1,2)
			->attach(GTK2.Label((["label":"Host name","xalign":1.0])),0,1,2,3,GTK2.Fill,GTK2.Fill,5,0)
			->attach_defaults(win->hostname=GTK2.Entry(),1,2,2,3)
			->attach(GTK2.Label((["label":"Port","xalign":1.0])),0,1,3,4,GTK2.Fill,GTK2.Fill,5,0)
			->attach_defaults(win->port=GTK2.Entry(),1,2,3,4)
			->attach(GTK2.Label((["label":"Auto-log","xalign":1.0])),0,1,4,5,GTK2.Fill,GTK2.Fill,5,0)
			->attach_defaults(win->logfile=GTK2.Entry(),1,2,4,5)
			->attach(win->use_ka=GTK2.CheckButton("Use keep-alive"),1,2,5,6,GTK2.Fill,GTK2.Fill,5,0) //No separate label
		,0,0,0)
		->pack_start(GTK2.Frame("Description")->add(
			win->descr=GTK2.TextView(GTK2.TextBuffer())->set_size_request(250,70)
		),1,1,0)
		->pack_start(GTK2.Frame("Text to output upon connect")->add(
			win->writeme=GTK2.TextView(GTK2.TextBuffer())->set_size_request(250,70)
		),1,1,0);
}

/**
 * Creates an instance of this class.
 *
 * @param name 	The name for the instance of this class
 */
void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
	G->G->commands->c=process;
	G->G->commands->worlds=listworlds;
}
