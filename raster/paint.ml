(* PAINT's flood fill (ref-9801 printed p.117).

   A scanline fill over an explicit stack, never recursion. A recursive
   flood fill of a 640x400 region overflows the stack on a region only a
   few hundred pixels across, which on a chart is not a rare edge case but
   the ordinary case — the whole point of PAINT is filling large areas.

   Termination is guaranteed by a visited bitmap rather than by reasoning
   about colours. Colour-based termination is the tempting version and it
   is subtly wrong: it holds only while the fill colour differs from every
   colour already inside the region, and when it fails it fails by looping
   forever rather than by drawing something slightly off. A byte per pixel
   is 256KB and buys an argument we do not have to make.

   The fill is bounded by the framebuffer in every direction, so a region
   open to the screen edge floods to the edge and stops — it cannot run
   away. Whether that is what the machine does with an unclosed region is a
   separate question, recorded on GFX.PAINT rather than answered here. *)

type spans = { mutable stack : (int * int) list }

let push s p = s.stack <- p :: s.stack

(* A pixel belongs to the region while it is not the border colour. That is
   the manual's rule: the border colour stops the fill, and everything else
   is inside — including pixels already carrying the fill colour, which is
   why the visited bitmap above and not a colour test does the bookkeeping.

   The comparison is between *palette numbers* now that the framebuffer holds
   them, which is what the manual's rule actually says: PAINT's border
   argument is a palette number, and matching it against a resolved RGB used
   to make two palettes sharing one colour code indistinguishable to the
   fill. They are distinct borders again. *)
let is_inside fb ~visited ~border ~x ~y =
  Framebuffer.in_bounds ~x ~y
  && (not visited.(((y * Framebuffer.width) + x)))
  && Framebuffer.get_pixel fb ~x ~y <> border

(* [area] is a [Fill.t] rather than a colour so that a tile pattern fills
   exactly the region a flat colour would ([2] PAINT, ref-9801 printed
   p.118-119). It also strengthens the visited-bitmap argument in the header
   above rather than weakening it: with a pattern the pixels already filled
   are no longer any one colour, so a colour test could not have terminated
   this fill even in principle. *)
let fill (fb : Framebuffer.t) ~(x : int) ~(y : int) ~(area : Fill.t)
    ~(border : int) : unit =
  if Framebuffer.in_bounds ~x ~y && Framebuffer.get_pixel fb ~x ~y <> border then begin
    let visited = Array.make (Framebuffer.width * Framebuffer.height) false in
    let mark ~x ~y = visited.(((y * Framebuffer.width) + x)) <- true in
    let s = { stack = [] } in
    push s (x, y);
    while s.stack <> [] do
      match s.stack with
      | [] -> ()
      | (px, py) :: rest ->
          s.stack <- rest;
          if is_inside fb ~visited ~border ~x:px ~y:py then begin
            (* Walk left and right to the span's ends, filling as we go. *)
            let left = ref px in
            while is_inside fb ~visited ~border ~x:(!left - 1) ~y:py do
              decr left
            done;
            let right = ref px in
            while is_inside fb ~visited ~border ~x:(!right + 1) ~y:py do
              incr right
            done;
            for sx = !left to !right do
              mark ~x:sx ~y:py;
              Framebuffer.set_pixel fb ~x:sx ~y:py ~palette:(Fill.colour_at area ~x:sx ~y:py)
            done;
            (* Seed the rows above and below. Every pixel of the span is
               offered rather than only the span ends, so a neighbouring row
               reachable through a one-pixel gap is still found. *)
            for sx = !left to !right do
              if is_inside fb ~visited ~border ~x:sx ~y:(py - 1) then push s (sx, py - 1);
              if is_inside fb ~visited ~border ~x:sx ~y:(py + 1) then push s (sx, py + 1)
            done
          end
    done
  end
