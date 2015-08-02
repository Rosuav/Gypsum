inherit command;

//I wonder... can this viably inherit connection.pike?????
//Hmm. Actually, it'd probably be better implemented with a gross hack in window.pike that replicates all say() output.

int process(string param,mapping(string:mixed) subw)
{
	if (param=="-" && m_delete(persist,"plugins/rc/password"))
	{
		say(subw,"%% Password unset. There is now no valid password for remote control.");
		return 1;
	}
	if (sizeof(param)<8)
	{
		say(subw,"%% This sets the remote-control password for your Gypsum.");
		say(subw,"%% Your password must be at least 8 characters long, and should");
		say(subw,"%% ideally be much longer.");
		catch
		{
			//On Unix systems, there's often a dictionary handy. Offer an XKCD 936 password example.
			//If there isn't (eg on Windows), just skip this bit.
			array words=Regexp.SimpleRegexp("^[a-z]+$")->match(Stdio.read_file("/usr/share/dict/words")/"\n");
			say(subw,"%%%% For example: /rc %s-%s-%s-%s",random(words),random(words),random(words),random(words));
		};
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
