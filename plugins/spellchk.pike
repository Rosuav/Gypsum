constant docstring=#"
Interface to an external spelling checker.

While this does not currently give real-time spell-checking of your input, it
does allow you to request the checking of your current command. In many cases,
this will be all you need; for additional flexibility, consider opening up a
new subwindow just for spell-checking.

On Linux, install the GNU Aspell package from your repositories. On Windows,
install http://aspell.net/win32/ and ensure that it is in your PATH.
";
//({"aspell","--encoding=utf-8","pipe"}),(["stdin":string_to_utf8("words to check")])
//Skip the first line and any that are just asterisks, output any others.
//Can we do "spell-check word under cursor" as a single keystroke, and maybe "spell-check current command" too?
