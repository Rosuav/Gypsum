==============
Gypsum Plugins
==============

Scripts in this directory are automatically loaded on Gypsum startup.

As Gypsum is a free and open system, anything described in this document
can be overridden or augmented, so I'll just describe the defaults and
leave the rest to your imagination. Anything's possible.

Functionality stated here is a Gypsum promise, unless marked "advisory".
Upgrading Gypsum within the same major version should not violate any
promised behaviour, and any departure from these promises is a bug. More
promises can be added at any minor version, so backward compatibility is
guaranteed only as far as that minor version. Semantic Versioning v2.0.0
is applicable here - see http://semver.org/ for details.

Plugins are identified by their base names (without any path or the ".pike"
extension). Plugins are loaded in directory-walk order, but once
bootstrapping is complete, only the file name matters. Initialization
order can thus be modified by moving scripts into subdirectories. Note
that a plugin should not depend on any other plugin; initialization order
should not affect anything more significant than, say, the order of their
status bar entries.

A plugin MAY be loaded from somewhere other than Gypsum's 'plugins/'
directory, but this is not advisable and may cause issues with some minor
features (eg the insta-edit and insta-update features of the corresponding
plugins). Also, paths on Windows-like platforms MUST NOT contain drive letters;
this entirely precludes the loading of plugins from any drive other than the
one Gypsum is run from. The best place to develop your own plugin is in the
zz_local subdirectory, where it will never be overwritten by a future update,
even if the name conflicts with a newly-created standard plugin.


Plugin modes
============

A plugin may inherit any combination of the following, to gain access
to Gypsum facilities and to implement the hook's functionality. Also, a
plugin may define additional classes, inheriting from these, in order to
create temporary and discardable extensions; while it would be surprising
to craft a temporary slash command, it may well make very good sense to
have a temporary hook, and certainly a window can be either created on
demand or permanently active.

The demo plugin (demo.pike) lists as many plugin modes as practical. View its
source code (eg type '/edit demo') to see what can be done.

Command - 'inherit command'
---------------------------

Commands are invoked explicitly by the user typing "/foo", where foo is
the plugin's name. The plugin should define a function thus::

    int process(string param, mapping(string:mixed) subw)

The 'param' parameter is the parameters to the command. (Yo dawg?) It
may be "", but it will never be 0. The subw mapping identifies the
subwindow (aka tab) into which the command was typed; ideally (but not
mandatorially) this should be where messages are sent, etc.

If a command causes a command to be sent to the connection, it is
courteous to clear the prompt prior to returning::

    subw->prompt = ({([])});

This maintains the behaviour of normal command entry. Otherwise, the
prompt (if any) will be retained, which is normal behaviour for local
operations. Note though that this should be unusual; commands should
normally work locally, and input hooks (see below) should manipulate
text sent to the server. It's also (therefore) not fully supported, so
you're on your own here. Perhaps in the future there will be a formal
function for sending commands, which will deal with all this, but not
in current versions.

Hook - 'inherit hook'
---------------------

Hooks are notified of particular events in the Gypsum world. Any given hook
plugin can be notified of any or all of the following by defining functions
which will be called at the appropriate times. All these functions are given a
subw reference as their first parameter; additional parameters depend on the
specific hook. If a hook function returns 1, the event is deemed "consumed"; no
other hooks will be called, and (generally) the default behaviour will not be
performed.

- int input(mapping(string:mixed) subw, string line)

  An input hook looks very similar to a command processor, but take note of
  the following distinctions:

  * The intention is for a hook to manipulate text that would be sent to the
    server, but for a command to work locally.
  * Only one command processor is ever called for a given command - the
    one whose name matches the command entered. Every hook is called for
    every command.
  * A command processor will normally consume its command. A hook will
    normally permit it through unchanged.
  * Command processors handle slash commands (eg "/alias"). Hooks handle
    what would otherwise go to the MUD (those without slashes).
  * In "password mode" (where inputted text is hidden), hooks are not
    called. Commands still will be, though.
  * A command's "param" is what comes after the command name. A hook's
    "line" is the entire line.
  * In summary: A hook interacts with the stream of commands flowing from
    the human to the remote server, but a slash command is explicitly
    called upon by the human.

  An input hook can feed a replacement line of text into the system with::

	nexthook(subw, line);

  This can be either before or after returning 1 from the hook function.
  If nexthook is successful, it will return 1, so modifying user input
  can be done by simply::

	return nexthook(subw, modified_line);

  Returning from the hook function and subsequently calling nexthook
  will work so long as the subw still exists. (Note that nexthook will
  not call the current hook function, and thus cannot create an infinite
  loop.)

  ADVISORY: If this is called _and_ 0 is returned, both commands will be sent,
  but this is not the normal form of processing and is not formally supported nor
  recommended. Similarly if nexthook is called to synthesize an input command
  that wasn't in response to an inputhook call. The purpose of this is to modify,
  not create, input. This behaviour may change in the future.

- int output(mapping(string:mixed) subw, string line)

  An output hook is similar to an input hook, but works on a different type of
  line: a line of text from the server. Consuming the line means it will not be
  shown to the user.

- int prompt(mapping(string:mixed) subw, string prompt)

  A line of text is about to be treated as a prompt. With some servers, this may
  include useful information such as hitpoint status. Note that "consuming" a
  prompt pretends that the server did not send it - any previous prompt will be
  kept. There's currently no way to say "this isn't a prompt, keep it as text".

- int closetab(mapping(string:mixed) subw, int index)

  A tab (subwindow) is about to be closed. This is a good opportunity to dispose
  of any per-tab memory, break refloops, or do any other final cleanup. Return 1
  to prevent the tab from closing (use with caution). Note that this will not
  currently be called on application shutdown.

- int switchtabs(mapping(string:mixed) subw)

  The user has just selected a new tab. The subw mapping represents the _new_ tab
  (currently there is no notification of which tab was previously selected). This
  event cannot be 'consumed' (although returning 1 will still prevent other hooks
  from seeing it).

- DEPRECATED: Prior to 20150422, hook functions for input and output followed
  different signatures. The old signatures are still valid, but new code should
  not use them::

	int inputhook(string line, mapping(string:mixed) subw)
	int outputhook(string line, mapping(string:mixed) conn)

  Note that the outputhook receives a connection, *not* a subwindow. See below
  for details of the two separate mappings. Or just use output() instead :)

Window - 'inherit window'
-------------------------

Rather than manually creating a window, inherit window to ensure that
your subwindow is well-behaved. Provide the following function::

    void makewindow()

It will be called when your plugin is first loaded, and not called when it is
reloaded. Store all GTK object references etc inside win[]. The plugin's main
window should be stored in win->mainwindow; be sure to set a title, even if you
suppress its display (it'll be used as the window's human-readable identifier).
After creating the window, call ``::makewindow()`` in case further setup
needs to be done.

GTK signals can be connected in two ways. Where possible, use this shorthand::

	void sig_someobj_some_event() {...}

This covers the simple and common case where a function (or class, which would
be instantiated when the signal occurs - useful for buttons that open windows)
is to be called with no custom parameter or other configuration. The signal is
connected after the normal action; to connect before, instead, adorn the name::

	void sig_b4_someobj_some_event() {...}

Every time your plugin is (re)loaded, this function will be connected to the
"some_event" signal of win->someobj. (Note that the documentation may refer to
a signal as "some-event". This is equivalent - hyphens and underscores can be
used interchangeably.)

For the less common cases, eg providing callback arguments or detail strings,
override this function::

	void dosignals()
	{
		::dosignals();
		win->signals += ({
			gtksignal(win->someobj, "some_event", callback, "arg"),
			gtksignal(win->otherobj, "blah", b4_callback, "arg", UNDEFINED, 1),
			//... as many as needed
		});
	}

This can be used in conjunction with the shorthand, so only those signals which
need customization need be mentioned in dosignals().

Generic storage space is in mapping(string:mixed) win, which is
retained across reloads.

Normally, the window will be hidden from pagers and task bars (under window
manager control; Gypsum simply sets the appropriate hints). Disable this by
marking that your window is not a subwindow, preferably only for ephemeral
windows rather than windows which will stay around permanently::

	constant is_subwindow = 0;

Any time a user requests that your window be closed, closewindow() will be
called. Override this to alter what happens, eg to add a confirmation, or to
turn closing into hiding::

	int closewindow() {return hidewindow();}

Certain stock objects with obvious events can be created with simple
function calls. Use of these functions guarantees a consistent look, and
also automatically connects the appropriate signal handler. The following
stock objects are available, and more may be added in the future:

* stock_close() - a Close button, which will call closewindow().
* stock_menu_bar() - a menu bar, designed to be packed into the top of a Vbox,
  which will automatically seek out menu items based on constants.

Note that constructing more than one of a stock object on a given window is not
guaranteed to work, and may result in signals not being connected correctly.

In addition to the regular GTK2 objects, Gypsum provides a few of its own
widgets for use on windows and configdlgs. These are mostly thin wrappers
around existing widgets, designed to play more nicely with the rest of Gypsum.

* MultiLineEntryField - the classic MLE can be used in all the same ways that
  a single-line entry field can, but GTK2.TextView lacks crucial methods. This
  corrects that by adding set_text() and get_text().
* SelectBox - for drop-down lists of strings, and also has [gs]et_text()
* GTK2Table - table layout based on a 2D array of widgets and strings
* two_column - thin wrapper around GTK2Table for the most common use

More details about all can be found by exploring the source (globals.pike).


Movable window - 'inherit movablewindow'
----------------------------------------

The same as 'inherit window' in usage, but gives automatic saving
and loading of the window position. Provide one additional constant::

	constant pos_key = "plugins/plugin_name/winpos";

This will be used as the persist[] key in which the window position
is stored. Optionally also set::

	constant load_size = 1; //To resize on startup to the last saved size

Without this (or with load_size set to 0), only the position will be saved and
restored - good for windows where the size is set by the contained widgets.

Otherwise is identical to window above.

Configuration dialog - 'inherit configdlg'
------------------------------------------

A somewhat more-featured version of window, this will do nearly all of
the work of a config dialog - as long as your configuration fits in
the provided framework. (If it doesn't, just use window/movablewindow
and do everything directly.)

The most common usage requires only that you provide::

	//Set any window properties desired - see GTK docs for details
	mapping(string:mixed) windowprops = (["title":"Configure"]);
	constant persist_key = "pluginname/whatever"; //Set this to the persist[] key where your data is stored
	//Name all the fields that you care about, identifying them by type
	constant strings=({"key1","key2","key3"}); //One or more of these three
	constant ints=({"key4","key5","key6"});
	constant bools=({"key7","key8","key9"});
	constant labels=({"Keyword", "Key 1", "Key 2", "Key 3", "Key 4"}); //Labels for the above three, in order

You may also wish to include one or more of these::

	constant allow_new=0; //Remove the -- New -- entry to prevent the creation of new elements
	constant allow_delete=0; //Disable the Delete button (it'll always be visually present)
	constant allow_rename=0; //Prevent renamings

For more advanced usage, define these::

	//Explicitly set the items mapping - if non-null, persist_key is ignored.
	mapping(string:mapping(string:mixed)) items;
	//Create and return a widget (most likely a layout widget) representing all the custom content.
	GTK2.Widget make_content() { }
	//Custom save/load hooks. Can be used in conjunction with the strings/ints/bools bindings.
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword.
	constant descr_key="title"; //Set this to a key inside the info mapping to populate with descriptions.
	string selectme="keyword"; //Preselect this item. Otherwise, -- New -- is preselected, or the first.

The layout of your window is governed by the broad structure of a configdlg,
with a "content block" incorporated in the right hand panel. The simplest way
to generate a content block is to provide labels for your fields, which will
then be paired off with the most obvious GUI widget for each one - GTK2.Entry
for strings and ints (including the keyword, if allow_rename isn't zeroed),
GTK2.CheckButton for bools, and MultiLineEntryField for multi-line strings
(mark these by starting the label with "\n").

NOTE: An alternative (and far superior) system is in development. It is still
provisionary and may be subject to tweaks, although major changes are highly
unlikely. Search the source (mainly globals.pike) for 'elements'.

More advanced usage can incorporate all of the above, and then make small
tweaks to handle what doesn't work the easy way. It's code. Have at it!

When the info keys are human readable, no other description is needed. But if
they are not so, it may be helpful to provide a second column which adds some
human-readable descriptive text to the main list box. See its one and only
current use (as of 20141230) in window.pike, 'class keyboard', for usage.

Note that a configdlg will normally want to be a nested class, invoked when
needed, rather than being a top-level inherit. A configdlg does not "slide
forward" onto updated code as a window does, preferring instead to retain the
old bindings. Normal usage is to open them and close them again, but be aware
that old configdlgs CAN affect old code without updating new code. The normal
behaviour, with the persist key and/or items mapping, will be safe, as there'll
be only one mapping that every code file references; but if save_content needs
to trigger some sort of update, be sure to trigger this for all active code.

Status text - 'inherit statustext'
----------------------------------

Allows precisely one label (by default) to be displayed as part of the
main window's status text. No functions need be provided; simply call
setstatus(sbtext) any time you wish to change the currently-displayed
text. Order of elements on the status bar is by order loaded.

Instead of a single label, some other widget can be placed on the bar.
Be careful with this, though - avoid expanding the statusbar's height.
Override this::

	GTK2.Widget makestatus() {return statustxt->lbl=....;}

It must both set statustxt->lbl to something, and return something.
They need not necessarily be the same object (eg the returned label
might be wrapped inside something else for structure), but if not, the
return object must be a parent (direct or indirect) of statustxt->lbl.

The status text will have a tooltip, which by default is your plugin's
name. To change this to something more useful, put this in create()::

	statustxt->tooltip = "whatever text you want";

This must be done prior to calling ::create(), as there is currently no
way to alter the tooltip post-creation. (This may change in future.)

For more stable display, you may demand that the label never be reduced in
width. This is more ugly in some cases, but less ugly in others. Just add::

	constant fixedwidth = 1;

to your inherits, and all will be done for you.

Status text with eventbox - 'inherit statusevent'
-------------------------------------------------

Just like statustext, but creates an eventbox. Most of this is to be
considered ADVISORY as the details may change, but the intent is to
provide an easy way to respond to mouse clicks. The simplest form is
standardized: inherit this, don't override makestatus(), and implement
a statusbar_double_click function, which will be called when the user
double-clicks on your statusbar entry.

The event box itself is available as statustxt->evbox and can be, for
instance, recolored. Using this to provide a colored statustext should
be used sparingly, as color can become very distracting if overused,
but this can be an easy way to highlight an alert state.

Plugin menu item - 'inherit plugin_menu'
----------------------------------------

Creates an entry on the 'Plugins' pull-down menu. Provide some or all of::

	constant menu_label = 0; //(string) The initial label for your menu.
	constant menu_accel_key = 0; //(int) Accelerator key. Provide if you want an accelerator.
	constant menu_accel_mods = 0; //(int) Modifier keys, eg GTK2.GDK_CONTROL_MASK. Ignored if !menu_accel_key.
	constant menu_parent = "plugins"; //Which menu (file/options/plugins/help) this item belongs in - don't change without good reason
	void menu_clicked() { }

ADVISORY: Note that menu_clicked can be any callable, eg a class, not just
a function. Be careful with this, though, as it may receive some arguments
Works beautifully as long as this isn't a problem; a number of plugins do
this by having an explicit create() that doesn't pass args on to its inherits.

Uses for this include opening/showing a window or configdlg, giving
statistical information to the user, giving usage information about a
command... just about anything. It's more discoverable than a hook
feature, and less intrusive than a permanent window.

To change the menu item text at run time (or based on dynamic state), call
set_menu_text("new text"). This can be done at any time; check inside create()
after calling ::create() to rescan after an update.

BEST PRACTICE: Leave menu_parent unchanged, so the menu item is created under
the "Plugins" menu. This makes the plugin properly discoverable, unsurprising,
and conventional. The other menus are normally the core code's domain. In
unusual situations, it may make more sense to place a menu item under some
other menu, and thus this is made possible; but it should be rare.

BEST PRACTICE: Even if set_menu_text() will be called to set a dynamic label,
still provide a menu_label. It is used for introspection, and ideally should be
indicative of what the actual label is likely to be, perhaps with placeholders.

General notes
=============

Handlers should usually return 1 if processing is "complete" - if the
command or line has been consumed. For commands, this should be the
normal case, and suppresses the "Unknown command" message; for hooks,
this indicates that the line should be hidden, as though it never
happened. In cases where there is no meaningful alternate processing,
the return value is ignored, and the function can be declared void.

Local output can be produced on any subw::

	say(subw, "message");

A subw of 0 means "whichever is current" and is appropriate when no
subw reference is available. If additional arguments (after the message)
are present, the message will be passed through sprintf(). Multiple
lines of output can be produced; they will be processed separately.

There are other ways that a plugin can hook itself into the system, such as
OS-level signals (with the signal() command, and distinct from GTK signals),
but these are all unsupported. Not only are they potentially platform
specific (signals certainly are), but they will break the plugin unloading
system, which is admittedly fragile already. Use this sort of thing ONLY if
you are absolutely sure you know what you're doing.

Documentation (for Plugins|Configure) can be provided by a string constant::

	constant docstring = #"
	blah blah blah
	";

It will be rewrapped for display, so wrap it to whatever's convenient for the
source code. Two newlines form a paragraph; there's currently no way to make
preformatted text. There's no need to repeat the obvious; some information will
be added based on inherits and such.

If your plugin needs a lot of configuration, the best way is to craft your own
window and save into persist[]. But if all you need is one simple string, you
can tie in with the main plugin config dialog by creating two constants::

	constant config_persist_key = "pluginname/what_to_configure";
	constant config_description = "Human-readable descriptive text";

Explore other plugins for usage examples. Regardless of the style of config,
you must restrict persist usage to JSON-safe values: strings, integers,
floats, arrays of JSON-safe values, and mappings with string keys and JSON-safe
values.

ADVISORY: Commands can be synthesized directly to a subw::

	send(subw, line+"\r\n");

This is reaching into the internals, however, and is not supported. In future,
a fully-supported API may be provided; for now, this is available.

ADVISORY: Additional information may be stored in subw, or in subw->connection
if it should apply to the current connection only. This is not guaranteed,
however, as there is no protection against collisions; but if you make your key
begin with "plugins/pluginname/" (where pluginname is your plugin's name), this
will most likely be safe.

ADVISORY: Save a reference to subw for use in callbacks (or use a closure), but
be aware that the tab may have been closed before your callback occurs.

BEST PRACTICE: Provide a constructor, which chains through to all parents'.
If your plugin inherits only one mode (command, hook, window), a create()
function is optional, but for plugins using multiple, it is necessary.
Your create() function is called whenever the plugin is initially loaded
or updated; it must call ::create to ensure that its parents are called.
A minimal create function is::

	void create(string name) {::create(name);}

Having this for a single-mode plugin is not a problem, so simply placing it in
every plugin you create is safe. Note that additional initialization code in
create() is _not_ called when the plugin is probed, but _is_ called when it is
loaded/updated. Having code called during probing is NOT recommended, but can
be done by abusing static initializers if it's absolutely necessary (why it
would be, I have no idea, but other people are smarter than I).

A plugin will be loaded by default if it has this declaration at top-level::

	constant plugin_active_by_default = 1;

The plugin is probed for this by compiling it and examining its constants,
so it's possible for the value of the constant to be programmatically
chosen, eg based on the presence or absence of some lower-level module. If
the loading of the plugin could be problematic, guard the entire code thus::

	#if !constant(COMPILE_ONLY)
	... plugin code here ...
	#endif

Anything inside this check will not be processed during the probe phase.
(The normal create() call also doesn't happen during probing, so most
plugins need not go to this level of hassle.)

ADVISORY: Everything in globals.pike can be used simply by referencing
its name. Explore the file for what can be used; most of it is stable,
even if not explicitly part of this file's pledge. They're omitted for
brevity and to avoid duplicating documentation more than necessary. Other
files are similarly available, and are similarly stable, though less likely
to be of use to plugins.

BEST PRACTICE: If call_out is used to delay or repeat a function call (eg to
periodically update status text or other display), ensure that it will be
safe against updates and unloads by checking that the module is still loaded.

BEST PRACTICE: Every "string" inside Gypsum is (or ought to be) a string of
Unicode characters. If you need to work with bytes (maybe read from/written to
a file), don't call it "string", call it "bytes" (which is a global typedef for
string(0..255) or string(8bit)); that way, it's clear what's text and what's
binary data. In many cases, a string(7bit) or string(0..127) can be used as
either bytes or text (with an implicit ASCII encode/decode "step"); this is
also the case for any seven-bit string literals. For this purpose, the typedef
"ascii" can be used.

BEST PRACTICE: Plugin file names should restrict themselves to ASCII characters
for maximum cross-platform compatibility. File system encodings are a mess that
I'd really rather not have to dig into. Also, avoid using a leading dot;
currently, Gypsum does not acknowledge these specially, but in future, these
may become "undiscoverable" or in some way hidden.


The subwindow mapping
---------------------

Certain elements in subw and conn are guaranteed, and designed to be read by
plugins. In general, these are for you to read but not replace or mutate;
however, poking around in the source code will show a number of interesting
possibilities. Have fun. :) The following keys should always exist:

* subw->connection - referred to as conn, this mapping stores per-connection
  info. It will be replaced with a new mapping any time a new connection is
  attempted on this subw.

* conn->display - backref to subw, for convenience/certainty.

* subw->world - (usually) short identifier for the current or most-recent
  world. This may be numeric and may even have spaces in it, but it should be
  string-for-string identical every time the same world is connected to. This is
  the recommended way to distinguish worlds in a way that a human will expect.
  (It is the "Keyword" from the connection dialog.)

* conn->worldname - descriptive name for the current world (used as tab text,
  for instance). Should be used as a human-readable world description.
  (It is the "Name" from the connection dialog.)

* conn->sock - socket object, if connected. It's currently possible for there to
  be a subw->connection but for its sock to be 0/absent; this may change in the
  future, with the entire connection mapping being disposed of. You should never
  see a closed socket object here, although it's briefly possible. DO NOT send
  or receive data directly on the socket (Gypsum uses multiple levels of
  buffering), but it can be queried for IP addresses and other useful info. On
  Pikes which support it, socket attributes can be set/queried.

* conn->debug_textread, conn->debug_ansiread, conn->debug_sockread - debug mode
  flags. Each one enables display of incoming text at a different level. Great
  for figuring out exactly what's getting sent to you; otherwise, just a whole
  lot of noise. Changing these is perfectly safe (Gypsum itself will never set
  them, only read them).

* subw->conn_debug - debug mode enabler. If this is set when a connection is
  first established, all three of the above debug flags will be set on the new
  connection. This allows easy debugging of connection issues. As above, this
  is for you to set and Gypsum to read.

Poke around in the source code for useful comments about each of these members.
Note that the above names (subw, conn) are the conventional names in the core
as well as in all plugins, so a text search for them should bring up all usage.

Caution: Do not try to explore these by typing "/x subw" at the console! One of
the elements (subw->lines) is an array of all the lines of text in the window,
with each element represented by another array. This can easily add thousands
of lines of output to your display, and really isn't very useful :) Instead,
use "/x indices(subw)" to see the available keys. Similarly with conn - check
"/x indices(subw->connection)" rather than dumping the whole thing out.
