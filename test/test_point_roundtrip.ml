(* POINT(x,y) crosses the one boundary this project's graphics deliberately
   keeps one-way everywhere else: the interpreter reads pixel state back
   rather than only recording it. basic/interp.ml's [on_point] is the
   opening — a caller-supplied [float -> float -> int], the same shape as
   [input] — and basic/ never sees a Framebuffer or a Palette through it.
   This test plays the caller: it wires [on_point] the way bin/main.ml does,
   by rasterising the display list recorded so far and reading one pixel
   back, and checks the whole chain — PSET, PRESET, the palette, and POINT's
   own -1-outside-the-viewport rule (ref-9801 printed p.123) — end to end.

   The read is now a direct one. It used to go through
   Palette.index_of_rgb, a reverse lookup from an RGB triple back to the
   palette number that produced it, which was exact only because colours are
   never blended. The framebuffer stores palette numbers since [2] COLOR
   landed, so there is nothing to invert. What POINT reports is unchanged:
   the palette a dot was drawn THROUGH, not the colour it currently shows —
   see test/test_palette_indirection.ml, which pins that those two came
   apart. *)

open Raster

let on_point (ops : N88basic.Display.op list ref) (x : float) (y : float) : int =
  let fb = Rasterize.to_framebuffer (List.rev !ops) in
  let xi = int_of_float (Float.round x) and yi = int_of_float (Float.round y) in
  if Framebuffer.in_bounds ~x:xi ~y:yi then
    Framebuffer.get_pixel fb ~x:xi ~y:yi
  else -1

let run source =
  let ops = ref [] in
  let buf = Buffer.create 64 in
  match
    N88basic.Interp.run_source
      ~on_draw:(fun op -> ops := op :: !ops)
      ~on_point:(on_point ops) ~write:(Buffer.add_string buf) source
  with
  | Ok () -> Buffer.contents buf
  | Error e -> Alcotest.fail (N88basic.Error.to_string e)

let check name expected source = Alcotest.(check string) name expected (run source)

let test_point_reads_back_a_pixel_pset_drew () =
  check "PSET then POINT" " 4 \n"
    "10 PSET (100,100),4\n20 PRINT POINT(100,100)\n30 END\n"

let test_point_on_an_untouched_pixel_is_black () =
  (* Never drawn is palette 0 (black), the framebuffer's own cleared state —
     distinct from -1, which POINT reserves for outside the viewport. *)
  check "untouched pixel" " 0 \n" "10 PRINT POINT(50,50)\n20 END\n"

let test_point_outside_the_viewport_is_minus_one () =
  check "off the 640x400 buffer" "-1 \n" "10 PRINT POINT(9999,9999)\n20 END\n"

let test_point_after_preset_reads_the_background () =
  check "PSET then PRESET then POINT" " 0 \n"
    "10 PSET (10,10),4\n20 PRESET (10,10)\n30 PRINT POINT(10,10)\n40 END\n"

let () =
  Alcotest.run "point round-trip"
    [
      ( "on_point via raster/",
        [
          Alcotest.test_case "reads back what PSET drew" `Quick
            test_point_reads_back_a_pixel_pset_drew;
          Alcotest.test_case "untouched pixel is palette 0" `Quick
            test_point_on_an_untouched_pixel_is_black;
          Alcotest.test_case "outside the viewport is -1" `Quick
            test_point_outside_the_viewport_is_minus_one;
          Alcotest.test_case "after PRESET reads the background" `Quick
            test_point_after_preset_reads_the_background;
        ] );
    ]
