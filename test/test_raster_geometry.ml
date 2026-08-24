(* raster/ is pure, so it is tested against actual pixel values rather than
   "it didn't crash" — geometry, clipping, the current-point rule, and
   determinism of the whole display-list-to-framebuffer pass. *)

open Raster

let line ?from_point ?colour ?(box = `None) to_point : N88basic.Display.op =
  N88basic.Display.Line
    { from_point = Option.map (fun (x, y) -> N88basic.Display.Abs (x, y)) from_point;
      to_point = (let x, y = to_point in N88basic.Display.Abs (x, y)); colour; box; style = None; fill = None }

let px fb ~x ~y = Framebuffer.rgb_at fb ~x ~y

let check_pixel name fb ~x ~y expected =
  Alcotest.(check (pair int (pair int int)))
    name expected
    (let r, g, b = px fb ~x ~y in
     (r, (g, b)))

let black = (0, (0, 0))
let white = (255, (255, 255))

(* colour 7 is white under the provisional palette (raster/palette.ml). *)
let colour7 = white

let test_horizontal_line () =
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(10., 20.) ~colour:7 (30., 20.) ]
  in
  check_pixel "start" fb ~x:10 ~y:20 colour7;
  check_pixel "mid" fb ~x:20 ~y:20 colour7;
  check_pixel "end" fb ~x:30 ~y:20 colour7;
  check_pixel "just past the end, untouched" fb ~x:31 ~y:20 black;
  check_pixel "above the line, untouched" fb ~x:20 ~y:19 black

let test_vertical_line () =
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(50., 10.) ~colour:7 (50., 40.) ]
  in
  check_pixel "start" fb ~x:50 ~y:10 colour7;
  check_pixel "mid" fb ~x:50 ~y:25 colour7;
  check_pixel "end" fb ~x:50 ~y:40 colour7;
  check_pixel "beside the line, untouched" fb ~x:51 ~y:25 black

let test_diagonal_line () =
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(0., 0.) ~colour:7 (9., 9.) ]
  in
  (* A 45-degree diagonal visits every (n,n) exactly. *)
  for n = 0 to 9 do
    check_pixel (Printf.sprintf "diagonal step %d" n) fb ~x:n ~y:n colour7
  done;
  check_pixel "off the diagonal, untouched" fb ~x:0 ~y:9 black

let test_frame_box () =
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(10., 10.) ~colour:7 ~box:`Frame (20., 15.) ]
  in
  (* The four corners and edge midpoints are drawn... *)
  check_pixel "top-left corner" fb ~x:10 ~y:10 colour7;
  check_pixel "top-right corner" fb ~x:20 ~y:10 colour7;
  check_pixel "bottom-left corner" fb ~x:10 ~y:15 colour7;
  check_pixel "bottom-right corner" fb ~x:20 ~y:15 colour7;
  check_pixel "top edge midpoint" fb ~x:15 ~y:10 colour7;
  check_pixel "left edge midpoint" fb ~x:10 ~y:12 colour7;
  (* ...but the interior is not: a Frame is unfilled. *)
  check_pixel "interior, unfilled" fb ~x:15 ~y:12 black

let test_filled_box () =
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(10., 10.) ~colour:7 ~box:`Filled (20., 15.) ]
  in
  check_pixel "corner" fb ~x:10 ~y:10 colour7;
  check_pixel "interior, filled" fb ~x:15 ~y:12 colour7;
  check_pixel "other corner" fb ~x:20 ~y:15 colour7;
  check_pixel "just outside, untouched" fb ~x:21 ~y:12 black;
  check_pixel "just above, untouched" fb ~x:15 ~y:9 black

let test_clip_off_every_edge () =
  (* A line of slope 1 (equal x and y deltas, so no rounding surprises)
     running from well past the top-left corner to well past the
     bottom-right one — off every edge of the 640x400 buffer at both ends.
     It must not crash, must not touch memory outside the buffer
     (get_pixel raises on an out-of-range request, so any corruption would
     surface as that or a wrong read), and the part that does cross the
     visible area — the diagonal (0,0)-(399,399), since the buffer is
     shorter (400 rows) than it is wide (640 columns) — must still be
     drawn. *)
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(-1000., -1000.) ~colour:7 (2000., 2000.) ]
  in
  check_pixel "on-screen point on the line" fb ~x:100 ~y:100 colour7;
  check_pixel "line clipped exactly at the shorter (height) edge" fb ~x:399
    ~y:399 colour7;
  (* Querying every corner succeeds (no crash / out-of-bounds write) and
     off-line corners remain untouched. *)
  check_pixel "top-right corner, off the line" fb ~x:639 ~y:0 black;
  check_pixel "bottom-right corner, off the line" fb ~x:639 ~y:399 black

let test_clip_box_entirely_off_screen () =
  let fb =
    Rasterize.to_framebuffer
      [ line ~from_point:(-500., -500.) ~colour:7 ~box:`Filled
          (-100., -100.)
      ]
  in
  (* Nothing on screen was touched: in particular the top-left pixel, which
     a bug that clamps each corner independently rather than intersecting
     the box with the buffer would wrongly paint. *)
  check_pixel "top-left corner stays black" fb ~x:0 ~y:0 black

let test_current_point_continues () =
  (* The second LINE has no from_point: it must continue from (30,20), the
     first LINE's endpoint, not from the rasterizer's own start-up default
     of (0,0). The second line is the vertical run x=30, y=20..40, so
     (30,30) lies on it only under the correct rule. *)
  let fb =
    Rasterize.to_framebuffer
      [
        line ~from_point:(10., 20.) ~colour:7 (30., 20.);
        line ~colour:7 (30., 40.);
      ]
  in
  check_pixel "continues from the last endpoint" fb ~x:30 ~y:30 colour7;
  (* (8,10) sits close to the diagonal from the wrong default (0,0) to
     (30,40) but is on neither the first line (y=20, x in 10..30) nor the
     correct vertical run (x=30, y in 20..40): a regression to the wrong
     default would light pixels along that diagonal, this one included. *)
  check_pixel "does not fall back to the origin default" fb ~x:8 ~y:10 black

(* CLS 1 -- which is what a bare CLS means -- clears the text screen, and
   this buffer holds no text, so the picture must survive it. This test read
   the other way round until the page was read (ref-9801 printed p.47): it
   asserted that CLS blanked the framebuffer, which is what CLS 2 and CLS 3
   do, and so pinned the divergence rather than catching it. *)
let test_cls_1_leaves_the_picture_alone () =
  let fb =
    Rasterize.to_framebuffer
      [
        line ~from_point:(0., 0.) ~colour:7 (10., 0.);
        N88basic.Display.Cls 1;
      ]
  in
  check_pixel "CLS 1 does not touch the graphics screen" fb ~x:5 ~y:0 colour7

let test_cls_2_and_3_clear_the_graphics_screen () =
  List.iter
    (fun code ->
      let fb =
        Rasterize.to_framebuffer
          [
            line ~from_point:(0., 0.) ~colour:7 (10., 0.);
            N88basic.Display.Cls code;
          ]
      in
      check_pixel
        (Printf.sprintf "cleared after CLS %d" code)
        fb ~x:5 ~y:0 black)
    [ 2; 3 ]

(* Clearing paints the screen in the background colour [1] COLOR set, not in
   black, and leaves the LP at the top-left corner -- so the segment drawn
   after the clear starts from (0,0) with no start point of its own. *)
let test_cls_clears_in_the_background_colour_and_resets_the_lp () =
  let fb =
    Rasterize.to_framebuffer
      [
        N88basic.Display.Color
          { function_code = None; background = Some 2; border = None; foreground = None };
        N88basic.Display.Cls 2;
        line ~colour:7 (0., 20.);
      ]
  in
  let r, g, b = Palette.to_rgb 2 in
  check_pixel "painted in the background colour" fb ~x:300 ~y:300 (r, (g, b));
  check_pixel "the LP is back at the top-left corner" fb ~x:0 ~y:10 colour7

let test_locate_and_key_off_ignored () =
  (* Text-cursor ops must not crash the rasterizer and must not paint
     anything. *)
  let fb =
    Rasterize.to_framebuffer
      [
        N88basic.Display.Screen
          { mode = Some 3; switch = None; active = None; display = None };
        N88basic.Display.Width (80, Some 25);
        N88basic.Display.Locate { column = 1; row = Some 1; cursor = None };
        N88basic.Display.Key { number = None; action = N88basic.Display.Key_off };
      ]
  in
  check_pixel "still blank" fb ~x:0 ~y:0 black

(* ------------------------------------------------------------ PSET/PRESET *)

let pset ?colour point : N88basic.Display.op = N88basic.Display.Pset { point; colour }
let preset ?colour point : N88basic.Display.op = N88basic.Display.Preset { point; colour }
let colour4 = (0, (255, 0)) (* palette 4: green, per raster/palette.ml *)

let test_pset_paints_one_pixel () =
  let fb = Rasterize.to_framebuffer [ pset ~colour:4 (N88basic.Display.Abs (100., 100.)) ] in
  check_pixel "the pixel" fb ~x:100 ~y:100 colour4;
  check_pixel "its neighbour, untouched" fb ~x:101 ~y:100 black

(* PSET with no colour uses the current foreground (white until COLOR
   changes it) — ref-9801 printed p.130. *)
let test_pset_without_a_colour_uses_the_foreground () =
  let fb = Rasterize.to_framebuffer [ pset (N88basic.Display.Abs (5., 5.)) ] in
  check_pixel "default foreground" fb ~x:5 ~y:5 white

(* PRESET with no colour paints the *background* (black until COLOR changes
   it) — ref-9801 printed p.124 is explicit that this, not erasure to a
   fixed colour, is what PRESET without a palette number does. Pinned
   against a pixel PSET lit first, so a PRESET that wrongly no-ops or wrongly
   uses the foreground both fail this. *)
let test_preset_without_a_colour_paints_the_background () =
  let fb =
    Rasterize.to_framebuffer
      [
        pset ~colour:4 (N88basic.Display.Abs (10., 10.));
        preset (N88basic.Display.Abs (10., 10.));
      ]
  in
  check_pixel "painted over with the background" fb ~x:10 ~y:10 black

(* PRESET *with* a colour behaves exactly like PSET (ref-9801 printed
   p.124), not like an erase — it paints that colour, not the background. *)
let test_preset_with_a_colour_behaves_like_pset () =
  let fb = Rasterize.to_framebuffer [ preset ~colour:4 (N88basic.Display.Abs (10., 10.)) ] in
  check_pixel "painted the given colour" fb ~x:10 ~y:10 colour4

(* STEP(dx,dy) is relative to the LP, which PSET and PRESET both move to the
   point they just touched (ref-9801 printed p.122, p.130, p.124). *)
let test_pset_step_is_relative_to_the_lp () =
  let fb =
    Rasterize.to_framebuffer
      [
        pset ~colour:7 (N88basic.Display.Abs (50., 60.));
        pset ~colour:4 (N88basic.Display.Step (5., -10.));
      ]
  in
  check_pixel "first point" fb ~x:50 ~y:60 white;
  check_pixel "second point, relative to the first" fb ~x:55 ~y:50 colour4

(* LINE's own current-point rule (test_current_point_continues, above) and
   PSET/PRESET's LP share the same running point in the rasteriser: a LINE
   moves it too, so a STEP after one is relative to where the LINE ended. *)
let test_step_after_a_line_is_relative_to_its_endpoint () =
  let fb =
    Rasterize.to_framebuffer
      [
        line ~from_point:(0., 0.) ~colour:7 (30., 20.);
        pset ~colour:4 (N88basic.Display.Step (2., 0.));
      ]
  in
  check_pixel "relative to LINE's endpoint, not the origin" fb ~x:32 ~y:20 colour4

(* ------------------------------------------------------------------ COLOR *)

let color ?background ?foreground () : N88basic.Display.op =
  N88basic.Display.Color { function_code = None; background; border = None; foreground }

(* COLOR's foreground slot is what PSET (and LINE) fall back to when no
   colour argument is given; COLOR's background slot is what PRESET falls
   back to (ref-9801 printed p.49, p.130, p.124). *)
let test_color_changes_the_defaults_pset_and_preset_use () =
  let fb =
    Rasterize.to_framebuffer
      [
        color ~foreground:4 ~background:4 ();
        pset (N88basic.Display.Abs (1., 1.));
        preset (N88basic.Display.Abs (2., 2.));
      ]
  in
  check_pixel "PSET now defaults to the new foreground" fb ~x:1 ~y:1 colour4;
  check_pixel "PRESET now defaults to the new background" fb ~x:2 ~y:2 colour4

(* A slot COLOR leaves unset (background here) keeps its previous value
   rather than resetting to the startup default. *)
let test_color_leaves_unset_slots_alone () =
  let fb =
    Rasterize.to_framebuffer
      [
        color ~foreground:4 ();
        preset (N88basic.Display.Abs (3., 3.));
      ]
  in
  check_pixel "background untouched by a COLOR that didn't mention it" fb ~x:3 ~y:3 black

let test_determinism () =
  let ops =
    [
      N88basic.Display.Cls 3;
      line ~from_point:(10., 10.) ~colour:7 (300., 200.);
      line ~colour:5 ~box:`Frame (320., 40.);
      line ~from_point:(100., 300.) ~colour:3 ~box:`Filled (200., 380.);
    ]
  in
  let bytes_of fb =
    let b = Buffer.create (Framebuffer.width * Framebuffer.height * 3) in
    for y = 0 to Framebuffer.height - 1 do
      for x = 0 to Framebuffer.width - 1 do
        let r, g, bl = Framebuffer.rgb_at fb ~x ~y in
        Buffer.add_char b (Char.chr r);
        Buffer.add_char b (Char.chr g);
        Buffer.add_char b (Char.chr bl)
      done
    done;
    Buffer.contents b
  in
  let a = bytes_of (Rasterize.to_framebuffer ops) in
  let b = bytes_of (Rasterize.to_framebuffer ops) in
  Alcotest.(check bool) "identical bytes on repeated rasterisation" true
    (String.equal a b)

(* ref-9801 printed p.122's own worked equivalence, checked over the WHOLE
   framebuffer rather than at sampled points:

     ex1) LINE(-200,30)-(100,120),3
     ex2) POINT(-200,30) : LINE -STEP(300,90),3

   "例1と例2は、まったく同じ図形を描きます" -- they draw exactly the same
   figure. The manual's literal coordinates are used, negatives and all, so
   this also pins that the equivalence survives clipping.

   The distinguishing input is the STEP: if the POINT statement failed to
   move the LP, ex2's line would start from raster/'s default (0,0) and the
   two frames would differ. Verified by making Point_lp a no-op, which turns
   this test red. *)
let frame_bytes fb =
  let b = Buffer.create (Framebuffer.width * Framebuffer.height * 3) in
  for y = 0 to Framebuffer.height - 1 do
    for x = 0 to Framebuffer.width - 1 do
      let r, g, bl = Framebuffer.rgb_at fb ~x ~y in
      Buffer.add_char b (Char.chr r);
      Buffer.add_char b (Char.chr g);
      Buffer.add_char b (Char.chr bl)
    done
  done;
  Buffer.contents b

let test_point_statement_matches_the_manuals_equivalent_line () =
  let ex1 = [ line ~from_point:(-200., 30.) ~colour:3 (100., 120.) ] in
  let ex2 =
    [
      N88basic.Display.Point_lp { point = N88basic.Display.Abs (-200., 30.) };
      N88basic.Display.Line
        { from_point = None; to_point = N88basic.Display.Step (300., 90.);
          colour = Some 3; box = `None; style = None; fill = None };
    ]
  in
  Alcotest.(check bool) "ex1 and ex2 draw exactly the same figure" true
    (String.equal
       (frame_bytes (Rasterize.to_framebuffer ex1))
       (frame_bytes (Rasterize.to_framebuffer ex2)))

(* A wrong STEP must NOT match, or the test above would pass for a rasteriser
   that drew nothing at all in either case. *)
let test_a_wrong_step_does_not_match () =
  let ex1 = [ line ~from_point:(-200., 30.) ~colour:3 (100., 120.) ] in
  let wrong =
    [
      N88basic.Display.Point_lp { point = N88basic.Display.Abs (-200., 30.) };
      N88basic.Display.Line
        { from_point = None; to_point = N88basic.Display.Step (300., 91.);
          colour = Some 3; box = `None; style = None; fill = None };
    ]
  in
  Alcotest.(check bool) "a one-pixel-different STEP draws a different figure" false
    (String.equal
       (frame_bytes (Rasterize.to_framebuffer ex1))
       (frame_bytes (Rasterize.to_framebuffer wrong)))

let () =
  Alcotest.run "raster geometry"
    [
      ( "lines",
        [
          Alcotest.test_case "horizontal" `Quick test_horizontal_line;
          Alcotest.test_case "vertical" `Quick test_vertical_line;
          Alcotest.test_case "diagonal" `Quick test_diagonal_line;
        ] );
      ( "box",
        [
          Alcotest.test_case "frame ,B" `Quick test_frame_box;
          Alcotest.test_case "filled ,BF" `Quick test_filled_box;
        ] );
      ( "POINT statement",
        [
          Alcotest.test_case "matches the manual's equivalent LINE" `Quick
            test_point_statement_matches_the_manuals_equivalent_line;
          Alcotest.test_case "a wrong STEP does not match" `Quick
            test_a_wrong_step_does_not_match;
        ] );
      ( "clipping",
        [
          Alcotest.test_case "line off every edge" `Quick
            test_clip_off_every_edge;
          Alcotest.test_case "filled box entirely off-screen" `Quick
            test_clip_box_entirely_off_screen;
        ] );
      ( "state",
        [
          Alcotest.test_case "current point continues" `Quick
            test_current_point_continues;
          Alcotest.test_case "CLS 1 leaves the picture alone" `Quick
            test_cls_1_leaves_the_picture_alone;
          Alcotest.test_case "CLS 2 and CLS 3 clear the graphics screen" `Quick
            test_cls_2_and_3_clear_the_graphics_screen;
          Alcotest.test_case "CLS clears in the background colour, LP to (0,0)"
            `Quick test_cls_clears_in_the_background_colour_and_resets_the_lp;
          Alcotest.test_case "LOCATE / KEY OFF ignored, not crashed" `Quick
            test_locate_and_key_off_ignored;
        ] );
      ( "pset/preset",
        [
          Alcotest.test_case "paints one pixel" `Quick test_pset_paints_one_pixel;
          Alcotest.test_case "PSET defaults to the foreground" `Quick
            test_pset_without_a_colour_uses_the_foreground;
          Alcotest.test_case "PRESET defaults to the background" `Quick
            test_preset_without_a_colour_paints_the_background;
          Alcotest.test_case "PRESET with a colour behaves like PSET" `Quick
            test_preset_with_a_colour_behaves_like_pset;
          Alcotest.test_case "PSET STEP is relative to the LP" `Quick
            test_pset_step_is_relative_to_the_lp;
          Alcotest.test_case "STEP after LINE is relative to its endpoint" `Quick
            test_step_after_a_line_is_relative_to_its_endpoint;
        ] );
      ( "color",
        [
          Alcotest.test_case "changes PSET/PRESET's defaults" `Quick
            test_color_changes_the_defaults_pset_and_preset_use;
          Alcotest.test_case "leaves unset slots alone" `Quick
            test_color_leaves_unset_slots_alone;
        ] );
      ( "determinism",
        [ Alcotest.test_case "same list, same bytes" `Quick test_determinism ]
      );
    ]
