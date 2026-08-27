(* Writes deflate samples for tools/check_deflate.py to inflate.

   raster/Zlib has no decompressor and should not grow one: nothing in this
   project reads a PNG. So the round-trip is closed from outside, against
   Python's zlib, which is a real RFC 1951 inflater and not one of ours. A
   compressor checked only against its own reader can agree with itself and
   be wrong.

   Each sample is written twice: NAME.raw is the input and NAME.z the
   compressed stream. The checker inflates the second and compares. *)

let sample_dir = Sys.argv.(1)

let write name (data : bytes) =
  let path suffix = Filename.concat sample_dir (name ^ suffix) in
  let oc = open_out_bin (path ".raw") in
  output_bytes oc data;
  close_out oc;
  let oc = open_out_bin (path ".z") in
  output_bytes oc (Raster.Zlib.compress data);
  close_out oc

(* A deterministic generator: a test that varies between runs cannot be
   bisected when it fails. *)
let lcg = ref 12345
let next_byte () =
  lcg := ((!lcg * 1103515245) + 12345) land 0x3fffffff;
  (!lcg lsr 16) land 0xff

let () =
  write "empty" Bytes.empty;
  write "one" (Bytes.of_string "A");
  write "two" (Bytes.of_string "AB");
  (* Shorter than the three bytes a match needs. *)
  write "under_min_match" (Bytes.of_string "AA");
  (* A run: the distance-1 case, which is where a naive matcher overlaps. *)
  write "run" (Bytes.make 1000 '\x00');
  (* Long enough to need several maximum-length matches in a row. *)
  write "long_run" (Bytes.make 100_000 '\xff');
  write "repeating" (Bytes.init 50_000 (fun i -> Char.chr (i mod 7)));
  (* Incompressible: every literal path, including the 9-bit codes above 143. *)
  write "random" (Bytes.init 20_000 (fun _ -> Char.chr (next_byte ())));
  (* A match further back than the window, so it must NOT be referenced. *)
  let far = Bytes.make 40_000 'x' in
  Bytes.blit_string "UNIQUEMARKER" 0 far 0 12;
  Bytes.blit_string "UNIQUEMARKER" 0 far 39_000 12;
  write "beyond_window" far;
  (* The shape that actually matters: a frame of RGB scanlines with a filter
     byte in front of each, mostly flat with a band of noise. *)
  let w = 640 and h = 400 in
  let frame = Bytes.create (h * ((w * 3) + 1)) in
  let p = ref 0 in
  for y = 0 to h - 1 do
    Bytes.set frame !p '\x00';
    incr p;
    for x = 0 to w - 1 do
      let v = if y > 180 && y < 220 then next_byte () else (x / 80) * 32 in
      Bytes.set frame !p (Char.chr v);
      Bytes.set frame (!p + 1) (Char.chr (v land 0x7f));
      Bytes.set frame (!p + 2) (Char.chr (255 - v));
      p := !p + 3
    done
  done;
  write "frame" frame
