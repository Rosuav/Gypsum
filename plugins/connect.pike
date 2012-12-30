inherit command;
inherit window;

mapping(string:mapping) worlds=persist["worlds"] || ([
	"threshold":(["host":"thresholdrpg.com","port":23,"name":"Threshold RPG","descr":"Threshold RPG by Frogdice, a high-fantasy game with roleplaying required."]),
	"minstrelhall":(["host":"gideon.rosuav.com","port":221,"name":"Minstrel Hall","descr":"A virtual gaming shop where players gather to play Dungeons & Dragons online."]),
]);

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

int dc(string param,mapping(string:mixed) subw) {G->G->window->connect(0,subw); return 1;}

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

//Return the keyword of the selected world, or 0 if none (or new) is selected
string selectedworld()
{
	[object iter,object store]=win->mudsel->get_selected();
	string kwd=iter && store->get_value(iter,0);
	return (kwd!="-- New --") && kwd; //TODO: Recognize the "New" entry by something other than its text
}

//Is there no simpler way to do this?
string get_text(GTK2.TextView mle)
{
	object buf=mle->get_buffer();
	return buf->get_text(buf->get_start_iter(),buf->get_end_iter(),0);
}

void pb_save()
{
	string oldkwd=selectedworld();
	string newkwd=win->kwd->get_text();
	if (newkwd=="") return; //TODO: Be a tad more courteous.
	mapping info=m_delete(worlds,oldkwd) || ([]);
	worlds[newkwd]=info;
	info->name=win->name->get_text();
	info->host=win->hostname->get_text();
	info->port=(int)win->port->get_text();
	info->descr=get_text(win->descr);
	info->writeme=get_text(win->writeme);
	persist["worlds"]=worlds;
	if (newkwd!=oldkwd)
	{
		[object iter,object store]=win->mudsel->get_selected();
		if (!oldkwd) win->mudsel->select_iter(iter=store->append());
		store->set_value(iter,0,newkwd);
	}
}

void pb_connect()
{
	pb_save();
	string kwd=selectedworld();
	if (!kwd) return;
	mapping info=worlds[kwd];
	info->recon=kwd;
	G->G->window->connect(info,0);
	win->mainwindow->hide();
}

void selchanged()
{
	string kwd=selectedworld();
	mapping info=worlds[kwd] || ([]);
	win->kwd->set_text(kwd || "");
	win->name->set_text(info->name || "");
	win->hostname->set_text(info->host || "");
	win->port->set_text((string)(info->port||"23"));
	win->descr->get_buffer()->set_text(info->descr || "",-1);
	win->writeme->get_buffer()->set_text(info->writeme || "",-1);
}

void makewindow()
{
	object ls=GTK2.ListStore(({"string"}));
	foreach (sort(indices(worlds)),string kwd) ls->set_value(ls->append(),0,kwd); //Is there no simpler way to pre-fill the liststore?
	ls->set_value(ls->append(),0,"-- New --");
	win->mainwindow=GTK2.Window((["title":"Configure worlds","transient-for":G->G->window->mainwindow,"modal":1,"no-show-all":1]))
		->add(GTK2.Vbox(0,10)
			->add(GTK2.Hbox(0,5)
				->add(win->mudlist=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
					->append_column(GTK2.TreeViewColumn("MUD name",GTK2.CellRendererText(),"text",0))
				)
				->add(GTK2.Vbox(0,10)
					->pack_start(GTK2.Table(4,2,0)
						->attach(GTK2.Label((["label":"Keyword","xalign":1.0])),0,1,0,1,GTK2.Fill,GTK2.Fill,5,0)
						->attach_defaults(win->kwd=GTK2.Entry(),1,2,0,1)
						->attach(GTK2.Label((["label":"Name","xalign":1.0])),0,1,1,2,GTK2.Fill,GTK2.Fill,5,0)
						->attach_defaults(win->name=GTK2.Entry(),1,2,1,2)
						->attach(GTK2.Label((["label":"Host name","xalign":1.0])),0,1,2,3,GTK2.Fill,GTK2.Fill,5,0)
						->attach_defaults(win->hostname=GTK2.Entry(),1,2,2,3)
						->attach(GTK2.Label((["label":"Port","xalign":1.0])),0,1,3,4,GTK2.Fill,GTK2.Fill,5,0)
						->attach_defaults(win->port=GTK2.Entry(),1,2,3,4)
					,0,0,0)
					->pack_start(GTK2.Frame("Description")->add(
						win->descr=GTK2.TextView(GTK2.TextBuffer())->set_size_request(250,70)
					),1,1,0)
					->pack_start(GTK2.Frame("Text to output upon connect")->add(
						win->writeme=GTK2.TextView(GTK2.TextBuffer())->set_size_request(250,70)
					),1,1,0)
				)
			)
			->pack_end(GTK2.Hbox(0,10)
				->add(win->pb_connect=GTK2.Button((["label":"Save and C_onnect","use-underline":1])))
				->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
				->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1])))
				->add(win->pb_close=GTK2.Button((["label":"_Close","use-underline":1])))
			,0,0,0)
		);
	win->mudsel=win->mudlist->get_selection();
}

void dosignals()
{
	win->signals=({
		gtksignal(win->pb_connect,"clicked",pb_connect),
		gtksignal(win->pb_save,"clicked",pb_save),
		gtksignal(win->pb_close,"clicked",win->mainwindow->hide),
		gtksignal(win->mudsel,"changed",selchanged),
	});
}

void create(string name)
{
	::create(name);
	G->G->commands->dc=dc;
	G->G->commands->c=process;
	G->G->commands->worlds=listworlds;
}
