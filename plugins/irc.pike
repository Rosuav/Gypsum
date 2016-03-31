inherit hook;

constant docstring=#"
Various functions to make IRC connections easier.

TODO: Apply these only to a specially-marked world.
";

int output(mapping(string:mixed) subw,string line)
{
	if (sscanf(line, "PING :%s", string pingpong))
	{
		send(subw, "PONG :"+pingpong+"\r\n");
		return 1;
	}
}
