(* The n88basic command-line runner. It performs the interpreter's I/O so that
   basic/ itself never has to: reads the file, feeds stdin to INPUT, writes
   PRINT output to stdout, and turns N88basic.Error.t into an exit code. When
   the program draws anything, it also rasterises the display list (raster/,
   itself pure) and is the one place that writes the resulting PNG to disk,
   beside the source file. *)

(* A directory opens and reports a length perfectly happily; it is the read
   that fails, with whatever errno the filesystem chooses -- "Invalid
   argument" here, "Value too large for defined data type" for the one the
   kernel reports a huge size for. Neither names the path, and neither is
   stable enough to pin in a test, so the case is refused up front with the
   same shape as the missing-file message. Sys.is_directory raises for a
   path that does not exist at all, which is exactly the message that case
   already printed. *)
let read_file (path : string) : string =
  if Sys.is_directory path then raise (Sys_error (path ^ ": Is a directory"));
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let stdin_line () : string option =
  match input_line stdin with line -> Some line | exception End_of_file -> None

(* Beside [path]: "demo.bas" draws into "demo.png". A path with no
   extension at all just grows a ".png". *)
let png_path_for (path : string) : string =
  Filename.remove_extension path ^ ".png"

(* This was the one file operation the runner did not guard. Every other
   path here reports on stderr and picks an exit code deliberately; a
   Sys_error raised while writing the PNG -- the target taken by a
   directory, a read-only tree, a full disk -- escaped instead as an
   uncaught exception, printing "Fatal error: exception Sys_error(...)".
   The program's own output has already been written and is correct; what
   failed is the drawing, so say so and exit 2 with the other file errors
   rather than let a crash stand in for a diagnostic. *)
let write_png (path : string) (ops : N88basic.Display.op list) : unit =
  let png_path = png_path_for path in
  match
    let framebuffer = Raster.Rasterize.to_framebuffer ops in
    let bytes = Raster.Png.encode framebuffer in
    let oc = open_out_bin png_path in
    Fun.protect
      ~finally:(fun () -> close_out oc)
      (fun () -> output_string oc bytes)
  with
  | () -> Printf.eprintf "wrote %s\n%!" png_path
  | exception Sys_error message ->
      flush stdout;
      prerr_endline message;
      exit 2

(* Kept in step with the release tag. A consumer pinning byte-exact output
   needs something to pin against, and asking the binary is more reliable
   than inferring a version from the output itself. *)
let version = "0.1.0"

let usage =
  "usage: n88 FILE.bas\n\n\
  \  Runs an N88-BASIC(86) program. Output goes to stdout; a program that\n\
  \  draws also writes a PNG beside its source.\n\n\
  \  --version   print the version and exit\n\
  \  --help      print this message and exit\n"

let () =
  match Sys.argv with
  | [| _; ("--version" | "-version" | "-v") |] ->
      print_endline version;
      exit 0
  | [| _; ("--help" | "-help" | "-h") |] ->
      print_string usage;
      exit 0
  | [| _; path |] -> (
      match read_file path with
      | exception Sys_error message ->
          prerr_endline message;
          exit 2
      | source -> (
          let prog, errors = N88basic.Program.of_source source in
          match errors with
          | _ :: _ ->
              List.iter
                (fun e -> prerr_endline (N88basic.Error.to_string e))
                errors;
              exit 1
          | [] ->
              (* The interpreter never touches a pixel; it only appends to
                 this list (basic/interp.ml's on_draw). Collected in reverse
                 for O(1) appends, reversed once here rather than on every
                 op. *)
              let ops = ref [] in
              let on_draw op = ops := op :: !ops in
              (* POINT(x,y) is the one place the interpreter reads drawing
                 state back rather than only recording it (basic/interp.ml's
                 on_point). basic/ never sees a Framebuffer or a Palette; this
                 is the boundary's other side, where both are available. It
                 answers by rasterising everything drawn so far — the exact
                 pure function raster/ already exposes for the whole
                 program — and reading the one pixel POINT asked about. That
                 recomputes the buffer on every POINT call rather than
                 keeping one incrementally, an accepted cost against a
                 listing's ordinary number of graphics operations, in
                 exchange for basic/ staying pixel-blind and raster/ staying
                 the only place that rasterises. *)
              let on_point (x : float) (y : float) : int =
                let fb = Raster.Rasterize.to_framebuffer (List.rev !ops) in
                let xi = int_of_float (Float.round x)
                and yi = int_of_float (Float.round y) in
                if Raster.Framebuffer.in_bounds ~x:xi ~y:yi then
                  Raster.Framebuffer.get_pixel fb ~x:xi ~y:yi
                else -1
              in
              (* The same boundary as [on_point], asked the other way round:
                 PAINT needs to know whether its start point lands inside the
                 window, and a STEP start resolves against the last point
                 referenced, which only raster/ tracks. *)
              let on_in_window p = Raster.Rasterize.in_window (List.rev !ops) p in
              (* [1] POINT(<function>) reads the LP, which raster/ tracks for
                 the same reason it tracks pixels: six operations move it. *)
              let on_lp () = Raster.Rasterize.last_point (List.rev !ops) in
              let result =
                N88basic.Interp.run ~input:stdin_line ~write:print_string
                  ~on_draw ~on_point ~on_in_window ~on_lp prog
              in
              (* A program that drew nothing must behave exactly as it did
                 before graphics existed: no stray file, no extra output. *)
              if Raster.Rasterize.produces_a_picture (List.rev !ops) then
                write_png path (List.rev !ops);
              (match result with
              | Ok () -> exit 0
              | Error e ->
                  flush stdout;
                  prerr_endline (N88basic.Error.to_string e);
                  exit 1)))
  | _ ->
      prerr_string usage;
      exit 2
