(* The conformance layer design §9 promises: a `.bas` program and its
   `.expected` output (or, for a drawing program, a `.digest` of its
   framebuffer), tagged with the clause identifiers it exercises.

   Tagging mechanism: a sidecar `<name>.clauses` file, one clause id per
   line (blank lines and "#"-led comments ignored). A `.bas` file with no
   such sidecar, or an empty one, is a hard failure here -- not a silent
   skip -- which is what makes it impossible to add a case without
   declaring what it covers. A sidecar rather than an in-source header
   comment: BASIC source is line-numbered, so a header would either burn a
   line number on metadata or need its own parsing convention layered onto
   REM; a sidecar keeps the `.bas` file exactly the program a user would
   type, and its presence is checked mechanically rather than by
   convention.

   Each case runs through N88basic.Interp directly (the same entry point
   test_interp.ml uses), not through a bin/main.exe subprocess: cheaper,
   and it is the interpreter's conformance being measured, not the CLI's
   (that boundary already has its own tests in test/cli/). A case whose
   program raises may still conform -- most of this project's error
   handling and the one documented divergence (NUM.DIV-BY-ZERO) are
   exactly that -- so the run's stdout and, on Error, the error's own
   [to_string] plus a trailing newline (the exact convention test/cli's
   runtime_error.out pins for the CLI) are concatenated into one string
   before comparison. *)

let conformance_dir = "conformance"

type case = {
  name : string;
  clauses : string list;
  bas : string;
  expected : string option;
  digest : string option;
  stdin_path : string option;
}

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))

let read_lines_nonblank (path : string) : string list =
  read_file path |> String.split_on_char '\n' |> List.map String.trim
  |> List.filter (fun l -> l <> "" && not (String.length l > 0 && l.[0] = '#'))

let at (dir : string) (name : string) : string = Filename.concat dir name
let exists_at (dir : string) (name : string) : bool = Sys.file_exists (at dir name)

(* Every `.bas` basename in [conformance_dir], each paired with its
   required `.clauses` sidecar and whichever of `.expected` / `.digest` /
   `.stdin` sit beside it. *)
let discover_cases () : case list =
  Sys.readdir conformance_dir |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".bas")
  |> List.sort compare
  |> List.map (fun bas_file ->
         let name = Filename.remove_extension bas_file in
         let clauses =
           if exists_at conformance_dir (name ^ ".clauses") then
             read_lines_nonblank (at conformance_dir (name ^ ".clauses"))
           else []
         in
         let expected =
           if exists_at conformance_dir (name ^ ".expected") then
             Some (read_file (at conformance_dir (name ^ ".expected")))
           else None
         in
         let digest =
           if exists_at conformance_dir (name ^ ".digest") then
             Some (String.trim (read_file (at conformance_dir (name ^ ".digest"))))
           else None
         in
         let stdin_path =
           if exists_at conformance_dir (name ^ ".stdin") then Some (at conformance_dir (name ^ ".stdin")) else None
         in
         { name; clauses; bas = at conformance_dir bas_file; expected; digest; stdin_path })

(* Answers INPUT/LINE INPUT from a case's `.stdin` sidecar, one line per
   call -- the same shape as test_interp.ml's private [answering] helper. *)
let input_from_lines (lines : string list) : unit -> string option =
  let remaining = ref lines in
  fun () ->
    match !remaining with
    | [] -> None
    | l :: rest ->
        remaining := rest;
        Some l

(* Runs [source] once and returns everything PRINT wrote, followed by the
   error's own text (plus a trailing newline, test/cli's own convention)
   if it raised, together with the display list drawn before either
   outcome -- a program is free to draw before it fails. *)
let run (source : string) (input : unit -> string option) : string * N88basic.Display.op list =
  let buf = Buffer.create 256 in
  let ops = ref [] in
  let on_draw op = ops := op :: !ops in
  let on_point x y =
    let fb = Raster.Rasterize.to_framebuffer (List.rev !ops) in
    let xi = int_of_float (Float.round x) and yi = int_of_float (Float.round y) in
    if Raster.Framebuffer.in_bounds ~x:xi ~y:yi then
      Raster.Framebuffer.get_pixel fb ~x:xi ~y:yi
    else -1
  in
  (* PAINT asks whether a start point lands inside the window, and the answer
     needs the last point referenced when a STEP start is used -- so the same
     display list is handed back to raster/, which is the only side that knows
     either. *)
  let on_in_window p = Raster.Rasterize.in_window (List.rev !ops) p in
  (* [1] POINT(<function>) reads the LP, which raster/ tracks -- wired for the
     same reason as the two handlers above, so a case can assert on it. *)
  let on_lp () = Raster.Rasterize.last_point (List.rev !ops) in
  let text =
    match
      N88basic.Interp.run_source ~input ~on_draw ~on_point ~on_in_window ~on_lp
        ~write:(Buffer.add_string buf) source
    with
    | Ok () -> Buffer.contents buf
    | Error e -> Buffer.contents buf ^ N88basic.Error.to_string e ^ "\n"
  in
  (text, List.rev !ops)

let framebuffer_digest (ops : N88basic.Display.op list) : string =
  let fb = Raster.Rasterize.to_framebuffer ops in
  (* Digest the RESOLVED picture, not the raw index bytes: the buffer holds
     palette numbers now, and what these cases pin is what the frame looks
     like. Digesting indices would also make a [2] COLOR that visibly
     recolours the screen leave the digest unchanged. *)
  Digest.to_hex (Digest.bytes (Raster.Framebuffer.to_rgb_bytes fb))

(* On a digest mismatch, write the frame that was actually produced next
   to the `.digest` file that expected something else, exactly as design
   §9 requires: "a hash mismatch alone tells you nothing about what
   moved." *)
let write_actual_png (case : case) (ops : N88basic.Display.op list) : string =
  let fb = Raster.Rasterize.to_framebuffer ops in
  let png = Raster.Png.encode fb in
  let path = at conformance_dir (case.name ^ ".actual.png") in
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc png);
  path

let run_case (case : case) () : unit =
  if case.clauses = [] then
    Alcotest.failf
      "%s: missing or empty %s.clauses -- every conformance case must declare which clause ids it exercises"
      case.name case.name;
  if case.expected = None && case.digest = None then
    Alcotest.failf "%s: neither %s.expected nor %s.digest is present -- a case must declare what it expects"
      case.name case.name case.name;
  let source = read_file case.bas in
  let input =
    match case.stdin_path with
    | Some p -> input_from_lines (String.split_on_char '\n' (read_file p))
    | None -> fun () -> None
  in
  let text, ops = run source input in
  Option.iter (fun expected -> Alcotest.(check string) (case.name ^ ": stdout") expected text) case.expected;
  Option.iter
    (fun expected_digest ->
      let actual_digest = framebuffer_digest ops in
      if actual_digest <> expected_digest then begin
        let png_path = write_actual_png case ops in
        Alcotest.failf "%s: framebuffer digest mismatch: expected %s, got %s -- actual frame written to %s"
          case.name expected_digest actual_digest png_path
      end)
    case.digest

let () =
  let cases = discover_cases () in
  if cases = [] then Alcotest.fail "no conformance cases found under test/conformance/";
  Alcotest.run "conformance"
    [ ("cases", List.map (fun c -> Alcotest.test_case c.name `Quick (run_case c)) cases) ]
