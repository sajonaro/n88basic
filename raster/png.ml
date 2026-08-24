(* PNG encoding (design §7): signature, IHDR, one IDAT holding a Zlib stream
   of stored blocks, IEND. Truecolor (colour type 2), 8 bits per channel, no
   interlacing, filter type 0 (None) on every scanline. This is the only
   module in raster/ that produces file-format bytes; it still performs no
   I/O itself; the caller decides whether those bytes reach a disk. *)

let signature = "\x89PNG\r\n\x1a\n"

let add_be32 (buf : Buffer.t) (n : int) : unit =
  Buffer.add_char buf (Char.chr ((n lsr 24) land 0xff));
  Buffer.add_char buf (Char.chr ((n lsr 16) land 0xff));
  Buffer.add_char buf (Char.chr ((n lsr 8) land 0xff));
  Buffer.add_char buf (Char.chr (n land 0xff))

let chunk (kind : string) (data : bytes) : bytes =
  let buf = Buffer.create (Bytes.length data + 12) in
  add_be32 buf (Bytes.length data);
  Buffer.add_string buf kind;
  Buffer.add_bytes buf data;
  let crc_input = Bytes.cat (Bytes.of_string kind) data in
  add_be32 buf (Checksums.to_unsigned (Checksums.crc32 crc_input));
  Buffer.to_bytes buf

let ihdr (width : int) (height : int) : bytes =
  let buf = Buffer.create 13 in
  add_be32 buf width;
  add_be32 buf height;
  Buffer.add_char buf '\008';
  (* bit depth *)
  Buffer.add_char buf '\002';
  (* colour type: truecolor *)
  Buffer.add_char buf '\000';
  (* compression method: deflate, the only one PNG defines *)
  Buffer.add_char buf '\000';
  (* filter method: the only one PNG defines *)
  Buffer.add_char buf '\000';
  (* interlace method: none *)
  Buffer.to_bytes buf

(* Filter type 0 (None) on every row, then the row's pixels as RGB.

   This is where the palette indirection is resolved: the framebuffer holds
   palette numbers, and the colour each one shows is whatever the palette
   says *at the moment the picture is written*. That is the whole mechanism
   behind [2] COLOR recolouring pixels already drawn (ref-9801 printed p.51,
   demonstrated at book intro-8801 printed p.119) -- nothing rewrites those
   pixels, they simply resolve differently here. *)
let raw_scanlines (fb : Framebuffer.t) : bytes =
  let w = Framebuffer.width and h = Framebuffer.height in
  let row_bytes = w * 3 in
  let out = Bytes.create (h * (1 + row_bytes)) in
  for y = 0 to h - 1 do
    let row_start = y * (1 + row_bytes) in
    Bytes.set out row_start '\000';
    for x = 0 to w - 1 do
      let r, g, b = Framebuffer.rgb_at fb ~x ~y in
      let p = row_start + 1 + (x * 3) in
      Bytes.set out p (Char.chr r);
      Bytes.set out (p + 1) (Char.chr g);
      Bytes.set out (p + 2) (Char.chr b)
    done
  done;
  out

(* Pixel density, 72 per inch on both axes (2835 pixels per metre, the
   conventional rounding of 72 / 0.0254). PNG's own pixels are otherwise
   unitless; without this chunk some readers assume 96 DPI and report this
   640x400 framebuffer as a 480x300-point page — a scaling artefact of the
   *reader*, not a claim this encoder makes about physical size, but naming
   a density here keeps "640x400 pixels in" reading back as "640x400 out". *)
let phys : bytes =
  let buf = Buffer.create 9 in
  add_be32 buf 2835;
  add_be32 buf 2835;
  Buffer.add_char buf '\001';
  (* unit specifier: metre *)
  Buffer.to_bytes buf

let encode (fb : Framebuffer.t) : string =
  let buf = Buffer.create (1 lsl 20) in
  Buffer.add_string buf signature;
  Buffer.add_bytes buf
    (chunk "IHDR" (ihdr Framebuffer.width Framebuffer.height));
  Buffer.add_bytes buf (chunk "pHYs" phys);
  Buffer.add_bytes buf (chunk "IDAT" (Zlib.compress (raw_scanlines fb)));
  Buffer.add_bytes buf (chunk "IEND" Bytes.empty);
  Buffer.contents buf
