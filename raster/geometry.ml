(* Pixel-level drawing primitives for LINE's three forms, each clipped to the
   framebuffer so a program drawing off-screen touches no memory outside the
   buffer and never loops unboundedly. All arithmetic here is integer or
   exact-rational (Liang-Barsky's parameters), never formatted to text, so
   two runs of the same input always draw the same pixels. *)

(* A coordinate that has escaped the display's range by more than this is
   treated as "very far away" rather than passed to [int_of_float] as-is:
   that conversion is unspecified for NaN, infinities, and magnitudes
   outside the representable-int range, and BASIC arithmetic (e.g. a huge
   intermediate product) can in principle produce any of those. Clamping
   first keeps every later computation finite and bounded, whatever the
   input was. *)
let coord_limit = 1.0e7

let finite (v : float) : float =
  match Float.classify_float v with
  | Float.FP_nan | Float.FP_infinite -> 0.0
  | Float.FP_normal | Float.FP_subnormal | Float.FP_zero -> v

let clamp_coord (v : float) : float =
  let v = finite v in
  if v < -.coord_limit then -.coord_limit
  else if v > coord_limit then coord_limit
  else v

let round_to_int (v : float) : int = int_of_float (Float.round (clamp_coord v))

(* Liang-Barsky segment clipping against [xmin,xmax] x [ymin,ymax] (both
   inclusive). Returns the clipped endpoints, or [None] if the segment
   misses the rectangle entirely. *)
let clip_segment ~xmin ~ymin ~xmax ~ymax ((x0, y0) : float * float)
    ((x1, y1) : float * float) : ((float * float) * (float * float)) option =
  let dx = x1 -. x0 and dy = y1 -. y0 in
  let t0 = ref 0.0 and t1 = ref 1.0 in
  let accept = ref true in
  let clip_edge p q =
    if !accept then
      if p = 0.0 then (if q < 0.0 then accept := false)
      else begin
        let r = q /. p in
        if p < 0.0 then begin
          if r > !t1 then accept := false else if r > !t0 then t0 := r
        end
        else if r < !t0 then accept := false
        else if r < !t1 then t1 := r
      end
  in
  clip_edge (-.dx) (x0 -. xmin);
  clip_edge dx (xmax -. x0);
  clip_edge (-.dy) (y0 -. ymin);
  clip_edge dy (ymax -. y0);
  if !accept then
    Some
      ( (x0 +. (!t0 *. dx), y0 +. (!t0 *. dy)),
        (x0 +. (!t1 *. dx), y0 +. (!t1 *. dy)) )
  else None

(* LINE's sixteen-bit line style: dot [n] along the line is drawn when bit
   [15 - (n mod 16)] of the mask is set, so the mask reads left to right as
   the manual's own figure draws it -- &HF99F's leading F is the first four
   dots (ref-9801 printed p.94-95 / PDF p.105-106). [None] is a solid line.

   The count starts at the first dot actually drawn, which for a line
   running off the buffer is the first ON-SCREEN dot rather than the true
   endpoint. The manual says only that the pattern repeats every sixteen
   dots on screen and never addresses a clipped line, so that is our
   reading rather than a stated rule. *)
let style_lights (style : int option) (n : int) : bool =
  match style with
  | None -> true
  | Some mask -> mask land (1 lsl (15 - (n mod 16))) <> 0

(* Bresenham, on integer points already known to lie within the buffer
   (or right on its edge), so every step's [set_pixel] call is a courtesy
   bounds-check rather than a load-bearing one. *)
let bresenham (fb : Framebuffer.t) (x0, y0) (x1, y1) ~palette ?style () : unit =
  let dx = abs (x1 - x0) and sx = if x0 < x1 then 1 else -1 in
  let dy = -abs (y1 - y0) and sy = if y0 < y1 then 1 else -1 in
  let err = ref (dx + dy) in
  let x = ref x0 and y = ref y0 in
  let step = ref 0 in
  let continue_ = ref true in
  while !continue_ do
    if style_lights style !step then Framebuffer.set_pixel fb ~x:!x ~y:!y ~palette;
    incr step;
    if !x = x1 && !y = y1 then continue_ := false
    else begin
      let e2 = 2 * !err in
      if e2 >= dy then begin
        err := !err + dy;
        x := !x + sx
      end;
      if e2 <= dx then begin
        err := !err + dx;
        y := !y + sy
      end
    end
  done

let draw_line (fb : Framebuffer.t) (p0 : float * float) (p1 : float * float)
    ~palette ?style () : unit =
  let clamp (x, y) = (clamp_coord x, clamp_coord y) in
  let p0 = clamp p0 and p1 = clamp p1 in
  let xmax = float_of_int (Framebuffer.width - 1) in
  let ymax = float_of_int (Framebuffer.height - 1) in
  match clip_segment ~xmin:0.0 ~ymin:0.0 ~xmax ~ymax p0 p1 with
  | None -> () (* the segment never touches the framebuffer *)
  | Some ((cx0, cy0), (cx1, cy1)) ->
      let to_i v = int_of_float (Float.round v) in
      bresenham fb (to_i cx0, to_i cy0) (to_i cx1, to_i cy1) ~palette ?style ()

(* Shared by the frame and filled forms of LINE's box: normalise the two
   corners into an (xlo,ylo)-(xhi,yhi) rectangle in integer device space,
   and the same rectangle intersected with the framebuffer — [None] when
   the box does not touch the buffer at all. *)
let rectangle (p0 : float * float) (p1 : float * float) :
    (int * int * int * int) * (int * int * int * int) option =
  let x0, y0 = p0 and x1, y1 = p1 in
  let xlo = min (round_to_int x0) (round_to_int x1)
  and xhi = max (round_to_int x0) (round_to_int x1)
  and ylo = min (round_to_int y0) (round_to_int y1)
  and yhi = max (round_to_int y0) (round_to_int y1) in
  let vxlo = max 0 xlo and vxhi = min (Framebuffer.width - 1) xhi in
  let vylo = max 0 ylo and vyhi = min (Framebuffer.height - 1) yhi in
  let visible =
    if vxlo <= vxhi && vylo <= vyhi then Some (vxlo, vylo, vxhi, vyhi)
    else None
  in
  ((xlo, ylo, xhi, yhi), visible)

(* LINE ,BF's interior, which takes a [Fill.t] because ,BF's trailing
   argument may be a tile string as well as a palette number (ref-9801
   printed p.94, and [2] PAINT p.118-119 for what a tile string means). *)
let fill_rect (fb : Framebuffer.t) (p0 : float * float) (p1 : float * float)
    ~(fill : Fill.t) : unit =
  match snd (rectangle p0 p1) with
  | None -> ()
  | Some (vxlo, vylo, vxhi, vyhi) ->
      for y = vylo to vyhi do
        for x = vxlo to vxhi do
          Framebuffer.set_pixel fb ~x ~y ~palette:(Fill.colour_at fill ~x ~y)
        done
      done

(* A ,B outline may carry a line style -- the manual forbids one only with
   BF, which is what says it is allowed here (ref-9801 printed p.94). It
   does not say how the pattern relates to the four sides, so this is our
   reading: one counter runs on across all four in the order they are drawn
   (top, bottom, left, right), rather than restarting at each side. A
   per-side restart would give every side the same dash sequence, which the
   manual's figure -- a single run of dots along one line -- gives no
   grounds for. The counter is not walked around the perimeter in
   geometric order either; it simply continues, which is the same choice
   made visible. *)
let draw_frame (fb : Framebuffer.t) (p0 : float * float) (p1 : float * float)
    ~palette ?style () : unit =
  let (xlo, ylo, xhi, yhi), visible = rectangle p0 p1 in
  match visible with
  | None -> ()
  | Some (vxlo, vylo, vxhi, vyhi) ->
      let row_in_bounds y = y >= 0 && y <= Framebuffer.height - 1 in
      let col_in_bounds x = x >= 0 && x <= Framebuffer.width - 1 in
      let step = ref 0 in
      let dot ~x ~y =
        if style_lights style !step then Framebuffer.set_pixel fb ~x ~y ~palette;
        incr step
      in
      if row_in_bounds ylo then
        for x = vxlo to vxhi do
          dot ~x ~y:ylo
        done;
      if yhi <> ylo && row_in_bounds yhi then
        for x = vxlo to vxhi do
          dot ~x ~y:yhi
        done;
      if col_in_bounds xlo then
        for y = vylo to vyhi do
          dot ~x:xlo ~y
        done;
      if xhi <> xlo && col_in_bounds xhi then
        for y = vylo to vyhi do
          dot ~x:xhi ~y
        done
