inherit hook;

constant docstring=#"
Various functions to make IRC connections easier.

Will generally apply only to port 6667 connections.

TODO: Mark connection types more reliably.
";

int output(mapping(string:mixed) subw,string line)
{
	if (!has_suffix(subw->connection->sock->query_address() || "", " 6667")) return 0;
	if (sscanf(line, "PING :%s", string pingpong))
	{
		send(subw, "PONG :"+pingpong+"\r\n");
		return 1;
	}
	if (sscanf(line, ":%s!%s@%s.%s JOIN #%s", string n1, string n2, string n3, string domain, string chan) && chan) return 1;
	if (sscanf(line, ":%s!%s@%s.%s PART #%s", string n1, string n2, string n3, string domain, string chan) && chan) return 1;
}
