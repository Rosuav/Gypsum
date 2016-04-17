/* Stub for notes.

Pop up a window to explore global state. Start with G or G->G, and drill down as far as you want.

GTK2.TreeView, add subentries for key in indices(cur). If it's a mapping/array, let it be plussed out.
Preferably, don't actually load up the next level until it's needed.

Simple types other than mappings and arrays can be rendered simply. (Maybe %O, maybe not.)
Objects... ??? TODO.

Will probably use test-expand-row signal.
*/
