inherit command;

constant docstring=#"
This was going to be a sort of remote-control facility for Gypsum.
You set it up, configure your password, and then can telnet back to
Gypsum in order to do things. This would allow you to 'portal' a
connection to another system (effectively proxying through your main
system), and would also allow simple slash commands to implement
boss-key and other features, which would then be accessible to other
applications. However, it has shown up a few glaring problems, which
are mentioned in source code comments; as such, this plugin is almost
completely useless, and is retained only for the interest of editors.
It does contain an industry best-practice password management system,
which may be of some value somewhere.

This exists for its source code - it has no practical use as-is.
Though I suppose you could use it as an XKCD 936 password generator,
on Unix-like systems only, and without the 'common words' rule.
";

//I wonder... can this viably inherit connection.pike?????
//Hmm. Actually, it'd probably be better implemented with a gross hack in window.pike that replicates all say() output.

//TODO: Make a password generation system that uses input and output stats to
//figure out what "common" words are. This would then work on all platforms.
//It could then be asked for a dictionary-only password, a received-only or
//sent-only password, or a filtered-common password, where the latter uses the
//frequency table from sent/received words, but filters down to those words
//which exist in the dictionary (thus eliminating misspellings, names, etc).

string generate_password()
{
	catch
	{
		//On Unix systems, there's often a dictionary handy.
		//If there isn't (eg on Windows), an error will be thrown and we'll return zero.
		array words=Regexp.SimpleRegexp("^[a-z]+$")->match(Stdio.read_file("/usr/share/dict/words")/"\n");
		return sprintf("%s-%s-%s-%s",random(words),random(words),random(words),random(words));
	};
	return 0; //Unable to generate a password.
}

int process(string param,mapping(string:mixed) subw)
{
	if (param=="-" && m_delete(persist,"plugins/rc/password")) //If there wasn't, just fall through to the help-text display.
	{
		say(subw,"%% Password unset. There is now no valid password for remote control.");
		return 1;
	}
	if (sizeof(param)<8)
	{
		say(subw,"%% This sets the remote-control password for your Gypsum.");
		say(subw,"%% Your password must be at least 8 characters long, and should");
		say(subw,"%% ideally be much longer.");
		string pw=generate_password();
		if (pw) say(subw,"%%%% For example: /rc %s",pw); //If we can't generate passwords, don't, it's no big deal.
		if (persist["plugins/rc/password"]) say(subw,"%% A password has been set; using this command will replace it.");
		return 1;
	}
	string salt=MIME.encode_base64(random_string(9));
	persist["plugins/rc/password"]=salt+" "+MIME.encode_base64(Crypto.SHA256.hash(salt+param));
	say(subw,"%% Password set. You may override it by resubmitting this command.");
	//To verify, split the persist value on the space, and compare against the same encrypted+encoded form:
	//[string salt,string hash]=persist["plugins/rc/password"]/" ";
	//if (hash==MIME.encode_base64(Crypto.SHA256.hash(salt+entered_password))) it_is_correct;
}
