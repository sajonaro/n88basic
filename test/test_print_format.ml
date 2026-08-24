open N88basic

let fmt = Print_format.format_number

(* Single precision: fixed notation up to 6 significant digits, "E" exponent
   form beyond that (spec/spec.md NUM.DISPLAY; ref-9801 printed p.125 / PDF
   p.136). Every case here is unchanged from this module's pre-existing
   behaviour, now made explicit as what [Numtype.Single] does. *)
let single_cases =
  [ (0.0, " 0 ");
    (1.0, " 1 ");
    (-1.0, "-1 ");
    (42.0, " 42 ");
    (0.5, " .5 ");
    (-0.5, "-.5 ");
    (0.01, " .01 ");
    (0.0123456, " .0123456 ");
    (0.0999999, " .0999999 ");
    (0.012345, " .012345 ");
    (1.0 /. 3.0, " .333333 ");
    (123456.0, " 123456 ");
    (999999.4, " 999999 ");
    (999999.5, " 1E+06 ");
    (1234567.0, " 1.23457E+06 ");
    (0.001, " 1E-03 ");
    (-1234567.0, "-1.23457E+06 ")
  ]

(* Double precision: the identical rule at 16 significant digits, with "D"
   in place of "E" (same source as above, extended to double precision). *)
let double_cases =
  [ (0.0, " 0 ");
    (1.0, " 1 ");
    (-1.0, "-1 ");
    (1.0 /. 3.0, " .3333333333333333 ");
    (* 16 significant digits, still fixed *)
    (1234567890123456.0, " 1234567890123456 ");
    (* 17 digits overflows the 16-digit budget -> scientific *)
    (12345678901234567.0, " 1.234567890123457D+16 ");
    (0.001, " 1D-03 ");
    (0.01, " .01 ");
    (-12345678901234567.0, "-1.234567890123457D+16 ")
  ]

(* Integer: always fixed, never scientific -- every value in range fits
   comfortably within any digit budget (ref-9801 printed p.12 / PDF p.25:
   the whole type tops out at 32767). *)
let int_cases = [ (0.0, " 0 "); (1.0, " 1 "); (-1.0, "-1 "); (32767.0, " 32767 "); (-32768.0, "-32768 ") ]

(* THE INPUT THAT DISTINGUISHES, and which the tables above could not supply.
   [single_cases] already expected " .01 " for 0.01 and already passed, while
   PRINT .01 in an actual program produced " 1E-02 ". Both were true: the
   table hands OCaml's 0.01 -- a DOUBLE, and just above a hundredth -- to the
   single formatter, whereas a BASIC listing writing ".01" gets the
   single-precision value 0.00999999977, just BELOW it. The test could not
   see the bug because it never supplied a single-rounded value.

   The old decision compared that stored float against the literal 0.01 and
   so misfired at its own boundary. It now reads the RENDERED digits, which
   cannot round below a literal written in decimal. *)
let single_rounded (x : float) : float = Int32.float_of_bits (Int32.bits_of_float x)

let test_hundredth_written_in_a_listing () =
  Alcotest.(check string)
    "single-precision .01 stays in fixed form" " .01 "
    (fmt Numtype.Single (single_rounded 0.01));
  Alcotest.(check string)
    "and so does a negative one" "-.01 "
    (fmt Numtype.Single (single_rounded (-0.01)))

let test_format () =
  List.iter
    (fun (x, expected) ->
      Alcotest.(check string) (Printf.sprintf "single %g" x) expected (fmt Numtype.Single x))
    single_cases;
  List.iter
    (fun (x, expected) ->
      Alcotest.(check string) (Printf.sprintf "double %g" x) expected (fmt Numtype.Double x))
    double_cases;
  List.iter
    (fun (x, expected) ->
      Alcotest.(check string) (Printf.sprintf "int %g" x) expected (fmt Numtype.Int x))
    int_cases

let collect f =
  let buf = Buffer.create 64 in
  let w = Print_format.make (Buffer.add_string buf) in
  f w;
  Buffer.contents buf

let test_zones () =
  let out = collect (fun w ->
    Print_format.put w " 1 ";
    Print_format.tab_to_zone w;
    Print_format.put w " 2 ")
  in
  Alcotest.(check string) "comma jumps to column 14" " 1             2 " out

let test_column_resets_on_newline () =
  let w = Print_format.make ignore in
  Print_format.put w "abc";
  Print_format.newline w;
  Alcotest.(check int) "column reset" 0 (Print_format.column w)

(* --- the writer tracks WIDTH (ref-9801 printed p.125, p.158-159) --------- *)

let test_width_defaults_to_80 () =
  Alcotest.(check int) "80 columns before any WIDTH" 80
    (Print_format.width (Print_format.make ignore))

let test_set_width_is_read_back () =
  let w = Print_format.make ignore in
  Print_format.set_width w 40;
  Alcotest.(check int) "40 after WIDTH 40" 40 (Print_format.width w)

(* The PRINT entry's note says a number that would "run over onto the next
   line" is moved down first -- so running over is what the screen does by
   itself, and the writer has to do it too. *)
let test_put_wraps_at_the_width () =
  let buf = Buffer.create 32 in
  let w = Print_format.make ~width:10 (Buffer.add_string buf) in
  Print_format.put w "abcdefghijkl";
  Alcotest.(check string) "wrapped after ten columns" "abcdefghij\nkl" (Buffer.contents buf);
  Alcotest.(check int) "column continues on the new line" 2 (Print_format.column w);
  Alcotest.(check int) "and the row advanced" 1 (Print_format.row w)

(* The stated rule itself: a number too long for what is left of the line is
   written on a fresh line rather than split across the break. *)
let test_put_unbroken_moves_down_rather_than_splitting () =
  let buf = Buffer.create 32 in
  let w = Print_format.make ~width:10 (Buffer.add_string buf) in
  Print_format.put w "12345678";
  Print_format.put_unbroken w " 99 ";
  Alcotest.(check string) "moved down whole" "12345678\n 99 " (Buffer.contents buf)

let test_put_unbroken_stays_put_when_it_fits () =
  let buf = Buffer.create 32 in
  let w = Print_format.make ~width:10 (Buffer.add_string buf) in
  Print_format.put w "1234";
  Print_format.put_unbroken w "12345";
  Alcotest.(check string) "no break needed" "123412345" (Buffer.contents buf)

let using = Print_using.format

let test_using_width_and_alignment () =
  Alcotest.(check string) "8-wide right-justified"
    "  172.01" (using "#####.##" [ Value.Num (Numtype.Single, 172.0083) ])

let test_using_rounds_half_up () =
  Alcotest.(check string) "rounds, not truncates" "41.38"
    (using "##.##" [ Value.Num (Numtype.Single, 41.3849) ]);
  Alcotest.(check string) "half-up" "41.1" (using "##.#" [ Value.Num (Numtype.Single, 41.054) ])

let test_using_rounds_ties_away_from_even () =
  Alcotest.(check string) "2.5 rounds up" " 3" (using "##" [ Value.Num (Numtype.Single, 2.5) ]);
  Alcotest.(check string) "0.25 rounds up" "0.3" (using "#.#" [ Value.Num (Numtype.Single, 0.25) ]);
  Alcotest.(check string) "0.125 rounds up" "0.13" (using "#.##" [ Value.Num (Numtype.Single, 0.125) ])

let test_using_keeps_trailing_zero () =
  Alcotest.(check string) "keeps .0" "30.0" (using "##.#" [ Value.Num (Numtype.Single, 30.039) ])

let test_using_integer_field_right_justifies () =
  Alcotest.(check string) "right-justified" " 3000" (using "#####" [ Value.Num (Numtype.Single, 3000.0) ]);
  Alcotest.(check string) "zero" "    0" (using "#####" [ Value.Num (Numtype.Single, 0.0) ])

let test_using_literal_text_passes_through () =
  Alcotest.(check string) "literal" "X = 41.1 UNITS"
    (using "X = ##.# UNITS" [ Value.Num (Numtype.Single, 41.054) ])

let test_hash_in_text_is_a_field () =
  (* A single # inside prose is a one-digit field, so this string has TWO fields
     and consumes TWO arguments. *)
  Alcotest.(check string) "two fields" "GROUP 3 = 41.1"
    (using "GROUP # = ##.#" [ Value.Num (Numtype.Single, 3.0); Value.Num (Numtype.Single, 41.054) ])

(* More values than fields: the format string is used again from the start
   until the values run out. Dropping the tail would shorten a line of chapter
   output with nothing to say why. *)
let test_using_restarts_the_format_when_values_remain () =
  Alcotest.(check string) "three values through one field" "  1  2  3"
    (using "###" [ Value.Num (Numtype.Single, 1.0); Value.Num (Numtype.Single, 2.0); Value.Num (Numtype.Single, 3.0) ]);
  Alcotest.(check string) "the literal between fields comes with each pass" " 1  2  3 "
    (using "## " [ Value.Num (Numtype.Single, 1.0); Value.Num (Numtype.Single, 2.0); Value.Num (Numtype.Single, 3.0) ])

(* Fewer values than fields: output stops at the first field with nothing to
   put in it, rather than emitting the rest of the format around a field that
   silently vanished. *)
let test_using_stops_at_a_field_with_no_value () =
  Alcotest.(check string) "one value through two fields" " 1 "
    (using "## ##" [ Value.Num (Numtype.Single, 1.0) ]);
  Alcotest.(check string) "text after the starved field is not emitted" " 1 "
    (using "## ## UNITS" [ Value.Num (Numtype.Single, 1.0) ]);
  Alcotest.(check string) "no values at all" "" (using "###" [])

(* --- sign control (ref-9801 printed p.128 / PDF p.139) ------------------- *)

let num n = Value.Num (Numtype.Single, n)

let test_using_leading_plus_shows_the_sign_in_front () =
  Alcotest.(check string) "positive gets a +" "+ 42" (using "+###" [ num 42.0 ]);
  Alcotest.(check string) "negative gets a -" "- 42" (using "+###" [ num (-42.0) ])

let test_using_trailing_plus_shows_the_sign_behind () =
  Alcotest.(check string) "positive" " 42+" (using "###+" [ num 42.0 ]);
  Alcotest.(check string) "negative" " 42-" (using "###+" [ num (-42.0) ])

(* A trailing "-" marks negatives only; a positive leaves the column blank,
   which is what keeps a column of figures aligned. *)
let test_using_trailing_minus_marks_only_negatives () =
  Alcotest.(check string) "negative" " 42-" (using "###-" [ num (-42.0) ]);
  Alcotest.(check string) "positive leaves the column blank" " 42 " (using "###-" [ num 42.0 ])

(* "2個以上の + を並べた場合には、余分は…そのまま出力されます" -- with two in a
   row the one against the field signs it and the other is just a character. *)
let test_using_doubled_plus_prints_the_extra_literally () =
  Alcotest.(check string) "the outer + is literal" "++ 42" (using "++###" [ num 42.0 ])

(* The manual gives "-" a meaning only at the end, so a leading one is an
   ordinary character. *)
let test_using_leading_minus_is_literal () =
  Alcotest.(check string) "literal minus" "- 42" (using "-###" [ num 42.0 ])

(* --- fill and currency (ref-9801 printed p.129 / PDF p.140) -------------- *)

(* "**" reserves two digit positions of its own and fills whatever blank is
   left on the number's left with asterisks. *)
let test_using_asterisk_fill_pads_with_stars () =
  Alcotest.(check string) "three columns of fill" "***42" (using "**###" [ num 42.0 ]);
  Alcotest.(check string) "a full field needs no fill" "12345" (using "**###" [ num 12345.0 ])

(* The yen sign prints "immediately before the number", so it floats right
   against the digits rather than sitting at the field's left edge. The two
   "¥" reserve two columns, one of which the sign itself uses. *)
let test_using_yen_floats_against_the_number () =
  Alcotest.(check string) "padding stays outside the sign" "  \xc2\xa525"
    (using "\xc2\xa5\xc2\xa5###" [ num 25.0 ]);
  Alcotest.(check string) "a full field puts the sign at the edge" "\xc2\xa52500"
    (using "\xc2\xa5\xc2\xa5###" [ num 2500.0 ])

(* On the machine the yen sign IS 0x5C, the byte a modern keyboard types as a
   backslash, so a listing may spell the pair either way. *)
let test_using_yen_may_be_spelled_with_the_0x5c_byte () =
  Alcotest.(check string) "backslash spelling" "  \\25" (using "\\\\###" [ num 25.0 ])

(* "**¥" reserves three columns, one for the sign, and does both jobs. *)
let test_using_asterisk_yen_combines_both () =
  Alcotest.(check string) "stars then the sign against the digits" "***\xc2\xa542"
    (using "**\xc2\xa5###" [ num 42.0 ])

(* --- comma grouping (ref-9801 printed p.129 / PDF p.140) ----------------- *)

(* A "," among the "#" groups the integer part every three digits. It carries
   a column of its own, so "##,###" is a six-column field. *)
let test_using_comma_groups_the_integer_part () =
  Alcotest.(check string) "grouped" "12,345" (using "##,###" [ num 12345.0 ]);
  Alcotest.(check string) "a short number is still six columns wide" "   123"
    (using "##,###" [ num 123.0 ]);
  Alcotest.(check string) "two groups" "  1,234,567"
    (using "###,###,###" [ num 1234567.0 ])

let test_using_comma_groups_only_the_integer_part () =
  Alcotest.(check string) "the fraction is not grouped" "1,234.50"
    (using "#,###.##" [ num 1234.5 ])

(* Placed to the right of the point, the manual gives "," the opposite job: a
   comma at the end of the number, and no grouping at all. Falling out of the
   field and printing as an ordinary character is exactly that. *)
let test_using_comma_after_the_point_is_a_trailing_comma () =
  Alcotest.(check string) "trailing comma, no grouping" "1234.50,"
    (using "####.##," [ num 1234.5 ])

(* --- overflow and escaping (ref-9801 printed p.129 / PDF p.140) ---------- *)

(* A number too wide for its field is not truncated: it prints in full with a
   "%" immediately in front of it, so the line is visibly wrong rather than
   quietly wrong. *)
let test_using_overflow_marks_with_percent () =
  Alcotest.(check string) "too many digits" "%12345" (using "###" [ num 12345.0 ]);
  Alcotest.(check string) "a field that just fits is unmarked" "123" (using "###" [ num 123.0 ])

(* The manual calls out the case where it is the rounding that overflows. *)
let test_using_overflow_after_rounding_marks_too () =
  Alcotest.(check string) "99.96 rounds to 100.0 and no longer fits" "%100.0"
    (using "##.#" [ num 99.96 ])

let test_using_underscore_escapes_the_next_character () =
  Alcotest.(check string) "a literal hash and a literal at" "#@" (using "_#_@" []);
  Alcotest.(check string) "the escape only reaches one character" "#42"
    (using "_###" [ num 42.0 ])

(* --- exponential form (ref-9801 printed p.129 / PDF p.140) --------------- *)

(* The manual says only that "^^^^" after the digits switches the field to
   exponential form; the shape of the result is this interpreter's reading.
   The mantissa is normalised to fill the "#" before the point, and the four
   carets are the four columns "E+nn" occupies. *)
let test_using_carets_switch_to_exponential_form () =
  Alcotest.(check string) "two mantissa digits" "12.35E+01"
    (using "##.##^^^^" [ num 123.45 ]);
  Alcotest.(check string) "one mantissa digit" "1.234E+05"
    (using "#.###^^^^" [ num 123400.0 ])

let test_using_exponential_handles_a_negative_exponent () =
  Alcotest.(check string) "small numbers" "1.23E-03" (using "#.##^^^^" [ num 0.00123 ])

let test_using_exponential_of_zero () =
  Alcotest.(check string) "zero has no exponent to find" " 0.00E+00"
    (using "##.##^^^^" [ num 0.0 ])

(* Fewer than four carets is not the control sequence, so they stay text. *)
let test_using_three_carets_are_literal () =
  Alcotest.(check string) "literal carets" " 42^^^" (using "###^^^" [ num 42.0 ])

(* --- string fields (ref-9801 printed p.128 / PDF p.139) ------------------ *)

let str s = Value.Str s

let test_using_bang_takes_the_first_character () =
  Alcotest.(check string) "first character only" "B" (using "!" [ str "BOOKS" ]);
  Alcotest.(check string) "a one-character string is itself" "X" (using "!" [ str "X" ])

(* "& <n spaces> &" is a field of n+2 characters: the two ampersands count. *)
let test_using_ampersand_field_is_n_plus_2_wide () =
  Alcotest.(check string) "two spaces makes a 4-wide field" "AB  " (using "&  &" [ str "AB" ]);
  Alcotest.(check string) "adjacent ampersands make a 2-wide field" "XY" (using "&&" [ str "XYZ" ])

let test_using_ampersand_field_left_justifies_and_truncates () =
  Alcotest.(check string) "short strings are left-justified and padded" "AB   "
    (using "&   &" [ str "AB" ]);
  Alcotest.(check string) "long strings lose the excess" "ABCDE" (using "&   &" [ str "ABCDEFGH" ])

let test_using_at_takes_the_whole_string () =
  Alcotest.(check string) "whole string" "BOOKS" (using "@" [ str "BOOKS" ])

(* The manual states this one outright: when there are more "@" than values,
   the leftover "@" are ignored -- so output does NOT stop at one, unlike the
   numeric field below. *)
let test_using_extra_at_is_ignored_rather_than_stopping () =
  Alcotest.(check string) "the starved @ vanishes and the literal still prints" "A-"
    (using "@-@" [ str "A" ])

(* A format with no field cannot consume a value, so it is emitted once. This
   is what stops the restart above from looping forever. *)
let test_using_without_a_field_is_emitted_once () =
  Alcotest.(check string) "no field to consume a value" "NO FIELDS HERE"
    (using "NO FIELDS HERE" [ Value.Num (Numtype.Single, 1.0) ])

let () =
  Alcotest.run "print_format"
    [ ("numbers", [ Alcotest.test_case "format" `Quick test_format;
          Alcotest.test_case "a hundredth written in a listing" `Quick
            test_hundredth_written_in_a_listing ]);
      ("writer",
       [ Alcotest.test_case "zones" `Quick test_zones;
         Alcotest.test_case "newline" `Quick test_column_resets_on_newline;
         Alcotest.test_case "width defaults to 80" `Quick test_width_defaults_to_80;
         Alcotest.test_case "set_width reads back" `Quick test_set_width_is_read_back;
         Alcotest.test_case "put wraps at the width" `Quick test_put_wraps_at_the_width;
         Alcotest.test_case "an unbroken run moves down" `Quick
           test_put_unbroken_moves_down_rather_than_splitting;
         Alcotest.test_case "an unbroken run that fits stays put" `Quick
           test_put_unbroken_stays_put_when_it_fits ]);
      ("using",
       [ Alcotest.test_case "width and alignment" `Quick test_using_width_and_alignment;
         Alcotest.test_case "rounds half up" `Quick test_using_rounds_half_up;
         Alcotest.test_case "rounds ties away from even" `Quick
           test_using_rounds_ties_away_from_even;
         Alcotest.test_case "keeps trailing zero" `Quick test_using_keeps_trailing_zero;
         Alcotest.test_case "integer field right-justifies" `Quick
           test_using_integer_field_right_justifies;
         Alcotest.test_case "literal text passes through" `Quick
           test_using_literal_text_passes_through;
         Alcotest.test_case "hash in text is a field" `Quick test_hash_in_text_is_a_field;
         Alcotest.test_case "restarts for extra values" `Quick
           test_using_restarts_the_format_when_values_remain;
         Alcotest.test_case "stops at a starved field" `Quick
           test_using_stops_at_a_field_with_no_value;
         Alcotest.test_case "a format with no field is emitted once" `Quick
           test_using_without_a_field_is_emitted_once ]);
      ("using signs",
       [ Alcotest.test_case "leading + signs in front" `Quick
           test_using_leading_plus_shows_the_sign_in_front;
         Alcotest.test_case "trailing + signs behind" `Quick
           test_using_trailing_plus_shows_the_sign_behind;
         Alcotest.test_case "trailing - marks only negatives" `Quick
           test_using_trailing_minus_marks_only_negatives;
         Alcotest.test_case "a doubled + prints the extra literally" `Quick
           test_using_doubled_plus_prints_the_extra_literally;
         Alcotest.test_case "a leading - is literal" `Quick
           test_using_leading_minus_is_literal ]);
      ("using exponential",
       [ Alcotest.test_case "^^^^ switches to exponential form" `Quick
           test_using_carets_switch_to_exponential_form;
         Alcotest.test_case "a negative exponent" `Quick
           test_using_exponential_handles_a_negative_exponent;
         Alcotest.test_case "zero" `Quick test_using_exponential_of_zero;
         Alcotest.test_case "three carets are literal" `Quick
           test_using_three_carets_are_literal ]);
      ("using overflow",
       [ Alcotest.test_case "% marks an overflowing field" `Quick
           test_using_overflow_marks_with_percent;
         Alcotest.test_case "% marks an overflow caused by rounding" `Quick
           test_using_overflow_after_rounding_marks_too;
         Alcotest.test_case "_ escapes the next character" `Quick
           test_using_underscore_escapes_the_next_character ]);
      ("using commas",
       [ Alcotest.test_case "groups the integer part" `Quick
           test_using_comma_groups_the_integer_part;
         Alcotest.test_case "groups only the integer part" `Quick
           test_using_comma_groups_only_the_integer_part;
         Alcotest.test_case "a comma after the point trails the number" `Quick
           test_using_comma_after_the_point_is_a_trailing_comma ]);
      ("using fill",
       [ Alcotest.test_case "** fills with stars" `Quick
           test_using_asterisk_fill_pads_with_stars;
         Alcotest.test_case "yen floats against the number" `Quick
           test_using_yen_floats_against_the_number;
         Alcotest.test_case "yen may be spelled 0x5C" `Quick
           test_using_yen_may_be_spelled_with_the_0x5c_byte;
         Alcotest.test_case "**yen does both jobs" `Quick
           test_using_asterisk_yen_combines_both ]);
      ("using strings",
       [ Alcotest.test_case "! takes the first character" `Quick
           test_using_bang_takes_the_first_character;
         Alcotest.test_case "& field is n+2 wide" `Quick
           test_using_ampersand_field_is_n_plus_2_wide;
         Alcotest.test_case "& field left-justifies and truncates" `Quick
           test_using_ampersand_field_left_justifies_and_truncates;
         Alcotest.test_case "@ takes the whole string" `Quick
           test_using_at_takes_the_whole_string;
         Alcotest.test_case "an extra @ is ignored, not a full stop" `Quick
           test_using_extra_at_is_ignored_rather_than_stopping ]) ]
