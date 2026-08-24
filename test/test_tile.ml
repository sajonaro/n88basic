(* Tile-string decoding, tested against the worked example the manual gives
   for it (ref-9801 printed p.119 / PDF p.130). The example is the whole
   point of these tests: a tile string's meaning is a bit-plane convention
   with two easy things to get backwards -- which end of a byte is the
   leftmost dot, and which of the three characters is the low plane -- and
   the manual settles both by printing the answer. *)

open N88basic

let palette_row (t : Tile.t) (row : int) : int list =
  List.init Tile.width (fun x -> Tile.palette_at t ~x ~y:row)

let decode_exn (s : string) : Tile.t =
  match Tile.decode s with
  | Some t -> t
  | None -> Alcotest.fail "tile string should have decoded"

(* The manual's own table, printed p.119:

       dot        1 2 3 4 5 6 7 8
       &HAA       1 0 1 0 1 0 1 0   <- 2^0
       &H55       0 1 0 1 0 1 0 1   <- 2^1
       &HFF       1 1 1 1 1 1 1 1   <- 2^2
       palette    5 6 5 6 5 6 5 6

   It pins the bit order and the plane order together: read the other way
   round on either axis and the row comes out as something else. *)
let test_manual_worked_example () =
  let t = decode_exn "\xAA\x55\xFF" in
  Alcotest.(check int) "one row" 1 (Tile.height t);
  Alcotest.(check (list int))
    "the manual's palette row" [ 5; 6; 5; 6; 5; 6; 5; 6 ] (palette_row t 0)

(* The manual notes that with the palette in its startup state this example
   alternates light blue and yellow, which is palette 5 and palette 6 in the
   order printed p.49 gives. That is a second, independent statement about
   the same row, so it is worth asserting as its own case rather than
   folding into the one above. *)
let test_manual_example_is_light_blue_and_yellow () =
  let t = decode_exn "\xAA\x55\xFF" in
  Alcotest.(check int) "first dot is light blue" 5 (Tile.palette_at t ~x:0 ~y:0);
  Alcotest.(check int) "second dot is yellow" 6 (Tile.palette_at t ~x:1 ~y:0)

(* Three characters are one row, so nine are three rows -- the tile's height
   is the string's length divided by three, not its length. *)
let test_height_is_the_row_count () =
  Alcotest.(check int) "three rows" 3 (Tile.height (decode_exn (String.make 9 '\x00')));
  Alcotest.(check int) "one row" 1 (Tile.height (decode_exn (String.make 3 '\xFF')))

(* All planes clear is palette 0, all planes set is palette 7: the two ends
   of the three-bit number the planes spell out. *)
let test_plane_extremes () =
  let dark = decode_exn "\x00\x00\x00" and lit = decode_exn "\xFF\xFF\xFF" in
  Alcotest.(check (list int)) "no planes set" [ 0; 0; 0; 0; 0; 0; 0; 0 ] (palette_row dark 0);
  Alcotest.(check (list int)) "every plane set" [ 7; 7; 7; 7; 7; 7; 7; 7 ] (palette_row lit 0)

(* Only the low plane set gives palette 1, only the middle 2, only the high
   4 -- which is the plane order stated as three separate facts, so that a
   transposition of any two shows up here and not only in the combined
   example above. *)
let test_plane_order () =
  Alcotest.(check int) "first character is the 1s" 1 (Tile.palette_at (decode_exn "\xFF\x00\x00") ~x:0 ~y:0);
  Alcotest.(check int) "second character is the 2s" 2 (Tile.palette_at (decode_exn "\x00\xFF\x00") ~x:0 ~y:0);
  Alcotest.(check int) "third character is the 4s" 4 (Tile.palette_at (decode_exn "\x00\x00\xFF") ~x:0 ~y:0)

(* Bit 7 is the leftmost dot. &H80 sets only that bit, so only dot 0 lights;
   &H01 sets only bit 0, so only dot 7 does. *)
let test_bit_order_within_a_byte () =
  let left = decode_exn "\x80\x00\x00" and right = decode_exn "\x01\x00\x00" in
  Alcotest.(check (list int)) "high bit is the leftmost dot"
    [ 1; 0; 0; 0; 0; 0; 0; 0 ] (palette_row left 0);
  Alcotest.(check (list int)) "low bit is the rightmost dot"
    [ 0; 0; 0; 0; 0; 0; 0; 1 ] (palette_row right 0)

(* Characters left over at the end, when the length is not a multiple of
   three, are ignored -- the manual says so outright, and says which end. *)
let test_trailing_characters_are_ignored () =
  let t = decode_exn "\xAA\x55\xFF\xFF\xFF" in
  Alcotest.(check int) "the two spare characters make no second row" 1 (Tile.height t);
  Alcotest.(check (list int)) "the first row is unaffected"
    [ 5; 6; 5; 6; 5; 6; 5; 6 ] (palette_row t 0)

(* Shorter than one row's worth is not a tile at all. [decode] answers None
   rather than raising, the "Illegal function call" the manual names being
   the caller's to raise. *)
let test_too_short_is_no_tile () =
  Alcotest.(check bool) "two characters" true (Tile.decode "\xAA\x55" = None);
  Alcotest.(check bool) "empty string" true (Tile.decode "" = None)

(* The pattern repeats from the screen origin, in both axes, so a coordinate
   eight dots to the right or one tile-height down reads the same dot. *)
let test_pattern_repeats () =
  let t = decode_exn "\xAA\x55\xFF\x00\x00\x00" in
  Alcotest.(check int) "eight dots right repeats"
    (Tile.palette_at t ~x:0 ~y:0) (Tile.palette_at t ~x:8 ~y:0);
  Alcotest.(check int) "two rows down repeats"
    (Tile.palette_at t ~x:3 ~y:0) (Tile.palette_at t ~x:3 ~y:2);
  Alcotest.(check int) "the second row is its own pattern" 0 (Tile.palette_at t ~x:0 ~y:1)

let () =
  Alcotest.run "tile"
    [ ( "decode",
        [ Alcotest.test_case "the manual's worked example" `Quick test_manual_worked_example;
          Alcotest.test_case "light blue and yellow" `Quick
            test_manual_example_is_light_blue_and_yellow;
          Alcotest.test_case "height is the row count" `Quick test_height_is_the_row_count;
          Alcotest.test_case "plane extremes" `Quick test_plane_extremes;
          Alcotest.test_case "plane order" `Quick test_plane_order;
          Alcotest.test_case "bit order within a byte" `Quick test_bit_order_within_a_byte;
          Alcotest.test_case "trailing characters ignored" `Quick
            test_trailing_characters_are_ignored;
          Alcotest.test_case "too short is no tile" `Quick test_too_short_is_no_tile;
          Alcotest.test_case "pattern repeats" `Quick test_pattern_repeats ] );
    ]
