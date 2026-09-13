(* Base64, because an SVG that embeds a raster frame has to carry the PNG as a
   data URI and there is no encoder in the standard library.

   Written here for the same reason the deflate writer is: this project's PNG
   surface is its own, and a dependency for twenty lines of table lookup would
   be a dependency in the js_of_ocaml bundle too. RFC 4648, standard alphabet,
   padded. *)

let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let encode (s : string) : string =
  let n = String.length s in
  let b = Buffer.create (((n + 2) / 3 * 4) + 8) in
  let byte i = if i < n then Char.code s.[i] else 0 in
  let i = ref 0 in
  while !i < n do
    let x = (byte !i lsl 16) lor (byte (!i + 1) lsl 8) lor byte (!i + 2) in
    Buffer.add_char b alphabet.[(x lsr 18) land 63];
    Buffer.add_char b alphabet.[(x lsr 12) land 63];
    (* The tail is padded rather than truncated: a decoder is entitled to the
       length, and a data URI that loses it renders as nothing. *)
    Buffer.add_char b (if !i + 1 < n then alphabet.[(x lsr 6) land 63] else '=');
    Buffer.add_char b (if !i + 2 < n then alphabet.[x land 63] else '=');
    i := !i + 3
  done;
  Buffer.contents b
