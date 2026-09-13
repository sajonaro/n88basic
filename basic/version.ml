(* The version, in one place.

   It used to live in bin/main.ml, which was fine while the command line was
   the only host. The browser console is a third host and the extension
   compares its own version against the interpreter's, so a string copied per
   host is a string that goes stale per host.

   THERE WAS A SECOND ONE HERE AND IT HAD GONE STALE, which is the reason this
   comment is longer than the file. `Version.value` held "0.1.0" and was read
   by exactly one thing: a smoke test asserting it equalled "0.1.0". Nothing
   bumped it, because nothing else looked at it, so it still said 0.1.0 five
   releases later -- a constant checked against a copy of itself is not
   checked at all. This is the one the release bumps and every host reads. *)
let string = "0.2.0"
