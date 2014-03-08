/* GTK updater for Windows

The current Pike installer for Windows installs 7.8.700 with GTK 2.12.11
We can instead run 2.24.10 by downloading a bunch of DLLs and plopping them
into the Pike binaries directory, over the top of the existing ones (backing
them up just in case).

As the GTK libraries are licensed in ways that demand source code distribution
(LGPL mainly; I haven't checked every single one of them), I carry the sources
on the same web site that the binaries are downloaded from. Both sources and
binaries were simply downloaded from gtk.org, though - I didn't actually build
anything.

Usage: /update gtk

It won't actually retain itself anywhere. I could make this 'inherit command',
but what's the point? The command '/update_gtk' is no better than '/update gtk'
and there's no need to keep it in memory :)
*/

/*
Code style oddity: Do not use any globals.pike features by name. Instead, use
G->globals->some_name, which avoids creating a useless lookup entry. It's not
particularly likely that someone will be bugged by this (all it means is that
updating GTK and then updating globals will re-update GTK), but simpler to do
the lookups in such a way as to not have the problem in the first place.

Never-updated globals like say() are safe, though - they can't be triggered.
*/

/*
Awkwardness: I can't actually be sure of having any sort of 'unzip' utility on
the user's computer. Most Windows systems do have some way to unzip files, but
not necessarily exposed as a program. So... fetch all the files individually.
*/

//The files we need to fetch, mapped to their SHA256 signatures
mapping(string:string) files=([
	"freetype6.dll":           "2f44cbfe8b02974e029fa4b97f4bc342553167d6f715be082f8f52ac604cbb66",
	"intl.dll":                "682d4277092472cac940558f9e679b44a6394159e49c9bbda299e33bfc6fdc92",
	"libatk-1.0-0.dll":        "d45ee3e6573c0c55db99ae66b641075ec1e0b64feb548786378dc79f63d69045",
	"libcairo-2.dll":          "d91d6b0577e0334aa63d9ab8a31edc16270d00f60c32eb7bcc50092d81cb6a21",
	"libgdk-win32-2.0-0.dll":  "84a8b0041d806dc92cdb19e6127e25fbdb8c3cc6a93cb014ea57351a22685b78",
	"libgdk_pixbuf-2.0-0.dll": "c8ff2373d4c261fcd6525a826dbc736d347ae10168490a7a7fc837e76329afc1",
	"libgio-2.0-0.dll":        "433d3c2f00fda700fc6353e1af600937a42407b6f2467aa41bd825e96a79c464",
	"libglib-2.0-0.dll":       "c0f35b0e5f9b25f36bf9ef885a8135e7dcdb77d425f8ac88124d90cf2bf32fde",
	"libgmodule-2.0-0.dll":    "1e2332ed84bb447fe814e9201effe88e682fd9b2da89e2b1a27aef1c786b6589",
	"libgobject-2.0-0.dll":    "75b4e8a0757f7db26ef195f3c5e2da5770d95c3af081c2cdae0ec15b460aa9ea",
	"libgthread-2.0-0.dll":    "ee2e8485fdbfb2c5626099ccafcdc41ac60414dffd5c6c3befaf786634baf5c3",
	"libgtk-win32-2.0-0.dll":  "f137f75e50c13fbd632814e8ab873b44c7b8b18e22d0d1501815a81e77bf992e",
	"libpango-1.0-0.dll":      "cbd61867459abd458b5de5b6f3213f864cb11db52986e39631a643da7c3844de",
	"libpangocairo-1.0-0.dll": "29e2828266d52c4be341e6212fa22bf54b509fb8e0c2057385667d6b5073c38e",
	"libpangoft2-1.0-0.dll":   "dc34dbce591fbb9b4dc287897c2eb67b735edd1dba63841a48b16ea477b9ec14",
	"libpangowin32-1.0-0.dll": "0a52dc82c58ee95b6d311f3936701593af2ef7055fb12eadaa489574f39a96e0",
	"libpng14-14.dll":         "7644c698cb5c823b9fd238d9e88b25d14e04816a0a2c77c48170309957c69efd",
	"zlib1.dll":               "104162a59e7784e1fe2ec0b7db8836e1eb905abfd1602a05d86debe930b40cbf",
]);

//Destination binary directory
string target=combine_path(@explode_path(Program.defined(object_program(GTK2)))[..<3],"bin");
int downloading,downloaded;

void switch_dirs()
{
	foreach (files;string fn;)
	{
		mv(target+"/"+fn,target+"/oldgtk/"+fn);
		mv("newgtk/"+fn,target+"/"+fn);
	}
	rm("newgtk");
	say(0,"%% GTK update complete. Restart Gypsum to use the new GTK!");
}

void data_available(object q,string fn)
{
	string data=q->data(); //Now shouldn't block
	if (mixed ex=catch {Stdio.write_file("newgtk/"+fn,data);})
	{
		say(0,"%% Unable to save "+fn);
		say(0,"%% "+describe_error(ex));
		return;
	}
	say(0,"%%%% Downloaded %d/%d: %s",++downloaded,downloading,fn);
	if (downloaded==downloading)
	{
		//Note that failed downloads don't increment the count. This
		//block should only happen when everything seems to have worked.
		say(0,"%% All files downloaded. Checking integrity...");
		foreach (files;string fn;string sig)
		{
			string data=Stdio.read_file("newgtk/"+fn);
			if (!data) {say(0,"%% File unreadable: "+fn); return;}
			if (String.string2hex(Crypto.SHA256.hash(data))!=sig)
			{
				say(0,"%% File damaged, removing: "+fn);
				rm("newgtk/"+fn);
				return;
			}
		}
		say(0,"%% Files downloaded correctly.");
		confirm(0,"All files downloaded successfully. Effect the change?",0,switch_dirs);
	}
}

void request_ok(object q,string fn) {q->async_fetch(data_available,fn);}
void request_fail(object q,string fn) {say(0,"%% Failed to download: "+fn);}

void update()
{
	//Ignore errors eg already existing
	catch {mkdir("newgtk");};
	catch {mkdir(target+"/oldgtk");};
	foreach (files;string fn;string sig)
	{
		if (file_stat("newgtk/"+fn))
		{
			string data=Stdio.read_file("newgtk/"+fn);
			if (data && String.string2hex(Crypto.SHA256.hash(data))==sig) continue; //File already downloaded.
			rm("newgtk/"+fn); //File unreadable or incorrect somehow. I don't care how; just wipe it and redownload.
		}
		++downloading;
		Protocols.HTTP.do_async_method("GET","http://rosuav.com/gtk/"+fn,0,0,
			Protocols.HTTP.Query()->set_callbacks(request_ok,request_fail,fn));
	}
	if (downloading) say(0,"%% Downloading "+downloading+" files...");
	else confirm(0,"All files already downloaded. Effect the change?",0,switch_dirs);
}

void create()
{
	say(0,#"%% GTK update from rosuav.com hosted DLLs
%% This downloads a number of DLL files from http://rosuav.com/gtk/
%% and attempts to install them into the appropriate place in your
%% Pike program tree. As these files are covered by the GNU LGPL,
%% source code is available, at the above URL; you do not need this
%% to run Pike or Gypsum, however.");
	if ((string)GTK2.version()=="\2\30\12")
	{
		G->globals->MessageBox(0,GTK2.MESSAGE_INFO,GTK2.BUTTONS_OK,"Already on GTK 2.24.10, nothing to do.",0);
		return;
	}
	G->globals->confirm(0,sprintf("Currently you're on %d.%d.%d, and in theory, 2.24.10 is available. Fetch it?",@GTK2.version()),0,update);
}
