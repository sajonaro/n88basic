(* What a filled area takes its colour from: one colour everywhere, or a
   tile pattern that varies with position ([2] PAINT, ref-9801 printed
   p.118-119 / PDF p.129-130).

   PAINT's flood, LINE ,BF's rectangle and CIRCLE's F all fill, and all
   three accept either form, so they share this one abstraction rather than
   each growing a tile branch of its own. It is a function of the screen
   position rather than a colour, because that is the whole of what a tile
   adds: the pattern repeats from the screen origin, so what a pixel gets
   depends on where the pixel is and not on which fill put it there. A solid
   fill is the constant function, which keeps the two cases from needing
   separate code paths downstream.

   What it yields is a *palette number*, not a colour: the framebuffer stores
   palette numbers, so resolving to RGB here would be resolving too early and
   would freeze the fill against a later [2] COLOR. *)

type t = { colour_at : x:int -> y:int -> int }

let of_palette (p : int) : t = { colour_at = (fun ~x:_ ~y:_ -> p) }
let tiled (tile : N88basic.Tile.t) : t = { colour_at = N88basic.Tile.palette_at tile }

(* A [Display.paint_style] resolved for drawing. Kept here rather than in
   rasterize.ml so that every caller turning one into pixels does it the
   same way. *)
let of_style (style : N88basic.Display.paint_style) : t =
  match style with
  | N88basic.Display.Solid p -> of_palette p
  | N88basic.Display.Tiled tile -> tiled tile

let colour_at (t : t) ~(x : int) ~(y : int) : int = t.colour_at ~x ~y
