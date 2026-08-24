(* PNG encoding: structural checks on the bytes raster/png.ml produces, and
   a round-trip through a decoder that is not our own code — PyMuPDF, run
   as an external process — because a PNG only our own encoder can read is
   not a PNG. *)

open Raster

(* A Python with PyMuPDF, used only to read back a PNG this project encoded.
   There is no OCaml-side PNG decoder here to check against, and a decoder of
   our own would share our own misconceptions -- the point is to be read by
   something that is not this code.

   Found from the environment rather than hardcoded: N88BASIC_PYTHON if set,
   otherwise whatever "python3" the PATH offers. The test skips when no such
   interpreter can import PyMuPDF, so a checkout without it still passes
   rather than failing for a missing optional tool. *)
let python = try Sys.getenv "N88BASIC_PYTHON" with Not_found -> "python3"

(* Whether [python] exists AND can import PyMuPDF. Testing the binary alone
   is not enough: python3 is present almost everywhere and PyMuPDF usually
   is not, and an earlier version of this test checked only for a file at a
   hardcoded path, so it skipped silently on every machine but one. *)
let decoder_available =
  lazy
    (Sys.command
       (Printf.sprintf "%s -c \"import pymupdf\" >/dev/null 2>&1" (Filename.quote python))
     = 0)

let sample_framebuffer () =
  Rasterize.to_framebuffer
    N88basic.Display.
      [
        Cls 3;
        Line
          {
            from_point = Some (Abs (10., 10.));
            to_point = Abs (300., 200.);
            colour = Some 7;
            box = `None;
            style = None;
            fill = None;
          };
        Line
          {
            from_point = Some (Abs (320., 40.));
            to_point = Abs (600., 360.);
            colour = Some 5;
            box = `Frame;
            style = None;
            fill = None;
          };
        Line
          {
            from_point = Some (Abs (100., 300.));
            to_point = Abs (200., 380.);
            colour = Some 3;
            box = `Filled;
            style = None;
            fill = None;
          };
      ]

let test_signature_and_chunk_types () =
  let png = Png.encode (sample_framebuffer ()) in
  Alcotest.(check string) "PNG signature" Png.signature
    (String.sub png 0 8);
  (* IHDR must be the very next chunk, per the PNG spec, with its declared
     length of 13 and the dimensions this task fixes. *)
  Alcotest.(check string) "IHDR chunk type" "IHDR" (String.sub png 12 4);
  let be32 s off =
    (Char.code s.[off] lsl 24)
    lor (Char.code s.[off + 1] lsl 16)
    lor (Char.code s.[off + 2] lsl 8)
    lor Char.code s.[off + 3]
  in
  Alcotest.(check int) "IHDR length" 13 (be32 png 8);
  Alcotest.(check int) "IHDR width" Framebuffer.width (be32 png 16);
  Alcotest.(check int) "IHDR height" Framebuffer.height (be32 png 20);
  (* The file ends with IEND, declared-length 0. *)
  let len = String.length png in
  Alcotest.(check string) "IEND chunk type" "IEND"
    (String.sub png (len - 8) 4)

let test_determinism () =
  let fb = sample_framebuffer () in
  let a = Png.encode fb in
  let b = Png.encode fb in
  Alcotest.(check bool) "identical PNG bytes on repeated encoding" true
    (String.equal a b)

let test_checksum_known_vectors () =
  (* The standard CRC-32 and Adler-32 check values for the ASCII string
     "123456789" — independent of anything in this codebase, so a broken
     table or a sign/byte-order slip is caught without needing a decoder. *)
  let data = Bytes.of_string "123456789" in
  Alcotest.(check int32) "crc32(\"123456789\")" 0xcbf43926l
    (Checksums.crc32 data);
  Alcotest.(check int32) "adler32(\"123456789\")" 0x091e01del
    (Checksums.adler32 data)

(* Write [png] to a fresh temp file and ask an external process — the
   PyMuPDF-backed Python from the scratchpad venv, not any code in this
   repository — to open it and print its pixel dimensions. *)
let external_decode_dimensions (png : string) : (int * int) option =
  let path = Filename.temp_file "raster_test" ".png" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      Fun.protect
        ~finally:(fun () -> close_out oc)
        (fun () -> output_string oc png);
      let out_path = Filename.temp_file "raster_test" ".out" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove out_path with Sys_error _ -> ())
        (fun () ->
          let cmd =
            Printf.sprintf
              "%s -c \"import pymupdf; d = pymupdf.open('%s'); p = d[0]; \
               print(int(p.rect.width), int(p.rect.height))\" > %s 2>&1"
              (Filename.quote python) path (Filename.quote out_path)
          in
          let status = Sys.command cmd in
          if status <> 0 then None
          else
            let ic = open_in out_path in
            let line = input_line ic in
            close_in ic;
            match String.split_on_char ' ' (String.trim line) with
            | [ w; h ] -> Some (int_of_string w, int_of_string h)
            | _ -> None))

let test_external_decoder_round_trip () =
  if not (Lazy.force decoder_available) then Alcotest.skip ()
  else
    let png = Png.encode (sample_framebuffer ()) in
    match external_decode_dimensions png with
    | None ->
        Alcotest.fail
          "external decoder (PyMuPDF) failed to open the encoded PNG"
    | Some (w, h) ->
        Alcotest.(check int) "decoded width" Framebuffer.width w;
        Alcotest.(check int) "decoded height" Framebuffer.height h

let () =
  Alcotest.run "raster png"
    [
      ( "structure",
        [
          Alcotest.test_case "signature and chunk types" `Quick
            test_signature_and_chunk_types;
          Alcotest.test_case "determinism" `Quick test_determinism;
          Alcotest.test_case "checksum known vectors" `Quick
            test_checksum_known_vectors;
        ] );
      ( "external decoder",
        [
          Alcotest.test_case "round-trips through PyMuPDF" `Quick
            test_external_decoder_round_trip;
        ] );
    ]
