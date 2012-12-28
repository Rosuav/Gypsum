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

object persist=class(string savefn)
{
	//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
	//It's also undying storage. When it dies, bring it back one way or the other. :)
	/* Usage:
	 * persist["some/string/identifier"]=any_value;
	 * retrieved_value=persist["some/string/identifier"];
	 * old_value=m_delete(persist,"some/string/identifier");
	 * Saves to disk on every change. Loads from disk only on initialization - /update this file to reload.
	 **/

	mapping(string:mixed) data=([]);

	void create()
	{
		catch //Ignore any errors, just have no saved data.
		{
			Stdio.File f=Stdio.File(savefn);
			if (!f) return;
			string raw=f->read();
			if (!raw) return;
			mixed decode=decode_value(raw);
			if (mappingp(decode)) data=decode;
		};
		//NOTE: Does not call ::create(name) as it has no inherits.
	}

	mixed `[](string idx) {return data[idx];}
	mixed `[]=(string idx,mixed val)
	{
		data[idx]=val;
		Stdio.File(savefn,"wct")->write(encode_value(data));
		return val;
	}
	mixed _m_delete(string idx)
	{
		mixed val=m_delete(data,idx);
		Stdio.File(savefn,"wct")->write(encode_value(data));
		return val;
	}
}(".gypsumrc"); //Save file name. TODO: Make this configurable somewhere.
