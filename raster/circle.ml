(* CIRCLE's arc and ellipse geometry (ref-9801 printed p.45). Reuses
   Geometry.draw_line to stroke a chain of short segments around the curve
   rather than a midpoint/Bresenham ellipse walk: consecutive sample points
   are close enough together that Geometry's own clipped, bounds-checked
   line drawer connects them with no gap, which is exactly the property
   design SS11 warns a naive ellipse rasteriser can get wrong -- a boundary
   with a diagonal gap is a hole a later PAINT would leak straight through. *)

let two_pi = 2.0 *. Float.pi

(* However large a radius a program supplies, the number of segments drawn
   is capped well above anything a 640x400 buffer could ever need, so a
   pathological radius costs a bounded number of iterations rather than
   scaling the loop to a caller-supplied number (the same defensive posture
   as Geometry.clamp_coord for LINE's endpoints). *)
let max_samples = 8000

let sample_count ~rx ~ry ~span =
  let max_r = Float.max (Float.abs rx) (Float.abs ry) in
  let estimate = int_of_float (Float.ceil (max_r *. Float.abs span)) + 1 in
  min max_samples (max 2 estimate)

(* The manual's own angle diagram (ref-9801 printed p.45) places pi/2 at the
   top of the circle and increases counterclockwise as conventionally
   drawn. Screen Y grows downward, so matching that picture on an actual
   framebuffer means the Y term must shrink as the angle grows -- hence the
   minus sign on the sine term, our reading of the figure rather than
   prose the page states outright. *)
let point ~cx ~cy ~rx ~ry theta = (cx +. (rx *. Float.cos theta), cy -. (ry *. Float.sin theta))

let draw_arc (fb : Framebuffer.t) ~cx ~cy ~rx ~ry ~theta0 ~theta1 ~palette : unit =
  let span = theta1 -. theta0 in
  let n = sample_count ~rx ~ry ~span in
  let prev = ref (point ~cx ~cy ~rx ~ry theta0) in
  for i = 1 to n do
    let t = theta0 +. (span *. float_of_int i /. float_of_int n) in
    let p = point ~cx ~cy ~rx ~ry t in
    Geometry.draw_line fb !prev p ~palette ();
    prev := p
  done

(* <aspect> is (vertical radius)/(horizontal radius); <radius> is applied to
   whichever of the two is larger, not always to the horizontal one -- so an
   aspect above 1 (vertically-long) divides <radius> down for the *horizontal*
   axis instead of multiplying it up for the vertical one. Getting this branch
   backwards is exactly the "ellipse where a circle was asked for" design SS11
   warns a plausible-looking renderer can produce unnoticed. *)
let resolve_radii ~radius ~aspect =
  if aspect <= 1.0 then (radius, radius *. aspect) else (radius /. aspect, radius)

(* Negative start/end angles (ref-9801 printed p.45): the absolute value is
   the angle actually used, and a radius line is drawn from the centre to
   that endpoint -- independently for start and end, since the manual's
   prose does not say the two must both be negative together to get a line
   at all (see spec/clauses.json GFX.CIRCLE for this as a recorded decision,
   not a stated rule). *)
let draw (fb : Framebuffer.t) ~cx ~cy ~radius ~aspect ~start_angle ~end_angle ~palette
    ?(fill : Fill.t option) () : unit =
  let rx, ry = resolve_radii ~radius ~aspect in
  let theta0_raw = Option.value start_angle ~default:0.0 in
  let theta1_raw = Option.value end_angle ~default:two_pi in
  let theta0 = Float.abs theta0_raw in
  let theta1_abs = Float.abs theta1_raw in
  let theta1 = if theta1_abs < theta0 then theta1_abs +. two_pi else theta1_abs in
  draw_arc fb ~cx ~cy ~rx ~ry ~theta0 ~theta1 ~palette;
  let radius_line theta =
    let px, py = point ~cx ~cy ~rx ~ry theta in
    Geometry.draw_line fb (cx, cy) (px, py) ~palette ()
  in
  (* An arc given angles is only a wedge once its two radius lines are there.
     F makes it one: "when F is specified while start and end angles are
     given, a sector is drawn and its interior is filled" (printed p.45), so
     the lines are drawn for a fill even where the angles are positive and
     the negative-angle rule would not have asked for them. Without them the
     region is open and the fill would escape around the arc. *)
  let has_angles = start_angle <> None || end_angle <> None in
  let closing = fill <> None && has_angles in
  (match start_angle with
  | Some a when a < 0.0 -> radius_line theta0
  | _ -> if closing then radius_line theta0);
  (match end_angle with
  | Some a when a < 0.0 -> radius_line theta1
  | _ -> if closing then radius_line theta1);
  match fill with
  | None -> ()
  | Some area ->
      (* Seeded on the bisector at half the radius rather than at the centre:
         for a sector the centre lies on the two radius lines, which are the
         border the fill must not start on. For a whole circle the bisector
         point is just as interior as the centre is. *)
      let mid = (theta0 +. theta1) /. 2.0 in
      let sx, sy = point ~cx ~cy ~rx:(rx /. 2.0) ~ry:(ry /. 2.0) mid in
      Paint.fill fb ~x:(Geometry.round_to_int sx) ~y:(Geometry.round_to_int sy)
        ~area ~border:palette
