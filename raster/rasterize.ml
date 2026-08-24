(* Turns a display list (basic/display.ml) into a framebuffer. Pure: same
   list in, identical bytes out, every time — see design §7. This module
   owns display-list traversal and the "current point" and current-colour
   rules; the pixel-level maths (clipping, line stepping, box fill) lives in
   Geometry. *)

(* The palette number a drawing op paints with: its own argument, or the
   current foreground/background when it omitted one. No longer resolved to
   RGB here -- the framebuffer stores palette numbers, and resolving now
   would freeze the pixel against a later [2] COLOR. *)
let colour_of ~(default : int) (colour : int option) : int =
  Option.value colour ~default

(* PSET/PRESET's coordinate, resolved against the LP: STEP(dx,dy) is
   relative to it, a bare (x,y) ignores it entirely. *)
let resolve_point (current : float * float) (p : N88basic.Display.point) :
    float * float =
  match p with
  | N88basic.Display.Abs (x, y) -> (x, y)
  | N88basic.Display.Step (dx, dy) ->
      let cx, cy = current in
      (cx +. dx, cy +. dy)

(* One pass over the display list, returning both the pixels and the last
   point referenced when it ends. Callers that want only one of the two get
   it from a wrapper below rather than from a second traversal: the LP is
   moved by six different operations, and a separate function that tried to
   track it alone would be a second definition of the same rule, free to
   drift from this one. *)
let render (ops : N88basic.Display.op list) : Framebuffer.t * (float * float) =
  let fb = Framebuffer.create () in
  (* LINE with no explicit start point continues "from the last point
     referenced" (display.ml's own words for [from_point = None]), and so do
     PSET and PRESET's STEP form — all three share this one running point,
     since ref-9801 (printed p.122) describes the LP as one piece of state
     "most graphics operations" move together, not one per statement kind.
     Before any drawing op has run there is no such point; (0,0) — the
     top-left corner — is used as an unremarkable default, not a citation. *)
  let current = ref (0.0, 0.0) in
  (* The "current foreground/background colour" COLOR sets and PSET, PRESET
     and LINE's omitted-colour argument reads back (ref-9801 printed p.49).
     The startup values are this module's own choice — see
     Palette.default_foreground_index — not read from any source. *)
  let fg = ref Palette.default_foreground_index in
  let bg = ref Palette.default_background_index in
  List.iter
    (fun (op : N88basic.Display.op) ->
      match op with
      | N88basic.Display.Screen _
      | N88basic.Display.Width _
      | N88basic.Display.Locate _
      | N88basic.Display.Console _
      | N88basic.Display.Key _ ->
          (* Text-cursor and mode state, not pixels: recorded by the
             interpreter, ignored here per the task's scope. *)
          ()
      (* CLS 1 clears the text screen, and this buffer holds no text, so it
         is not a no-op we are cutting a corner on -- it is the whole of
         what CLS 1 does to a graphics screen. The bare CLS a listing
         writes before it starts drawing is CLS 1, which is exactly why
         clearing the framebuffer here used to erase pictures the program
         meant to keep (spec/clauses.json SCREEN.CLS, once divergent).

         CLS 2 and CLS 3 do clear this screen, and they paint it in the
         background colour [1] COLOR set rather than in black; they also
         leave the LP at the top-left corner of the viewport, which -- with
         VIEW out of scope (spec/spec.md section 3.2) -- is the screen's own
         corner, (0,0). *)
      | N88basic.Display.Cls 1 -> ()
      | N88basic.Display.Cls _ ->
          Framebuffer.fill fb ~palette:!bg;
          current := (0.0, 0.0)
      | N88basic.Display.Line { from_point; to_point; colour; box; style; fill } ->
          (* The first point resolves against the LP, and the second against
             the FIRST -- so LINE (10,10)-STEP(30,30) ends at (40,40), not
             at thirty past wherever the previous statement finished. The
             manual offers STEP on both sides without saying what the second
             is relative to; taking it as the point just referenced is our
             reading, and the only one under which the LP means the same
             thing throughout a statement as it does between statements. *)
          let start =
            match from_point with
            | None -> !current
            | Some p -> resolve_point !current p
          in
          let finish = resolve_point start to_point in
          let palette = colour_of ~default:!fg colour in
          (match box with
          | `None -> Geometry.draw_line fb start finish ~palette ?style ()
          | `Frame -> Geometry.draw_frame fb start finish ~palette ?style ()
          | `Filled ->
              (* ,BF's own palette number colours the interior; with none
                 given the interior takes the colour the rectangle was drawn
                 in, which is what [colour_of] already resolved. *)
              let area =
                match fill with
                | Some style -> Fill.of_style style
                | None -> Fill.of_palette palette
              in
              Geometry.fill_rect fb start finish ~fill:area);
          current := finish
      (* The POINT statement: move the LP, paint nothing. *)
      | N88basic.Display.Point_lp { point } -> current := resolve_point !current point
      | N88basic.Display.Pset { point; colour } ->
          let x, y = resolve_point !current point in
          Framebuffer.set_pixel fb ~x:(Geometry.round_to_int x)
            ~y:(Geometry.round_to_int y) ~palette:(colour_of ~default:!fg colour);
          current := (x, y)
      | N88basic.Display.Preset { point; colour } ->
          let x, y = resolve_point !current point in
          (* Unlike PSET, an omitted colour here does not mean "the
             foreground": ref-9801 (printed p.124) has PRESET paint over
             with the background colour when none is given, and behave
             exactly like PSET (foreground default included) when one is. *)
          Framebuffer.set_pixel fb ~x:(Geometry.round_to_int x)
            ~y:(Geometry.round_to_int y) ~palette:(colour_of ~default:!bg colour);
          current := (x, y)
      | N88basic.Display.Circle { center; radius; colour; start_angle; end_angle; aspect; fill } ->
          let cx, cy = resolve_point !current center in
          let palette = colour_of ~default:!fg colour in
          let aspect = Option.value aspect ~default:1.0 in
          (* An omitted palette after the F fills in the colour the circle
             itself was drawn in, which is what [palette] already is. *)
          let circle_fill =
            Option.map
              (fun (f : N88basic.Display.circle_fill) ->
                match f with
                | N88basic.Display.Fill_current -> Fill.of_palette palette
                | N88basic.Display.Fill_palette p -> Fill.of_palette p
                | N88basic.Display.Fill_tile t -> Fill.tiled t)
              fill
          in
          Circle.draw fb ~cx ~cy ~radius ~aspect ~start_angle ~end_angle ~palette
            ?fill:circle_fill ();
          (* CIRCLE moves the last point referenced to its centre, not to a
             point on the arc — the centre is the coordinate the statement
             names, and the arc has no single endpoint when it closes. *)
          current := (cx, cy)
      | N88basic.Display.Paint { point; area; border } ->
          let x, y = resolve_point !current point in
          let area_fill =
            match area with
            | Some style -> Fill.of_style style
            | None -> Fill.of_palette !fg
          in
          (* An omitted border defaults to the area colour, so a fill with
             no border argument stops at pixels already carrying the fill
             colour. That is the manual's rule, and it is why a shape
             outlined in the fill colour paints correctly with two
             arguments. *)
          (* An omitted border defaults to "the same colour as area", which
             stops the fill at pixels already carrying the fill colour. A
             TILE has no single colour for that default to name, and the
             manual does not say what an omitted border means in the tile
             form -- so the current foreground colour is used there, being
             the colour an omitted area would itself have taken. That choice
             is ours; see GFX.PAINT. *)
          let border_palette =
            match (border, area) with
            | Some c, _ -> c
            | None, Some (N88basic.Display.Tiled _) -> !fg
            | None, Some (N88basic.Display.Solid p) -> p
            | None, None -> !fg
          in
          Paint.fill fb ~x:(Geometry.round_to_int x) ~y:(Geometry.round_to_int y)
            ~area:area_fill ~border:border_palette;
          current := (x, y)
      | N88basic.Display.Color { background; foreground; function_code = _; border = _ } ->
          (* function_code (text-attribute) and border have no rasterised
             form — this buffer draws no text and has no border region —
             so only the two colours PSET/PRESET consume are tracked. *)
          Option.iter (fun c -> bg := c) background;
          Option.iter (fun c -> fg := c) foreground
      (* [2] COLOR = (<palette number>, <colour code>), ref-9801 printed
         p.51. It paints nothing: it changes what the numbers already in the
         buffer will resolve to when the PNG is written, which is exactly how
         it recolours pixels drawn before it ran. *)
      | N88basic.Display.Color_palette { palette; code } ->
          Framebuffer.set_palette fb ~palette ~code
      | N88basic.Display.Color_palette_init -> Framebuffer.reset_palette fb)
    ops;
  (fb, !current)

let to_framebuffer (ops : N88basic.Display.op list) : Framebuffer.t = fst (render ops)

(* Whether a display list yields a picture worth writing out.

   bin/ needs this to decide whether to write a PNG at all, and its own
   comment promises that "a program that drew nothing must behave exactly as
   it did before graphics existed: no stray file". It used to ask whether the
   op list was non-empty, which is a different question: WIDTH, CONSOLE,
   SCREEN, COLOR and LOCATE are all recorded here and none of them paints, so
   a text-only listing that set WIDTH 80 got a blank PNG dropped beside it.
   Found by running the book's chapter 5, which is full of such listings.

   Asked as "does the frame differ from a blank screen" rather than by
   listing which ops paint. That is the criterion that actually matters --
   is there anything to look at -- and it needs no per-op judgement, so it
   cannot drift when an op is added. It also gets the awkward case right
   without special-casing it: a program whose only statement is COLOR=(0,2)
   paints nothing, yet every pixel of the blank screen is palette 0 and now
   shows red, so there IS a picture and one is written. *)
let produces_a_picture (ops : N88basic.Display.op list) : bool =
  let drawn = to_framebuffer ops in
  let blank = Framebuffer.create () in
  Framebuffer.to_rgb_bytes drawn <> Framebuffer.to_rgb_bytes blank

(* The LP itself, for [1] POINT(<function>). Same single traversal every
   other query here uses, so the LP this reports is by construction the one
   the next drawing operation will step from. *)
let last_point (ops : N88basic.Display.op list) : float * float = snd (render ops)

(* Where a point spec lands, given everything drawn before it -- the answer to
   the question basic/ cannot ask itself, since resolving a STEP needs the LP
   and the LP lives here. *)
let resolve_against (ops : N88basic.Display.op list) (p : N88basic.Display.point) :
    float * float =
  resolve_point (snd (render ops)) p

(* Whether a point spec lands inside the window, which is what PAINT's own
   entry makes an error to get wrong (ref-9801 printed p.117 / PDF p.128).
   With VIEW and WINDOW out of scope the window is the whole screen, so this
   is the framebuffer's own bounds test applied to a resolved point. *)
let in_window (ops : N88basic.Display.op list) (p : N88basic.Display.point) : bool =
  let x, y = resolve_against ops p in
  Framebuffer.in_bounds ~x:(Geometry.round_to_int x) ~y:(Geometry.round_to_int y)
