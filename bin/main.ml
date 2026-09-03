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
(* "-" means the program arrives on stdin. Read in chunks rather than by
   length: in_channel_length needs a seekable channel, which is why passing
   /dev/stdin fails with "Illegal seek" rather than working by accident. *)
let read_all (ic : in_channel) : string =
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 65536 in
  let rec loop () =
    let n = input ic chunk 0 (Bytes.length chunk) in
    if n > 0 then begin
      Buffer.add_subbytes buf chunk 0 n;
      loop ()
    end
  in
  loop ();
  Buffer.contents buf

let read_file (path : string) : string =
  if path = "-" then read_all stdin
  else begin
    if Sys.is_directory path then raise (Sys_error (path ^ ": Is a directory"));
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic (in_channel_length ic))
  end

let stdin_line () : string option =
  match input_line stdin with line -> Some line | exception End_of_file -> None

(* Beside [path]: "demo.bas" draws into "demo.png". A path with no
   extension at all just grows a ".png".

   A program read from stdin has no source file to sit beside, so it draws
   into "n88.png" in the working directory. A caller running several should
   give each its own directory rather than expect distinct names -- an
   editor executing a buffer already has somewhere it wants the file. *)
let png_path_for (path : string) : string =
  if path = "-" then "n88.png" else Filename.remove_extension path ^ ".png"

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
let version = "0.2.0"

let usage =
  "usage: n88 FILE.bas\n\
  \       n88 -\n\n\
  \  Runs an N88-BASIC(86) program. Output goes to stdout; a program that\n\
  \  draws also writes a PNG beside its source.\n\n\
  \  \"-\" reads the program from stdin and draws into \"n88.png\" in the\n\
  \  working directory. The program has then consumed stdin, so INPUT and\n\
  \  LINE INPUT have nothing left to read and stop with \"Out of input\";\n\
  \  pass a file when a program asks for input.\n\n\
  \  --immediate, -i\n\
  \              the manual's direct mode (printed pp.4-6): statements are\n\
  \              read from stdin and executed as they arrive, and the\n\
  \              variables they set persist. A line typed with a number in\n\
  \              front is stored instead; RUN executes the stored lines, LIST\n\
  \              shows them, a bare line number deletes one, and NEW erases\n\
  \              the program. A session that draws writes \"n88.png\" when it\n\
  \              ends.\n\n\
  \  --uninstall remove this binary, and list what else came with n88\n\
  \              (add --yes to skip the confirmation)\n\
  \  --version   print the version and exit\n\
  \  --help      print this message and exit\n"


(* ---------------------------------------------------------------- immediate

   The manual's direct mode, printed pp.4-6 (ch1 SS3). The rules implemented
   here are all from those pages:

     - A command typed WITHOUT a line number executes on its own and is not
       stored in memory (p.5). BASIC then prints "Ok", which p.4 names as the
       prompt.
     - A command typed WITH a line number is stored in memory with its number
       and produces no output (p.5); the program runs in line-number order
       when RUN is typed.
     - Typing a line number ALONE deletes that line (p.6).
     - Typing an existing line number with new text replaces that line (p.6).
     - Memory holds one program at a time; NEW erases it (p.5).
     - Multi-statement (colon-separated) is allowed in direct mode (p.5).

   WHAT IS OURS, and named so it is not mistaken for the page. RUN, NEW and
   LIST are recognised HERE, at the prompt, rather than being statements the
   parser knows -- the interpreter has none of them, and pp.4-6 describe them
   as things typed at the prompt, so this is the smaller claim. Whether NEW
   also clears variables is not stated on those pages: it erases the program
   only, and CLEAR (printed p.46) is the statement the manual does define for
   clearing variables. Errors print their message and are followed by "Ok",
   the session continuing; the pages do not say, and stopping a session on a
   typo would make it useless. *)

let is_digit c = c >= '0' && c <= '9'

(* "10 PRINT 1" -> Some (10, "PRINT 1");  "10" -> Some (10, "") *)
let split_line_number (line : string) : (int * string) option =
  let n = String.length line in
  let i = ref 0 in
  while !i < n && is_digit line.[!i] do incr i done;
  if !i = 0 then None
  else
    match int_of_string_opt (String.sub line 0 !i) with
    | None -> None
    | Some num -> Some (num, String.trim (String.sub line !i (n - !i)))

let immediate () =
  let stored : (int, string) Hashtbl.t = Hashtbl.create 64 in
  let env = N88basic.Env.create () in
  let writer = N88basic.Print_format.make print_string in
  let ops = ref [] in
  let on_draw op = ops := op :: !ops in
  (* The same boundary the file path crosses, and for the same reason: basic/
     stays pixel-blind, so POINT is answered by rasterising the display list
     so far. *)
  let on_point (x : float) (y : float) : int =
    let fb = Raster.Rasterize.to_framebuffer (List.rev !ops) in
    let xi = int_of_float (Float.round x) and yi = int_of_float (Float.round y) in
    if Raster.Framebuffer.in_bounds ~x:xi ~y:yi then
      Raster.Framebuffer.get_pixel fb ~x:xi ~y:yi
    else -1
  in
  let on_in_window p = Raster.Rasterize.in_window (List.rev !ops) p in
  let listing () =
    Hashtbl.fold (fun k v acc -> (k, v) :: acc) stored []
    |> List.sort (fun (a, _) (b, _) -> compare a b)
  in
  let ok () = print_string "Ok\n"; flush stdout in
  let exec ?start_line (source : string) =
    let prog, errors = N88basic.Program.of_source source in
    match errors with
    | e :: _ -> prerr_endline (N88basic.Error.to_string e)
    | [] -> (
        match
          N88basic.Interp.run ~input:stdin_line ~on_draw ~on_point ~on_in_window
            ~env ~writer ?start_line ~write:print_string prog
        with
        | Ok () -> ()
        | Error e -> prerr_endline (N88basic.Error.to_string e))
  in
  ok ();
  let rec loop () =
    match stdin_line () with
    | None -> ()
    | Some raw ->
        let line = String.trim raw in
        (if line = "" then ()
         else
           match split_line_number line with
           | Some (num, "") -> Hashtbl.remove stored num
           | Some (num, text) -> Hashtbl.replace stored num text
           | None -> (
               match String.uppercase_ascii line with
               | cmd when cmd = "RUN" || String.length cmd > 4
                                         && String.sub cmd 0 4 = "RUN " ->
                   (* Printed p.138: "RUN は、プログラムの実行に先だち、変数を
                      すべて初期化し" -- RUN INITIALISES ALL VARIABLES before it
                      runs. It is not a way to enter the stored program with
                      the variables a direct statement has just set, which is
                      what this did before the page was read. Env.clear is the
                      same reset CLEAR performs (printed p.46). *)
                   let arg = String.trim (String.sub cmd 3 (String.length cmd - 3)) in
                   let start_line = int_of_string_opt arg in
                   let source =
                     listing ()
                     |> List.map (fun (n, t) -> string_of_int n ^ " " ^ t)
                     |> String.concat "\n"
                   in
                   if arg <> "" && start_line = None then
                     prerr_endline "RUN takes a line number"
                   else begin
                     N88basic.Env.clear env;
                     if source <> "" then exec ?start_line source
                   end;
                   ok ()
               | "NEW" ->
                   (* Printed p.106: NEW erases the program in memory AND
                      initialises every variable. pp.4-6 mention only the
                      erasing, and this cleared only the program until NEW's
                      own page was read. *)
                   Hashtbl.reset stored;
                   N88basic.Env.clear env;
                   ok ()
               | cmd when cmd = "LIST" || String.length cmd > 5
                                          && String.sub cmd 0 5 = "LIST " ->
                   (* Printed p.97 gives five forms, and the table there is
                      the whole rule: "start-end" lists that range, "start-"
                      lists from there up, "-end" lists from the lowest line
                      to there, "start" lists that one line, and no argument
                      lists everything. The page's "." (the interpreter's
                      current-line pointer) is NOT implemented: nothing here
                      tracks a current line. LLIST, which sends the same
                      listing to a printer, is out of scope with the rest of
                      printer handling. *)
                   let arg = String.trim (String.sub cmd 4 (String.length cmd - 4)) in
                   let bounds =
                     if arg = "" then Some (None, None)
                     else
                       match String.index_opt arg '-' with
                       | None -> (
                           match int_of_string_opt arg with
                           | Some n -> Some (Some n, Some n)
                           | None -> None)
                       | Some i ->
                           let lo = String.trim (String.sub arg 0 i)
                           and hi =
                             String.trim
                               (String.sub arg (i + 1) (String.length arg - i - 1))
                           in
                           let parse t =
                             if t = "" then Some None
                             else match int_of_string_opt t with
                               | Some n -> Some (Some n)
                               | None -> None
                           in
                           (match (parse lo, parse hi) with
                           | Some l, Some h -> Some (l, h)
                           | _ -> None)
                   in
                   (match bounds with
                   | None -> prerr_endline "LIST takes a line number or a range"
                   | Some (lo, hi) ->
                       List.iter
                         (fun (n, t) ->
                           let above = match lo with None -> true | Some l -> n >= l
                           and below = match hi with None -> true | Some h -> n <= h in
                           if above && below then Printf.printf "%d %s\n" n t)
                         (listing ()));
                   ok ()
               | _ ->
                   (* An immediate statement has to reach a parser that only
                      reads numbered lines, so it is wrapped in one. It cannot
                      collide with the stored program: exec builds a Program
                      from this text alone. The number must be legal --
                      PROG.LINE-NUMBERS is 1..65529 and 0 is refused -- and the
                      visible cost is that an error in a direct statement
                      reports "in line 1", where the machine would name no line
                      at all. Recorded rather than hidden. *)
                   exec ("1 " ^ line);
                   ok ()));
        flush stdout;
        loop ()
  in
  loop ();
  if !ops <> [] && Raster.Rasterize.produces_a_picture (List.rev !ops) then begin
    write_png "n88.png" (List.rev !ops);
    prerr_endline "wrote n88.png"
  end


(* ---------------------------------------------------------------- uninstall

   Removes the binary and REPORTS everything else, because the binary can
   honestly account for exactly one of the things a user ends up with. It did
   not install the editor extension, knows nothing about container images, and
   must not touch anyone's editor settings. An --uninstall that silently
   removed one of those and called itself done would leave an extension driving
   a missing interpreter, which is the confusing failure the version check
   exists to prevent.

   It refuses where it is not the owner. Inside an opam switch, rm corrupts
   opam's view of the world and `opam remove n88basic` is the right command.
   Inside the container, uninstalling is meaningless -- the image is the unit,
   and `docker rmi` is what removes it. The path is a good enough signal for
   both.

   Removing a running executable is fine on Linux: the inode survives until the
   process exits, so this can unlink itself and finish printing. *)

let contains (haystack : string) (needle : string) : bool =
  let n = String.length needle and h = String.length haystack in
  let rec go i = i + n <= h && (String.sub haystack i n = needle || go (i + 1)) in
  n = 0 || go 0

let the_rest =
  String.concat "\n"
    [ "";
      "n88 also usually comes with things this binary did not install:";
      "";
      "  the VSCode extension:";
      "    code --uninstall-extension n88basic.n88basic";
      "  any container images:";
      "    docker images --format '{{.Repository}}:{{.Tag}}' | grep n88basic";
      "    docker rmi <each one>";
      "  a \"remote.extensionKind\" override in VSCode settings.json, if you added";
      "  one as a workaround before v0.1.4 -- delete the \"n88basic.n88basic\" key.";
      "";
      "There is nothing else: n88 writes no config, cache or state directory.";
      "" ]

let uninstall ~(assume_yes : bool) : unit =
  let self = Sys.executable_name in
  if contains self "/_opam/" || contains self "/.opam/" then begin
    prerr_endline (self ^ " is inside an opam switch. Removing it would corrupt opam's view.");
    prerr_endline "Use:  opam remove n88basic";
    exit 1
  end;
  if Sys.file_exists "/.dockerenv" then begin
    prerr_endline "This is the container image; there is nothing to uninstall inside it.";
    prerr_endline "Remove the image instead:  docker rmi ghcr.io/sajonaro/n88basic";
    exit 1
  end;
  Printf.printf "Will remove: %s (%s)\n" self version;
  if not assume_yes then begin
    print_string "Proceed? [y/N] ";
    flush stdout;
    match String.lowercase_ascii (String.trim (try input_line stdin with End_of_file -> "")) with
    | "y" | "yes" -> ()
    | _ -> print_endline "Cancelled."; exit 1
  end;
  (match Sys.remove self with
  | () -> Printf.printf "Removed %s\n" self
  | exception Sys_error m ->
      prerr_endline ("Could not remove " ^ self ^ ": " ^ m);
      exit 1);
  print_string the_rest

let () =
  match Sys.argv with
  | [| _; ("--version" | "-version" | "-v") |] ->
      print_endline version;
      exit 0
  | [| _; ("--help" | "-help" | "-h") |] ->
      print_string usage;
      exit 0
  | [| _; ("--immediate" | "-i") |] ->
      immediate ();
      exit 0
  | [| _; "--uninstall" |] ->
      uninstall ~assume_yes:false;
      exit 0
  | [| _; "--uninstall"; ("--yes" | "-y") |] ->
      uninstall ~assume_yes:true;
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
