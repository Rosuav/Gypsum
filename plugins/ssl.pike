inherit command;

constant docstring=#"
Enable SSL on the current connection.

Intended to be used after a protocol-level STARTTLS negotiation has succeeded.
";

int process(string param, mapping(string:mixed) subw)
{
	#if constant(SSL.File)
	if (!subw->connection || !subw->connection->sock)
	{
		say(subw, "%% Not connected");
		return 1;
	}
	SSL.File ssl = SSL.File(subw->connection->sock, SSL.Context());
	ssl->set_id(subw->connection);
	ssl->set_nonblocking(G->G->connection->sockread, G->G->connection->sockwrite, G->G->connection->sockclosed);
	ssl->connect();
	subw->connection->sock = ssl;
	#else
	say(subw, "%% SSL not available");
	#endif
	return 1;
}
