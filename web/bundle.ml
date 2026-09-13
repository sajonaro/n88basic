(* The example programs, as a file the page can load.

   A browser cannot read the repository, so the examples travel with the page:
   this walks test/programs at build time and writes every .bas file into one
   JavaScript object, name to contents, which the console offers in a menu.
   Native, because it runs at build time and not in the browser.

   Sorted, so the file is the same file on every build. *)

let read path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* JSON string escaping, which is all the quoting this needs: the contents are
   BASIC source, so the cases that arise are quotes, backslashes and newlines,
   and anything below space is escaped rather than guessed at. *)
let quote s =
  let b = Buffer.create (String.length s + 16) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let () =
  let dir = Sys.argv.(1) in
  let names =
    Sys.readdir dir |> Array.to_list |> List.sort compare
    |> List.filter (fun n -> Filename.extension n = ".bas")
  in
  print_string "window.N88_EXAMPLES = {\n";
  List.iteri
    (fun i name ->
      if i > 0 then print_string ",\n";
      Printf.printf "  %s: %s" (quote (Filename.remove_extension name))
        (quote (read (Filename.concat dir name))))
    names;
  print_string "\n};\n"
