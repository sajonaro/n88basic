(* n88basic, in a browser.

   [bin/main.ml] is one host and this is the other. What it adds is not a
   second interpreter: the language, the display list and the rasteriser are
   the same two libraries the command line links, and everything
   platform-shaped is the handful of callbacks [Interp.run] already takes from
   whoever is hosting it. A browser hands it a buffer instead of stdout and a
   pre-typed string instead of a keyboard, and that is the entire difference.

   THE GRAPHICS COST NOTHING TO BRING, which is the part worth noticing.
   basic/ never touches a pixel -- it appends to a display list and hands it
   back -- and raster/ turns that list into PNG bytes as a pure function. So
   the page gets drawings for free: no canvas drawing code, no second
   renderer, and a picture that is byte-identical to the one the CLI writes to
   disk. The invariant that keeps basic/ free of I/O, which exists for the
   editor's checker, is what makes this possible at all.

   What crosses into JavaScript is one call: give it a program and the input
   the program should read, get back what it printed, what went wrong, and the
   PNG if it drew one. *)

open Js_of_ocaml

let str s = Js.Unsafe.inject (Js.string s)

(* The program's INPUT/LINE INPUT answers, pre-typed, one per line.
   A browser cannot block for a keystroke, and this is the same model the
   command line already has: stdin is a sequence supplied in advance, and
   running out of it is "Out of input" rather than a wait. *)
let reader_of (stdin : string) : unit -> string option =
  let lines = ref (if stdin = "" then [] else String.split_on_char '\n' stdin) in
  fun () ->
    match !lines with
    | [] -> None
    | line :: rest ->
        lines := rest;
        Some line

let run (source : Js.js_string Js.t) (stdin : Js.js_string Js.t) =
  let source = Js.to_string source and stdin = Js.to_string stdin in
  let out = Buffer.create 1024 in
  let ops = ref [] in
  let on_draw op = ops := op :: !ops in
  (* POINT reads the drawing back, so it needs the same boundary the CLI
     crosses: rasterise what has been drawn so far and look. basic/ stays
     pixel-blind here exactly as it does there. *)
  let on_point x y =
    let fb = Raster.Rasterize.to_framebuffer (List.rev !ops) in
    let xi = int_of_float (Float.round x) and yi = int_of_float (Float.round y) in
    if Raster.Framebuffer.in_bounds ~x:xi ~y:yi then
      Raster.Framebuffer.get_pixel fb ~x:xi ~y:yi
    else -1
  in
  let on_in_window p = Raster.Rasterize.in_window (List.rev !ops) p in
  (* [1] POINT(<function>) reads the last point referenced, which only raster/
     tracks. Omitting this handler does not fail loudly -- the default answers
     something, and only gfx_point_lp in the corpus notices. *)
  let on_lp () = Raster.Rasterize.last_point (List.rev !ops) in
  let error =
    match N88basic.Program.of_source source with
    | _, (e :: _) -> Some (N88basic.Error.to_string e)
    | prog, [] -> (
        match
          N88basic.Interp.run ~input:(reader_of stdin) ~on_draw ~on_point
            ~on_in_window ~on_lp ~write:(Buffer.add_string out) prog
        with
        | Ok () -> None
        | Error e -> Some (N88basic.Error.to_string e)
        (* A page that stops answering just reads as broken, so anything the
           interpreter does not model is reported rather than thrown. *)
        | exception e -> Some (Printexc.to_string e))
  in
  let drawn = List.rev !ops in
  let png =
    if Raster.Rasterize.produces_a_picture drawn then
      (* Handed over as a byte string -- one character per byte -- so the page
         can btoa() it into a data URL without a base64 encoder on this side.
         These are the same bytes bin/main.ml writes to a .png file. *)
      Some (Raster.Png.encode (Raster.Rasterize.to_framebuffer drawn))
    else None
  in
  (* SVG as well as PNG: the page prefers the vectors, which stay sharp at any
     zoom and weigh a fraction of the frame, and falls back to the raster when
     the drawing used PAINT or a tile. [kind] says which arrived. *)
  let svg, svg_kind =
    if Raster.Rasterize.produces_a_picture drawn then
      let text, kind = Raster.Svg.encode drawn in
      (Some text, match kind with Raster.Svg.Vector -> "vector" | Raster.Svg.Raster -> "raster")
    else (None, "")
  in
  Js.Unsafe.obj
    [| ("output", str (Buffer.contents out));
       ("svg", match svg with None -> Js.Unsafe.inject Js.null | Some s -> str s);
       ("svgKind", str svg_kind);
       ("error", match error with None -> Js.Unsafe.inject Js.null | Some e -> str e);
       ("png", match png with
               | None -> Js.Unsafe.inject Js.null
               | Some p -> Js.Unsafe.inject (Js.bytestring p)) |]

let () =
  Js.export "n88"
    (Js.Unsafe.obj
       [| ("version", str N88basic.Version.string);
          ("run", Js.Unsafe.inject (Js.wrap_callback run)) |])
