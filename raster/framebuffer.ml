(* A 640x400 palette-indexed pixel buffer — the PC-9801 display's fixed
   resolution (design §7).

   WHY INDICES AND NOT RGB. This buffer used to hold three bytes per pixel,
   the resolved colour. That is the wrong model, and [2] COLOR is what makes
   it wrong: ref-9801 printed p.51 says every colour given to the graphics
   screen is given *through* the palette, so a palette number is what a
   drawing operation actually writes, and the RGB it currently shows is a
   display-time lookup. Reassigning a palette must therefore recolour what is
   already on the screen — book intro-8801 printed p.119 demonstrates exactly
   that: draw a dot through palette 0 while palette 0 shows white, reassign
   palette 0 to blue, and the dot already drawn turns blue. An RGB buffer
   cannot do it, because the pixel no longer knows which palette drew it.

   Storing the index is also the faithful model of the hardware, whose
   graphics screen is three bit planes — an index, not a colour. The RGB
   buffer only ever worked because nothing could move the palette.

   Pixels are stored row-major, one byte each, holding a palette number. The
   palette maps each number to a colour code, and [Palette.colours] maps that
   code to RGB; both hops happen at PNG-write time, in [rgb_at]. *)

let width = 640
let height = 400

type t = {
  pixels : Bytes.t;
      (* Invariant: [Bytes.length pixels = width * height], one palette
         number per pixel. *)
  palette : int array;
      (* [palette.(n)] is the colour code palette number [n] displays.
         Invariant: [Array.length palette = Palette.count]. *)
}

let create () : t =
  (* Cleared to palette 0, matching a screen before any CLS has run. The
     palette starts as the identity mapping, which is the startup state
     ref-9801 printed p.51 refers [1] COLOR to, and which is *why* a palette
     number and a colour number look interchangeable until something moves
     one. *)
  { pixels = Bytes.make (width * height) '\000'; palette = Palette.initial_mapping () }

let in_bounds ~x ~y : bool = x >= 0 && x < width && y >= 0 && y < height
let index ~x ~y : int = (y * width) + x

(* Every write goes through here, so clipping to the framebuffer — required
   by the task regardless of how far off-screen a caller's coordinates run —
   is enforced in exactly one place. *)
let set_pixel (t : t) ~x ~y ~(palette : int) : unit =
  if in_bounds ~x ~y then Bytes.set t.pixels (index ~x ~y) (Char.chr (Palette.wrap palette))

(* The palette number stored at a pixel. This is what GFX.POINT reports, and
   it is now a direct read: the old buffer had to search the colour table for
   a matching RGB triple (Palette.index_of_rgb), which was exact only because
   colours are never blended. That reverse lookup is gone. *)
let get_pixel (t : t) ~x ~y : int =
  if not (in_bounds ~x ~y) then invalid_arg "Framebuffer.get_pixel: out of bounds"
  else Char.code (Bytes.get t.pixels (index ~x ~y))

(* The colour a pixel currently displays: palette number -> colour code ->
   RGB. Only output paths need this — PNG encoding and the tests that assert
   on appearance rather than on which palette drew a dot. *)
let rgb_at (t : t) ~x ~y : int * int * int =
  Palette.to_rgb t.palette.(Palette.wrap (get_pixel t ~x ~y))

let clear (t : t) : unit = Bytes.fill t.pixels 0 (Bytes.length t.pixels) '\000'

(* [clear] in one palette number rather than in palette 0: CLS 2 and CLS 3
   paint the graphics screen in the background colour [1] COLOR set, so
   palette 0 is only the default case of this (ref-9801 printed p.48 / PDF
   p.59). Written as a byte fill so that the common case -- a whole 640x400
   screen -- costs one pass rather than 256000 bounds checks. *)
let fill (t : t) ~(palette : int) : unit =
  Bytes.fill t.pixels 0 (Bytes.length t.pixels) (Char.chr (Palette.wrap palette))

(* [2] COLOR = (<palette number>, <colour code>) — ref-9801 printed p.51.
   Any palette number may be given any legal code, and the same code may be
   given to several palette numbers at once, so this is an unguarded write. *)
let set_palette (t : t) ~(palette : int) ~(code : int) : unit =
  t.palette.(Palette.wrap palette) <- Palette.wrap code

(* Bare COLOR with the equals sign and both arguments omitted: initialise the
   mapping back to its startup state (ref-9801 printed p.51). *)
let reset_palette (t : t) : unit =
  Array.blit (Palette.initial_mapping ()) 0 t.palette 0 (Array.length t.palette)

(* The whole screen as RGB, row-major, three bytes per pixel. Both output
   paths share it so that a PNG and a conformance digest can never disagree
   about what the frame looks like. *)
let to_rgb_bytes (t : t) : bytes =
  let out = Bytes.create (width * height * 3) in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let r, g, b = rgb_at t ~x ~y in
      let i = ((y * width) + x) * 3 in
      Bytes.set out i (Char.chr (r land 0xff));
      Bytes.set out (i + 1) (Char.chr (g land 0xff));
      Bytes.set out (i + 2) (Char.chr (b land 0xff))
    done
  done;
  out
