(* [2] COLOR's indirection: what a palette number *displays* is decided when
   the picture is written, not when the dot is drawn.

   WHY THIS SUITE EXISTS SEPARATELY FROM THE CONFORMANCE CASE. The language
   cannot observe this rule. GFX.POINT reports the palette number a pixel was
   drawn through, and reassigning a palette does not change that number — so
   a .bas case, which can only assert on printed output, can pin that POINT
   stays put but can never see the colour move. The colour is visible only in
   the rendered frame, which makes this an OCaml test reading pixels back
   through Framebuffer.rgb_at.

   THE DISTINGUISHING INPUT, named before the tests were written because a
   suite that never supplies one is silent rather than reassuring: a pixel
   drawn BEFORE the palette moved, whose displayed colour differs after. If
   the rasteriser resolved a colour at draw time, that pixel keeps its old
   colour and every test below still passes on appearance alone unless it
   checks that specific pixel. So each test here draws first and reassigns
   second, which is the order that tells the two designs apart.

   The scenario is book intro-8801 printed p.119's own demonstration: draw a
   dot through palette 0 while palette 0 shows white, reassign palette 0 to
   blue, and the dot already on the screen turns blue. *)

let ops (l : N88basic.Display.op list) : Raster.Framebuffer.t = Raster.Rasterize.to_framebuffer l
let abs x y = N88basic.Display.Abs (float_of_int x, float_of_int y)
let pset ~x ~y ~colour = N88basic.Display.Pset { point = abs x y; colour = Some colour }
let assign ~palette ~code = N88basic.Display.Color_palette { palette; code }

let rgb = Alcotest.(triple int int int)
let white = Raster.Palette.to_rgb 7
let blue = Raster.Palette.to_rgb 1
let red = Raster.Palette.to_rgb 2

(* The p.119 demonstration itself. Palette 0 starts showing colour code 0
   (black), so it is given white first, a dot is drawn through it, and only
   then is it moved to blue. *)
let test_reassigning_recolours_a_dot_already_drawn () =
  let fb =
    ops [ assign ~palette:0 ~code:7; pset ~x:10 ~y:10 ~colour:0; assign ~palette:0 ~code:1 ]
  in
  Alcotest.check rgb "the dot drawn through palette 0 now shows blue" blue
    (Raster.Framebuffer.rgb_at fb ~x:10 ~y:10)

(* The same buffer, asked the other way: the pixel's palette number is
   unchanged, which is what GFX.POINT reports. Both halves matter — a
   rasteriser that rewrote the stored pixels would pass the test above and
   fail this one, and it would be wrong, because POINT must keep answering 0. *)
let test_reassigning_leaves_the_stored_palette_number_alone () =
  let fb =
    ops [ assign ~palette:0 ~code:7; pset ~x:10 ~y:10 ~colour:0; assign ~palette:0 ~code:1 ]
  in
  Alcotest.(check int)
    "POINT still reports the palette the dot was drawn through" 0
    (Raster.Framebuffer.get_pixel fb ~x:10 ~y:10)

(* Two dots drawn through DIFFERENT palette numbers that happen to show the
   same colour code separate again when one of the palettes moves. This is
   the case an RGB buffer could not represent at all: both dots were the same
   three bytes, so nothing distinguished them. *)
let test_two_palettes_sharing_a_code_separate_when_one_moves () =
  let fb =
    ops
      [
        assign ~palette:3 ~code:7;
        assign ~palette:5 ~code:7;
        pset ~x:1 ~y:1 ~colour:3;
        pset ~x:2 ~y:1 ~colour:5;
        assign ~palette:5 ~code:2;
      ]
  in
  Alcotest.check rgb "the dot through palette 3 is still white" white
    (Raster.Framebuffer.rgb_at fb ~x:1 ~y:1);
  Alcotest.check rgb "the dot through palette 5 became red" red
    (Raster.Framebuffer.rgb_at fb ~x:2 ~y:1)

(* Only the LAST assignment counts, because the palette is a display-time
   lookup rather than a running log: a program that moves one palette twice
   shows the second colour everywhere, including on dots drawn between the
   two assignments.

   The final mapping here is deliberately NOT the identity. An earlier draft
   ended with palette 1 back on code 1, and that version passed even with the
   indirection ripped out -- because "palette 1 shows blue" is what an
   implementation ignoring the palette says too. Ending on red is what makes
   the assertion mean something. *)
let test_the_last_assignment_wins_for_every_dot () =
  let fb =
    ops
      [
        assign ~palette:1 ~code:7;
        pset ~x:1 ~y:1 ~colour:1;
        assign ~palette:1 ~code:1;
        pset ~x:2 ~y:1 ~colour:1;
        assign ~palette:1 ~code:2;
      ]
  in
  Alcotest.check rgb "the dot drawn first shows the final colour" red
    (Raster.Framebuffer.rgb_at fb ~x:1 ~y:1);
  Alcotest.check rgb "so does the dot drawn between the assignments" red
    (Raster.Framebuffer.rgb_at fb ~x:2 ~y:1)

(* Bare COLOR puts the mapping back, so a dot drawn through a moved palette
   returns to the colour its number names. This is the form every listing in
   the book's chapter 4 uses (intro-8801 printed pp.114, 120, 129).

   Asserting only the restored colour would be silent: "palette 1 shows blue"
   is also what an implementation with no palette at all reports. So the same
   op list is rendered twice, with and without the reset, and the test pins
   the DIFFERENCE -- which no palette-free implementation can produce. *)
let test_bare_color_restores_the_startup_mapping () =
  let moved = [ assign ~palette:1 ~code:2; pset ~x:1 ~y:1 ~colour:1 ] in
  Alcotest.check rgb "without the reset, palette 1 still shows red" red
    (Raster.Framebuffer.rgb_at (ops moved) ~x:1 ~y:1);
  Alcotest.check rgb "after bare COLOR, palette 1 shows colour 1 again" blue
    (Raster.Framebuffer.rgb_at (ops (moved @ [ N88basic.Display.Color_palette_init ])) ~x:1 ~y:1)

(* An untouched palette still shows its own number's colour: the startup
   mapping is the identity, which is why palette numbers and colour numbers
   look interchangeable until something moves one. *)
let test_startup_mapping_is_the_identity () =
  let fb = ops [ pset ~x:1 ~y:1 ~colour:2 ] in
  Alcotest.check rgb "palette 2 shows colour 2" red (Raster.Framebuffer.rgb_at fb ~x:1 ~y:1)

let () =
  Alcotest.run "palette indirection"
    [
      ( "reassignment",
        [
          Alcotest.test_case "recolours a dot already drawn" `Quick
            test_reassigning_recolours_a_dot_already_drawn;
          Alcotest.test_case "leaves the stored palette number alone" `Quick
            test_reassigning_leaves_the_stored_palette_number_alone;
          Alcotest.test_case "two palettes sharing a code separate" `Quick
            test_two_palettes_sharing_a_code_separate_when_one_moves;
          Alcotest.test_case "the last assignment wins" `Quick
            test_the_last_assignment_wins_for_every_dot;
        ] );
      ( "initial state",
        [
          Alcotest.test_case "bare COLOR restores the startup mapping" `Quick
            test_bare_color_restores_the_startup_mapping;
          Alcotest.test_case "startup mapping is the identity" `Quick
            test_startup_mapping_is_the_identity;
        ] );
    ]
