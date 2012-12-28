//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
//It's also undying storage. When it dies, bring it back one way or the other. :)
/* Usage:
 * persist["some/string/identifier"]=any_value;
 * retrieved_value=persist["some/string/identifier"];
 * old_value=m_delete(persist,"some/string/identifier");
 * Saves to disk on every change. Loads from disk only on initialization - /update this file to reload.
 **/


mapping(string:mixed) data=([]);
string savefn=".gypsumrc"; //TODO: Make this configurable somewhere.

void create(string name)
{
	add_constant("persist",this);
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
