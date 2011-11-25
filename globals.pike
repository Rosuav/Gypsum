void create(string n,string which)
{
    array(string) arr=indices(this);
    if (which && which!="") arr=which/" ";
    foreach (arr,string f) if (f!="create") add_constant(f,this[f]);
}

