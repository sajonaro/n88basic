(* CIRCLE and PAINT, tested against actual pixels.

   Design §11 records why these two get more care than the rest: a
   framebuffer digest catches a regression but cannot catch a rendering
   that was wrong on its first run. A circle with the wrong aspect and a
   fill that leaks past its border both look entirely deliberate. So these
   tests assert geometry — measured extents, a pixel on the arc and a pixel
   on the part that should have been omitted — rather than "something was
   drawn". *)

open Raster

let abs_pt (x, y) : N88basic.Display.point = N88basic.Display.Abs (x, y)

let circle ?colour ?start_angle ?end_angle ?aspect ?fill ~centre ~radius () :
    N88basic.Display.op =
  N88basic.Display.Circle
    { center = abs_pt centre; radius; colour; start_angle; end_angle; aspect; fill }

(* [area] stays a bare palette number in these helpers: every case here
   fills flat, and the tile form has its own tests. The wrapper does the
   Solid wrapping so the cases read as they did. *)
let paint ?area ?border point : N88basic.Display.op =
  N88basic.Display.Paint
    { point = abs_pt point;
      area = Option.map (fun p -> N88basic.Display.Solid p) area;
      border }

let line ?colour ?(box = `None) from_point to_point : N88basic.Display.op =
  N88basic.Display.Line
    { from_point = (let x, y = from_point in Some (N88basic.Display.Abs (x, y)));
      to_point = (let x, y = to_point in N88basic.Display.Abs (x, y)); colour; box; style = None; fill = None }

let lit fb ~x ~y = Framebuffer.rgb_at fb ~x ~y <> (0, 0, 0)

let check_lit name fb ~x ~y = Alcotest.(check bool) name true (lit fb ~x ~y)
let check_dark name fb ~x ~y = Alcotest.(check bool) name false (lit fb ~x ~y)

(* Extent of every non-black pixel, so a circle's roundness is measured
   rather than eyeballed. *)
let extent fb =
  let xs = ref [] and ys = ref [] in
  for y = 0 to Framebuffer.height - 1 do
    for x = 0 to Framebuffer.width - 1 do
      if lit fb ~x ~y then (
        xs := x :: !xs;
        ys := y :: !ys)
    done
  done;
  match (!xs, !ys) with
  | [], _ | _, [] -> None
  | xs, ys ->
      let mn l = List.fold_left min max_int l and mx l = List.fold_left max min_int l in
      Some (mx xs - mn xs + 1, mx ys - mn ys + 1)

let render ops = Rasterize.to_framebuffer ops

let test_circle_is_round () =
  let fb = render [ circle ~centre:(200.0, 200.0) ~radius:100.0 () ] in
  (* A true circle spans the same number of pixels in both axes. An aspect
     bug shows up here and nowhere else. *)
  Alcotest.(check (option (pair int int)))
    "a default circle is as wide as it is tall" (Some (201, 201)) (extent fb);
  check_lit "east point on the circumference" fb ~x:300 ~y:200;
  check_lit "west point on the circumference" fb ~x:100 ~y:200;
  check_lit "north point on the circumference" fb ~x:200 ~y:100;
  check_lit "south point on the circumference" fb ~x:200 ~y:300;
  check_dark "the centre is not filled" fb ~x:200 ~y:200

let test_aspect_makes_an_ellipse () =
  (* aspect is (vertical radius)/(horizontal radius): below 1 flattens. *)
  let fb = render [ circle ~centre:(200.0, 200.0) ~radius:100.0 ~aspect:0.4 () ] in
  match extent fb with
  | None -> Alcotest.fail "aspect circle drew nothing"
  | Some (w, h) ->
      Alcotest.(check int) "horizontal extent follows the radius" 201 w;
      Alcotest.(check bool) "aspect 0.4 is markedly flatter than wide" true (h < w / 2)

let test_arc_omits_the_rest_of_the_ring () =
  (* 0 to pi is the upper half on screen: screen Y grows downward, so the
     sine term is negated when sampling. The lower half must stay dark. *)
  let fb =
    render
      [ circle ~centre:(200.0, 200.0) ~radius:100.0 ~start_angle:0.0
          ~end_angle:Float.pi ()
      ]
  in
  check_lit "a point on the drawn upper arc" fb ~x:200 ~y:100;
  check_dark "the omitted lower arc is not drawn" fb ~x:200 ~y:300

let test_paint_fills_and_does_not_leak () =
  let fb =
    render
      [ line ~colour:4 ~box:`Frame (100.0, 100.0) (200.0, 180.0);
        paint ~area:2 ~border:4 (150.0, 140.0)
      ]
  in
  check_lit "the interior is filled" fb ~x:150 ~y:140;
  Alcotest.(check (pair int (pair int int)))
    "interior carries the area colour"
    (let r, g, b = Palette.to_rgb 2 in
     (r, (g, b)))
    (let r, g, b = Framebuffer.rgb_at fb ~x:150 ~y:140 in
     (r, (g, b)));
  (* The whole point: nothing outside the border was touched. *)
  check_dark "just outside the left border" fb ~x:98 ~y:140;
  check_dark "just outside the right border" fb ~x:202 ~y:140;
  check_dark "just above the top border" fb ~x:150 ~y:98;
  check_dark "just below the bottom border" fb ~x:150 ~y:182

let test_paint_on_a_border_pixel_does_nothing () =
  (* ref-9801 printed p.117: when the start point already carries the border
     colour, PAINT performs no screen operation at all. *)
  let framed = [ line ~colour:4 ~box:`Frame (100.0, 100.0) (200.0, 180.0) ] in
  let before = render framed in
  let after = render (framed @ [ paint ~area:2 ~border:4 (100.0, 140.0) ]) in
  Alcotest.(check bool)
    "starting on the border leaves the buffer untouched" true
    (Framebuffer.rgb_at before ~x:150 ~y:140
    = Framebuffer.rgb_at after ~x:150 ~y:140)

let test_paint_open_region_terminates () =
  (* A region open to the screen edge floods to the edge and stops. The test
     exists to prove termination: an unbounded fill hangs the suite rather
     than failing it, so this is the one case worth pinning. *)
  let fb = render [ paint ~area:3 ~border:4 (5.0, 5.0) ] in
  check_lit "the open region reached the top-left corner" fb ~x:0 ~y:0;
  check_lit "and the far corner too" fb ~x:639 ~y:399

let test_determinism () =
  let ops =
    [ circle ~centre:(200.0, 200.0) ~radius:80.0 ();
      line ~colour:4 ~box:`Frame (300.0, 300.0) (400.0, 380.0);
      paint ~area:2 ~border:4 (350.0, 340.0)
    ]
  in
  let a = render ops and b = render ops in
  Alcotest.(check bool) "the same display list rasterises identically" true (a = b)


(* CIRCLE's F (ref-9801 printed p.45 / PDF p.56): "when F is specified, at the
   same time as drawing the circle its interior is filled" -- with palette 2
   when given, and otherwise with the colour the circle itself was drawn in.
   Asserted as geometry rather than as a digest: the centre must be filled and
   a point outside the circle must not, which is what "interior" means and what
   a fill that leaks would break. *)
let test_circle_f_fills_the_interior () =
  let fb =
    Rasterize.to_framebuffer
      [ circle ~centre:(100., 100.) ~radius:30. ~fill:N88basic.Display.Fill_current () ]
  in
  check_lit "centre is filled" fb ~x:100 ~y:100;
  check_lit "well inside is filled" fb ~x:115 ~y:100;
  check_dark "outside the circle is untouched" fb ~x:100 ~y:145

(* Without F the interior stays empty -- the outline alone. This is the guard
   that the test above is measuring the fill and not merely the circle. *)
let test_circle_without_f_leaves_the_interior_empty () =
  let fb = Rasterize.to_framebuffer [ circle ~centre:(100., 100.) ~radius:30. () ] in
  check_dark "centre is empty" fb ~x:100 ~y:100;
  check_lit "the outline is still drawn" fb ~x:130 ~y:100

(* "When F is specified while start and end angles are given, a sector is
   drawn and its interior is filled." So the radius lines close the shape even
   for positive angles, which alone would leave an open arc for the fill to
   escape through. The filled wedge is the first quadrant; the opposite side
   of the circle must stay empty. *)
let test_circle_f_with_angles_fills_a_sector () =
  let fb =
    Rasterize.to_framebuffer
      [ circle ~centre:(200., 200.) ~radius:60. ~start_angle:0.0
          ~end_angle:(Float.pi /. 2.) ~fill:N88basic.Display.Fill_current () ]
  in
  check_lit "inside the wedge is filled" fb ~x:215 ~y:185;
  check_dark "the opposite side is not" fb ~x:170 ~y:230

let () =
  Alcotest.run "raster_circle_paint"
    [ ( "circle",
        [ Alcotest.test_case "a default circle is round" `Quick test_circle_is_round;
          Alcotest.test_case "aspect flattens it" `Quick test_aspect_makes_an_ellipse;
          Alcotest.test_case "an arc omits the rest" `Quick
            test_arc_omits_the_rest_of_the_ring;
          Alcotest.test_case "F fills the interior" `Quick test_circle_f_fills_the_interior;
          Alcotest.test_case "without F the interior is empty" `Quick
            test_circle_without_f_leaves_the_interior_empty;
          Alcotest.test_case "F with angles fills a sector" `Quick
            test_circle_f_with_angles_fills_a_sector
        ] );
      ( "paint",
        [ Alcotest.test_case "fills without leaking" `Quick
            test_paint_fills_and_does_not_leak;
          Alcotest.test_case "no-op on a border pixel" `Quick
            test_paint_on_a_border_pixel_does_nothing;
          Alcotest.test_case "an open region terminates" `Quick
            test_paint_open_region_terminates
        ] );
      ("determinism", [ Alcotest.test_case "same list, same bytes" `Quick test_determinism ])
    ]
