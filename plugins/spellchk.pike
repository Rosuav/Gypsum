constant docstring=#"
  - Suggestion: Have a way to call up spell-check without wiping the current command.
  - Can we do \"spell-check word under cursor\" as a single keystroke, and maybe \"spell-check current command\" too?
  - Use http://aspell.net/win32/ on Windows
";
//({"aspell","--encoding=utf-8","pipe"}),(["stdin":string_to_utf8("words to check")])
//Skip the first line and any that are just asterisks, output any others.
