void create(string n,string which)
{
	array(string) arr=indices(this);
	if (which && which!="") arr=which/" ";
	foreach (arr,string f) if (f!="create") add_constant(f,this[f]);
}

//Usage: Instead of G->G->asdf->qwer(), use bouncer("asdf","qwer") and it'll late-bind.
class bouncer(string ... keys)
{
	mixed `()(mixed ... args)
	{
		mixed func=G->G; foreach (keys,string k) func=func[k];
		return func(@args);
	}
}

//Usage: gtksignal(some_object,"some_signal",handler,arg,arg,arg) --> save that object.
//Equivalent to some_object->signal_connect("some_signal",handler,arg,arg,arg)
//When it expires, the signal is removed. obj should be a GTK2.G.Object or similar.
class gtksignal(object obj)
{
	int signal_id;
	void create(mixed ... args) {signal_id=obj->signal_connect(@args);}
	void destroy() {obj->signal_disconnect(signal_id);}
}
