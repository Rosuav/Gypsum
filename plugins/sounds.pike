inherit hook;
#if constant(SDL.Music) && !constant(COMPILE_ONLY)

//Has a fixed number of "streams", with any given trigger attached to one particular stream
//Whenever there's any trigger on a stream, that stream's entry is _replaced_ with the new one.
//So there'll never be more than one SDL.Music() per stream.
//Normal usage would be all on the default stream. But you can set up other streams, eg one for background sound that loops.
//NOTE: Halt all sounds with G->G->sounds_playing=([]);

//Options available:
//file: File name. If omitted, will cut off any other sound but not start another.
//loop: Number of times to loop; -1 for indefinite. Default: Play once.
//stream: Which stream to play on. May be an integer or a string. Default: the integer 0 (not the same as the string "0").
//noretrigger: If nonzero, this file will not be retriggered if it's already playing.
mapping(string:mapping) triggers=([]);

int outputhook(string line,mapping(string:mixed) conn)
{
	foreach (triggers;string text;mapping info) if (has_value(line,text)) catch
	{
		if ((int)info->noretrigger && G->G->sounds_playing[info->stream]
			&& G->G->sounds_playing[info->stream][0]==info->file
			&& G->G->sounds_playing[info->stream][1]->playing()
		) continue;
		G->G->sounds_playing[info->stream]=info->file!="-" && ({info->file,SDL.Music(info->file)->play((int)info->loop || 1)});
	};
}

void create(string name)
{
	catch //If errors, no triggers, no problem.
	{
		string curtrig;
		foreach (Stdio.read_file("sounds.ini")/"\n",string line)
		{
			if (line=="") continue;
			if (line[0]==':') {triggers[curtrig=line[1..]]=([]); continue;}
			else if (!curtrig) continue;
			if (!triggers[curtrig]->file) {triggers[curtrig]->file=line; continue;}
			sscanf(line,"%{%[^= ]=%[^ ]%*[ ]%}",array info);
			triggers[curtrig]+=((mapping)info)&(<"loop","stream","noretrigger">);
		}
	};
	foreach (indices(triggers),string trig) if (!triggers[trig]->file) m_delete(triggers,trig); //Malformed config file - no file name against a trigger. Drop those entries.
	if (!G->G->sounds_playing)
	{
		SDL.init(SDL.INIT_AUDIO); atexit(SDL.quit);
		SDL.open_audio(22050,SDL.AUDIO_S16SYS,2,1024);
		G->G->sounds_playing=([]);
	}
	else G->G->sounds_playing&=values(triggers)->stream; //Mute any streams that no longer exist
	::create(name);
}
#endif
