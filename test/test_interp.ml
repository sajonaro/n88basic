open N88basic

(* Run a source string and return everything PRINT wrote. LPRINT, unless a
   separate sink is given, lands in the same buffer — the deliberate deviation
   from PRINT.LPRINT documented in Interp.run. *)
let run source =
  let buf = Buffer.create 128 in
  match Interp.run_source ~write:(Buffer.add_string buf) source with
  | Ok () -> Buffer.contents buf
  | Error e -> Alcotest.fail (Error.to_string e)

let check name expected source = Alcotest.(check string) name expected (run source)

(* Run a source string expected to fail, and return the error. *)
let run_expecting_failure name source =
  match Interp.run_source ~write:ignore source with
  | Ok () -> Alcotest.fail (Printf.sprintf "%s: expected an error" name)
  | Error e -> e

let check_failure name ~line ~message source =
  let e = run_expecting_failure name source in
  Alcotest.(check int) (name ^ ": line") line e.Error.line;
  Alcotest.(check string) (name ^ ": message") message e.Error.message

(* INPUT reads through a callback, so a test supplies the answers as a list and
   the interpreter draws them one at a time. Running out returns [None], which
   is a different case from an unparseable answer. *)
let answering answers =
  let remaining = ref answers in
  fun () ->
    match !remaining with
    | [] -> None
    | a :: rest ->
        remaining := rest;
        Some a

let run_answering answers source =
  let buf = Buffer.create 128 in
  match Interp.run_source ~input:(answering answers) ~write:(Buffer.add_string buf) source with
  | Ok () -> Buffer.contents buf
  | Error e -> Alcotest.fail (Error.to_string e)

let check_answering name answers expected source =
  Alcotest.(check string) name expected (run_answering answers source)

let check_answering_failure name answers ~line ~message source =
  match Interp.run_source ~input:(answering answers) ~write:ignore source with
  | Ok () -> Alcotest.fail (Printf.sprintf "%s: expected an error" name)
  | Error e ->
      Alcotest.(check int) (name ^ ": line") line e.Error.line;
      Alcotest.(check string) (name ^ ": message") message e.Error.message

(* ---------------------------------------------------------------- PRINT *)

let test_print_number () = check "print" " 1 \n" "10 PRINT 1\n20 END\n"

let test_print_string_has_no_padding () =
  check "string" "HI\n" "10 PRINT \"HI\"\n20 END\n"

let test_semicolon_packs () =
  check "semicolon" "A= 1 \n" "10 PRINT \"A=\"; 1\n20 END\n"

let test_comma_uses_zones () =
  check "comma" " 1             2 \n" "10 PRINT 1,2\n20 END\n"

let test_trailing_semicolon_suppresses_newline () =
  check "trailing" " 1 " "10 PRINT 1;\n20 END\n"

let test_trailing_comma_tabs_without_a_newline () =
  check "trailing comma" " 1            " "10 PRINT 1,\n20 END\n"

let test_bare_print_emits_a_newline () =
  check "bare PRINT" "A\n\n" "10 PRINT \"A\"\n20 PRINT\n30 END\n"

let test_tab_pads_to_a_one_based_column () =
  check "TAB" "    X\n" "10 PRINT TAB(5);\"X\"\n20 END\n"

let test_tab_behind_the_cursor_emits_nothing () =
  check "TAB behind" "ABCDEX\n" "10 PRINT \"ABCDE\";TAB(3);\"X\"\n20 END\n"

(* A non-positive TAB falls out of the same "never move backwards" rule and
   emits nothing. This is not yet confirmed against the manual (PRINT.TAB is
   unspecified evidence at this point) — the machine most likely rejects it —
   so this test pins what we actually do. *)
let test_a_non_positive_tab_emits_nothing () =
  check "TAB(0)" "XY\n" "10 PRINT \"X\";TAB(0);\"Y\"\n20 END\n"

let test_tab_at_the_end_of_a_list_still_breaks_the_line () =
  check "trailing TAB" "A   \n" "10 PRINT \"A\";TAB(5)\n20 END\n"

let test_lprint_goes_to_the_printer () =
  let screen = Buffer.create 32 and paper = Buffer.create 32 in
  (match
     Interp.run_source
       ~write:(Buffer.add_string screen)
       ~printer:(Buffer.add_string paper)
       "10 PRINT \"SCREEN\"\n20 LPRINT \"PAPER\"\n30 END\n"
   with
  | Ok () -> ()
  | Error e -> Alcotest.fail (Error.to_string e));
  Alcotest.(check string) "screen" "SCREEN\n" (Buffer.contents screen);
  Alcotest.(check string) "paper" "PAPER\n" (Buffer.contents paper)

let test_lprint_defaults_to_the_screen_sink () =
  check "merged" "PAPER\n" "10 LPRINT \"PAPER\"\n20 END\n"

(* The printer's print zones are counted from the printer's own column. A
   half-finished PRINT line on screen must not shift the paper. *)
let test_lprint_keeps_its_own_column () =
  let screen = Buffer.create 32 and paper = Buffer.create 32 in
  (match
     Interp.run_source
       ~write:(Buffer.add_string screen)
       ~printer:(Buffer.add_string paper)
       "10 PRINT \"ABC\";\n20 LPRINT 1,2\n30 END\n"
   with
  | Ok () -> ()
  | Error e -> Alcotest.fail (Error.to_string e));
  Alcotest.(check string) "screen" "ABC" (Buffer.contents screen);
  Alcotest.(check string) "paper" " 1             2 \n" (Buffer.contents paper)

(* ----------------------------------------------------------------- WRITE *)

(* Confirmed against ref-9801: WRITE always separates items with a comma on
   output, quotes strings, and drops the free-format padding PRINT gives
   numbers (no leading sign column, no trailing space). *)
let test_write_quotes_strings_and_commas_between_items () =
  check "quoting and separators" "\"HELLO\",42,-7\n" "10 WRITE \"HELLO\", 42, -7\n20 END\n"

(* "," and ";" are interchangeable as WRITE's own item separator -- the
   output is identical either way. *)
let test_write_treats_comma_and_semicolon_the_same () =
  check "; same as ," "1,2,3\n" "10 WRITE 1;2;3\n20 END\n"

let test_write_emits_a_trailing_newline () =
  check "newline" "1\n" "10 WRITE 1\n20 END\n"

(* A bare WRITE is not the form the manual's syntax box gives -- its first
   <expr> is not bracketed the way PRINT's items all are -- so it is a parse
   error, not a blank line. *)
let test_bare_write_is_a_parse_error () =
  check_failure "bare WRITE" ~line:10 ~message:"Unexpected end of line" "10 WRITE\n20 END\n"

(* ---------------------------------------------------------- PRINT USING *)

let test_print_using_formats_its_value () =
  check "USING" "  1.50\n" "10 PRINT USING \"###.##\";1.5\n20 END\n"

let test_print_using_takes_one_value_per_field () =
  check "two fields" " 1  2\n" "10 PRINT USING \"## ##\";1;2\n20 END\n"

(* The whole list becomes one formatted string, so the free-format leading and
   trailing spaces around a number are absent here. *)
let test_print_using_does_not_pad_like_free_format () =
  check "no free-format padding" "1\n" "10 PRINT USING \"#\";1\n20 END\n"

let test_print_using_trailing_semicolon_suppresses_the_newline () =
  check "no newline" "  1" "10 PRINT USING \"###\";1;\n20 END\n"

(* Confirmed: USING may follow a TAB(n); clause. The TAB has to position the
   writer before the formatted text lands, not be quietly filtered out of the
   item list on its way to the formatter. *)
let test_a_tab_before_using_positions_the_text () =
  check "TAB then USING"
    (String.make 12 ' ' ^ "1\n")
    "10 PRINT TAB(11);USING \"###\";1\n20 END\n"

(* USING renders every value as one string, so a TAB *after* a value has no
   position to take effect at. Refused rather than ignored. *)
let test_a_tab_after_a_value_in_a_using_list_is_refused () =
  check_failure "TAB after value" ~line:10
    ~message:"TAB after a value in a PRINT USING list"
    "10 PRINT USING \"###\";1;TAB(30)\n20 END\n"

(* Print_using rejects a string in a numeric field with an [Invalid_argument]
   that is not a BASIC error; the evaluator must not let it escape [run]. *)
let test_a_string_in_a_numeric_field_is_a_type_error () =
  check_failure "string in # field" ~line:10 ~message:"Type mismatch"
    "10 PRINT USING \"###\";\"A\"\n20 END\n"

(* A value list longer than the format's fields uses the format again from the
   start. Before this, everything past the first field was dropped — on the
   chapter's dominant numeric output path, where a short line is exactly what
   nobody would notice. *)
let test_print_using_reuses_the_format_for_extra_values () =
  check "restart" "  1  2  3\n" "10 PRINT USING \"###\";1;2;3\n20 END\n"

let test_lprint_using_reaches_the_printer () =
  let screen = Buffer.create 32 and paper = Buffer.create 32 in
  (match
     Interp.run_source
       ~write:(Buffer.add_string screen)
       ~printer:(Buffer.add_string paper)
       "10 LPRINT USING \"###\";7\n20 END\n"
   with
  | Ok () -> ()
  | Error e -> Alcotest.fail (Error.to_string e));
  Alcotest.(check string) "screen" "" (Buffer.contents screen);
  Alcotest.(check string) "paper" "  7\n" (Buffer.contents paper)

(* --------------------------------------------------------- expressions *)

let test_arithmetic_precedence () =
  check "precedence" " 7 \n" "10 PRINT 1+2*3\n20 END\n"

let test_power_and_unary_minus () =
  check "power" " 8 -4 \n" "10 PRINT 2^3;-(2*2)\n20 END\n"

let test_variables () =
  check "variables" " 6 \n" "10 A=2\n20 B=3\n30 PRINT A*B\n40 END\n"

let test_unset_variables_are_zero_and_empty () =
  check "defaults" " 0 [] \n" "10 PRINT Z;\"[\";Z$;\"] \"\n20 END\n"

let test_let_keyword_is_accepted () =
  check "LET" " 4 \n" "10 LET A=4\n20 PRINT A\n30 END\n"

let test_array_elements () =
  check "array" " 5  0 \n" "10 A(2)=5\n20 PRINT A(2);A(3)\n30 END\n"

let test_string_concatenation () =
  check "concat" "AB\n" "10 A$=\"A\"\n20 PRINT A$+\"B\"\n30 END\n"

let test_string_equality () =
  check "string compare" "-1  0 \n" "10 PRINT (\"A\"=\"A\");(\"A\"<>\"A\")\n20 END\n"

let test_comparison_yields_minus_one () =
  (* These dialects yield -1 for true and 0 for false. *)
  check "true is -1" "-1  0 \n" "10 PRINT (1=1);(1=2)\n20 END\n"

let test_relational_operators () =
  check "relations" "-1 -1 -1 -1 \n" "10 PRINT (1<2);(2>1);(1<=1);(1>=1)\n20 END\n"

let test_logical_operators () =
  check "logic" "-1  0 -1 \n" "10 PRINT (1=1 AND 2=2);(1=1 AND 1=2);NOT 0\n20 END\n"

let test_intrinsics () =
  check "intrinsics" " 2  1  3 -1 \n"
    "10 PRINT ABS(-2);INT(1.7);SQR(9);SGN(-5)\n20 END\n"

let test_division_by_zero () =
  check_failure "division" ~line:20 ~message:"Division by zero"
    "10 A=0\n20 PRINT 1/A\n30 END\n"

let test_type_mismatch () =
  check_failure "mismatch" ~line:10 ~message:"Type mismatch"
    "10 PRINT 1+\"A\"\n20 END\n"

(* Only = and <> are defined on strings in this dialect. *)
let test_ordering_strings_is_a_type_mismatch () =
  check_failure "string ordering" ~line:10 ~message:"Type mismatch"
    "10 PRINT \"A\"<\"B\"\n20 END\n"

let test_unknown_function () =
  check_failure "unknown function" ~line:10 ~message:"Undefined function FNA"
    "10 PRINT FNA(1)\n20 END\n"

(* Env raises subscript errors knowing neither the BASIC line nor the span;
   the evaluator must refill them from the node it was evaluating. *)
let test_subscript_error_carries_the_line () =
  check_failure "subscript" ~line:20 ~message:"Subscript out of range"
    "10 A(1)=1\n20 A(11)=1\n30 END\n"

(* ---------------------------------------------------------- numeric types *)

(* Integer's range is -32768..32767 (spec/spec.md NUM.TYPES; ref-9801
   printed p.12 / PDF p.25); both boundaries are valid, one past either is
   Overflow. *)
let test_integer_boundary_values_are_accepted () =
  check "boundary" " 32767 -32768 \n" "10 A%=32767\n20 B%=-32768\n30 PRINT A%;B%\n40 END\n"

let test_integer_assignment_overflow_above () =
  check_failure "overflow above" ~line:10 ~message:"Overflow (OV)" "10 A%=32768\n20 END\n"

let test_integer_assignment_overflow_below () =
  check_failure "overflow below" ~line:10 ~message:"Overflow (OV)" "10 A%=-32769\n20 END\n"

(* Assigning a fractional value to an integer variable rounds rather than
   truncates, ties away from zero (spec/spec.md NUM.COERCION; ref-9801
   printed p.18 / PDF p.31, rule 4). *)
let test_fractional_assignment_to_integer_rounds () =
  check "rounds" " 4  4 -4 \n" "10 A%=3.5\n20 B%=3.5001\n30 C%=-3.5\n40 PRINT A%;B%;C%\n50 END\n"

(* DEFINT makes a suffix-less name in its range integer; an explicit suffix
   on the name still overrides it (ref-9801 printed p.60 / PDF p.71). *)
let test_defint_makes_unsuffixed_names_integer () =
  check "DEFINT" " 4 \n" "10 DEFINT I-N\n20 I=3.5\n30 PRINT I\n40 END\n"

let test_explicit_suffix_overrides_defint () =
  check "suffix overrides DEFINT" " 3.5 \n" "10 DEFINT I-N\n20 I!=3.5\n30 PRINT I!\n40 END\n"

(* DEFSTR makes a suffix-less name a string variable, with no "$" required. *)
let test_defstr_makes_unsuffixed_names_strings () =
  check "DEFSTR" "HELLO\n" "10 DEFSTR L\n20 L=\"HELLO\"\n30 PRINT L\n40 END\n"

(* Mixed-precision arithmetic converts to the more precise operand
   (spec/spec.md NUM.COERCION; ref-9801 printed p.18 / PDF p.31, rule 2):
   an integer plus a double-precision value prints at double precision's own
   significant-digit budget, not the integer's. *)
let test_coercion_in_a_mixed_expression () =
  check "mixed precision" " 4.333333333333333 \n" "10 A%=4\n20 PRINT A%+1#/3#\n30 END\n"

(* "/" is always real-number division, even integer over integer (ref-9801
   printed p.19 / PDF p.32: the operator table calls "/" itself "real-number
   division"). *)
let test_division_of_two_integers_is_real () =
  check "int/int is real" " .5 \n" "10 PRINT 1/2\n20 END\n"

(* Single precision prints at up to 6 significant digits, switching to "E"
   exponent form beyond that; double precision does the same at 16 digits
   with "D" (spec/spec.md NUM.DISPLAY; ref-9801 printed p.125 / PDF p.136,
   extended to double precision as p.14 / PDF p.27 states its own digit
   budget). *)
let test_single_vs_double_significant_digits () =
  check "single vs double" " .333333  .3333333333333333 \n" "10 PRINT 1!/3!;1#/3#\n20 END\n"

let test_exponent_form_switches_both_directions () =
  check "large and small" " 1E+10  1.5E-08 \n" "10 PRINT 1E10;1.5E-8\n20 END\n"

(* A leading column for the sign (blank for non-negative, "-" for negative)
   and a trailing space follow every printed number regardless of its type
   (spec/spec.md NUM.DISPLAY; ref-9801 printed p.125 / PDF p.136). *)
let test_leading_and_trailing_space_by_sign () =
  check "sign spacing" " 5 -5 \n" "10 PRINT 5;-5\n20 END\n"

(* ------------------------------------------------------------- control *)

let test_goto_and_if () =
  check "loop via GOTO" " 1  2  3 \n"
    "10 I=1\n20 IF I>3 THEN 60\n30 PRINT I;\n40 I=I+1\n50 GOTO 20\n60 PRINT\n70 END\n"

let test_if_else () =
  check "ELSE" "F\n" "10 IF 0 THEN PRINT \"T\" ELSE PRINT \"F\"\n20 END\n"

let test_if_without_else_falls_through () =
  check "no ELSE" "AFTER\n" "10 IF 0 THEN PRINT \"T\"\n20 PRINT \"AFTER\"\n30 END\n"

(* Everything after THEN on the line belongs to the branch, so a jump inside it
   must abandon the statements that follow rather than run them on return. *)
let test_a_jump_abandons_the_rest_of_its_branch () =
  check "branch jump" "YES\n"
    "10 IF 1 THEN GOTO 30: PRINT \"NO\"\n20 END\n30 PRINT \"YES\"\n40 END\n"

let test_a_jump_from_the_else_branch_abandons_its_tail () =
  check "ELSE jump" "YES\n"
    "10 IF 0 THEN PRINT \"T\" ELSE GOTO 30: PRINT \"NO\"\n20 END\n30 PRINT \"YES\"\n\
     40 END\n"

(* The inner IF's jump has to abandon the OUTER branch's tail as well, not just
   its own: `PRINT "OUTER"` sits in the outer branch, two frames up. *)
let test_a_nested_jump_abandons_the_outer_branch_tail () =
  check "nested jump" "YES\n"
    "10 IF 1 THEN IF 1 THEN 30: PRINT \"OUTER\"\n20 END\n30 PRINT \"YES\"\n40 END\n"

(* END as a THEN target is a confirmed form of this dialect; halting must
   abandon the branch tail exactly as a jump does. *)
let test_end_inside_a_branch_abandons_its_tail () =
  check "END in branch" "" "10 IF 1 THEN END: PRINT \"NO\"\n20 END\n"

let test_colon_separates_statements () =
  check "colon" " 1 \n" "10 A=1: PRINT A\n20 END\n"

let test_rem_is_a_no_op () =
  check "REM" " 1 \n" "10 REM a note\n20 PRINT 1\n30 END\n"

let test_end_stops_before_later_lines () =
  check "END" "A\n" "10 PRINT \"A\"\n20 END\n30 PRINT \"B\"\n"

(* STOP names the line it stopped at on the way out, which is what
   distinguishes it from END here (ref-9801 printed p.147 / PDF p.158).
   This test expected silence until the page was read. *)
let test_stop_halts_and_names_its_line () =
  check "STOP" "A\nBreak in 20\n" "10 PRINT \"A\"\n20 STOP\n30 PRINT \"B\"\n"

let test_falls_off_end_without_END () = check "implicit stop" " 1 \n" "10 PRINT 1\n"

let test_lines_run_in_number_order_not_file_order () =
  check "sorted" "AB\n" "20 PRINT \"B\"\n10 PRINT \"A\";\n30 END\n"

let test_error_carries_line () =
  check_failure "GOTO" ~line:10 ~message:"Undefined line number" "10 GOTO 999\n"

(* A program that does not parse is not half-run. *)
let test_a_parse_error_refuses_to_run () =
  let e = run_expecting_failure "parse error" "10 PRINT \"A\"\n20 PRINT (\n" in
  Alcotest.(check int) "line" 20 e.Error.line

(* The whole point of threading spans through the evaluator is columns: the
   error must underline `1/0` and not the statement, the line, or nothing.
   Columns are 0-based and end_col is exclusive, so in "10 PRINT 1/0" the
   offending expression runs 9..12. *)
let test_runtime_errors_carry_a_span () =
  let e = run_expecting_failure "span" "10 PRINT 1/0\n" in
  match e.Error.span with
  | None -> Alcotest.fail "expected a span"
  | Some s ->
      Alcotest.(check int) "physical file line" 0 s.Span.line;
      Alcotest.(check int) "start_col" 9 s.Span.start_col;
      Alcotest.(check int) "end_col" 12 s.Span.end_col

(* GOTO's span is the target's digits alone — not the keyword, not the
   statement — which is the reason Ast.line_ref carries target_span. *)
let test_an_undefined_line_number_underlines_the_digits () =
  let e = run_expecting_failure "GOTO span" "10 GOTO 999\n" in
  match e.Error.span with
  | None -> Alcotest.fail "expected a span"
  | Some s ->
      Alcotest.(check int) "start_col" 8 s.Span.start_col;
      Alcotest.(check int) "end_col" 11 s.Span.end_col

(* The Program.t entry point. Every other case here goes through run_source;
   the chapter harness will want to parse once and run more than once, and a
   second run must start from a fresh environment rather than inherit the
   first's. *)
let test_run_takes_an_already_parsed_program () =
  let prog, errors = Program.of_source "10 A=A+1\n20 PRINT A\n30 END\n" in
  Alcotest.(check int) "no parse errors" 0 (List.length errors);
  let go () =
    let buf = Buffer.create 16 in
    match Interp.run ~write:(Buffer.add_string buf) prog with
    | Ok () -> Buffer.contents buf
    | Error e -> Alcotest.fail (Error.to_string e)
  in
  Alcotest.(check string) "first run" " 1 \n" (go ());
  Alcotest.(check string) "second run keeps the program, not the state" " 1 \n" (go ())

(* --------------------------------------------------- FOR/NEXT, GOSUB/RETURN *)

let test_for_loop () =
  check "counts" " 1  2  3 \n" "10 FOR I=1 TO 3\n20 PRINT I;\n30 NEXT I\n40 PRINT\n50 END\n"

let test_for_zero_iterations () =
  check "never enters" "DONE\n"
    "10 FOR I=1 TO 0\n20 PRINT \"IN\"\n30 NEXT I\n40 PRINT \"DONE\"\n50 END\n"

let test_for_negative_step () =
  check "counts down" " 3  2  1 \n"
    "10 FOR I=3 TO 1 STEP -1\n20 PRINT I;\n30 NEXT I\n40 PRINT\n50 END\n"

let test_for_fractional_step () =
  check "half steps" " 1  1.5  2 \n"
    "10 FOR V=1 TO 2 STEP .5\n20 PRINT V;\n30 NEXT V\n40 PRINT\n50 END\n"

(* A loop whose body is empty and whose NEXT sits on the FOR's own line: the
   jump target equals the counters already held, so only an explicit jump flag
   keeps this running three times instead of once. *)
let test_single_line_loop_with_empty_body () =
  check "empty body" " 3 \n" "10 FOR I=1 TO 3: NEXT I\n20 PRINT I-1\n30 END\n"

let test_nested_for () =
  check "nested" " 11  12  21  22  31  32 \n"
    "10 FOR I=1 TO 3\n20 FOR J=1 TO 2\n30 PRINT I*10+J;\n40 NEXT J\n50 NEXT I\n60 PRINT\n70 END\n"

(* NEXT <var> must find its loop past an inner one that is still open (J is
   never closed by its own NEXT here) rather than stopping at the first
   frame. This alone cannot tell whether the skipped J frame is discarded or
   merely left behind: NEXT I jumps back to the FOR J statement itself, so
   every outer iteration re-pushes a fresh J frame regardless of what became
   of the old one. See test_next_by_name_discards_the_frames_it_skips for
   the property this one cannot observe. *)
let test_next_by_name_matches_past_an_open_inner_frame () =
  check "outer NEXT finds its frame past the open inner one" " 11  21  31 \n"
    "10 FOR I=1 TO 3\n20 FOR J=1 TO 2\n30 PRINT I*10+J;\n40 NEXT I\n50 PRINT\n60 END\n"

(* The property the test above cannot see: once NEXT I closes the outer
   loop, is J's skipped frame actually gone? A trailing NEXT J, after the
   outer loop has run to completion, can only find a frame to act on if one
   was left on the stack -- and the only candidate is a leaked, stale J. If
   NEXT discards the frames it skips past, as it must, the stack is empty by
   then and line 50's NEXT J raises "NEXT without FOR" right there.

   The line matters, not just the message: a build that retains skipped
   frames instead of discarding them still eventually raises this same
   message (from a *different* NEXT, having run further and printed more
   output first) at line 40, not 50. Checking the message alone does not
   distinguish "the stack was already empty here" from "something went
   wrong two statements later that happens to produce the same words" --
   only the line pins which one actually happened. *)
let test_next_by_name_discards_the_frames_it_skips () =
  check_failure "discards skipped frames" ~line:50 ~message:"NEXT without FOR"
    "10 FOR I=1 TO 3\n20 FOR J=1 TO 2\n30 PRINT I*10+J;\n40 NEXT I\n50 NEXT J\n60 END\n"

let test_next_without_for () =
  match Interp.run_source ~write:ignore "10 NEXT\n" with
  | Ok () -> Alcotest.fail "expected an error"
  | Error e -> Alcotest.(check string) "message" "NEXT without FOR" e.message

let test_for_without_next () =
  check_failure "FOR without NEXT" ~line:10 ~message:"FOR without NEXT"
    "10 FOR I=1 TO 0\n20 PRINT I\n30 END\n"

let test_gosub_return () =
  check "subroutine" "A B A \n"
    "10 PRINT \"A \";\n20 GOSUB 100\n30 PRINT \"A \"\n40 END\n100 PRINT \"B \";\n110 RETURN\n"

let test_nested_gosub () =
  check "nested subroutines" " 1  2  3 \n"
    "10 GOSUB 100\n20 PRINT\n30 END\n100 PRINT 1;\n110 GOSUB 200\n120 PRINT 3;\n130 RETURN\n200 PRINT 2;\n210 RETURN\n"

let test_return_without_gosub () =
  match Interp.run_source ~write:ignore "10 RETURN\n" with
  | Ok () -> Alcotest.fail "expected an error"
  | Error e -> Alcotest.(check string) "message" "RETURN without GOSUB" e.message

(* --------------------------------------------------------- WHILE/WEND *)

(* Confirmed on the manual page: a condition false from the start means the
   body between WHILE and WEND never runs, not even once. *)
let test_while_false_from_the_start_never_runs () =
  check "never enters" "DONE\n"
    "10 WHILE 0\n20 PRINT \"IN\"\n30 WEND\n40 PRINT \"DONE\"\n50 END\n"

let test_while_loop () =
  check "counts" " 1  2  3 \n"
    "10 I=0\n20 WHILE I<3\n30 I=I+1\n40 PRINT I;\n50 WEND\n60 PRINT\n70 END\n"

let test_nested_while () =
  check "nested" " 11  12  21  22 \n"
    ("10 I=0\n20 WHILE I<2\n30 I=I+1\n40 J=0\n50 WHILE J<2\n60 J=J+1\n"
   ^ "70 PRINT I*10+J;\n80 WEND\n90 WEND\n100 PRINT\n110 END\n")

let test_wend_without_while () =
  match Interp.run_source ~write:ignore "10 WEND\n20 END\n" with
  | Ok () -> Alcotest.fail "expected an error"
  | Error e -> Alcotest.(check string) "message" "WEND without WHILE" e.message

(* A WHILE whose condition is false on entry and whose matching WEND does not
   exist anywhere in the program: the forward skip runs off the end of the
   line table (spec/errors.json #29), the same shape as FOR without NEXT. *)
let test_while_without_wend () =
  check_failure "WHILE without WEND" ~line:10 ~message:"WHILE without WEND"
    "10 WHILE 0\n20 PRINT \"IN\"\n30 END\n"

(* --------------------------------------------------------- ON GOTO/GOSUB *)

let test_on_goto_in_range () =
  check "middle target" "TWO\n"
    ("10 ON 2 GOTO 100,110,120\n20 END\n100 PRINT \"ONE\":GOTO 999\n"
   ^ "110 PRINT \"TWO\":GOTO 999\n120 PRINT \"THREE\"\n999 END\n")

(* Confirmed on the manual page: index 0 falls through to the next
   statement rather than erroring. *)
let test_on_goto_zero_falls_through () =
  check "zero falls through" "FELL THROUGH\n"
    "10 ON 0 GOTO 100\n20 PRINT \"FELL THROUGH\"\n30 END\n100 PRINT \"NOPE\"\n110 END\n"

(* Confirmed on the manual page: an index past the end of the list also
   falls through, and is not an error either. *)
let test_on_goto_past_the_end_falls_through () =
  check "past the end falls through" "FELL THROUGH\n"
    "10 ON 5 GOTO 100,110\n20 PRINT \"FELL THROUGH\"\n30 END\n100 END\n110 END\n"

(* Confirmed on the manual page: a negative index is "Illegal function
   call", distinct from the "no error, falls through" cases above. *)
let test_on_goto_negative_is_illegal_function_call () =
  check_failure "negative index" ~line:10 ~message:"Illegal function call"
    "10 ON -1 GOTO 100\n20 END\n100 END\n"

let test_on_gosub_returns () =
  check "ON GOSUB then RETURN" "IN OUT\n"
    "10 ON 1 GOSUB 100\n20 PRINT \"OUT\"\n30 END\n100 PRINT \"IN \";\n110 RETURN\n"

(* ------------------------------------------------------------------ SWAP *)

let test_swap_scalars () =
  check "swap scalars" " 2  1 \n" "10 A=1\n20 B=2\n30 SWAP A,B\n40 PRINT A;B\n50 END\n"

let test_swap_array_elements () =
  check "swap array elements" " 9  5 \n"
    "10 DIM A(2)\n20 DIM B(2)\n30 A(1)=5\n40 B(1)=9\n50 SWAP A(1),B(1)\n60 PRINT A(1);B(1)\n70 END\n"

let test_swap_strings () =
  check "swap strings" "WORLD HELLO\n"
    "10 A$=\"HELLO\"\n20 B$=\"WORLD\"\n30 SWAP A$,B$\n40 PRINT A$;\" \";B$\n50 END\n"

(* Confirmed on the manual page: mismatched types are refused. *)
let test_swap_type_mismatch () =
  check_failure "type mismatch" ~line:30 ~message:"Type mismatch"
    "10 A$=\"HI\"\n20 B=1\n30 SWAP A$,B\n40 END\n"

(* ------------------------------------------------------- arrays and DIM *)

let test_dim_and_arrays () =
  check "array" " 42 \n" "10 DIM A(5)\n20 A(3)=42\n30 PRINT A(3)\n40 END\n"

let test_two_dimensional_array () =
  check "matrix" " 7 \n" "10 DIM M(2,2)\n20 M(1,2)=7\n30 PRINT M(1,2)\n40 END\n"

(* Confirmed: subscripts run 0..N inclusive, and index 0 is a real cell. *)
let test_dim_allocates_zero_through_n () =
  check "0..N" " 1  2 \n" "10 DIM A(2)\n20 A(0)=1\n30 A(2)=2\n40 PRINT A(0);A(2)\n50 END\n"

(* Confirmed: DIM takes a bound computed at run time. The bound here is past
   the implicit 10, so a build that ignored the expression and left the
   default in place would fail on the subscript instead. *)
let test_dim_accepts_a_run_time_bound () =
  check "run-time bound" " 4 \n"
    "10 N=12\n20 DIM A(N)\n30 A(12)=4\n40 PRINT A(12)\n50 END\n"

(* A bound below zero has no cells to allocate. Env raises rather than letting
   Array.make's own Invalid_argument escape the interpreter's result type. *)
let test_a_negative_dim_bound_is_refused () =
  check_failure "negative bound" ~line:20 ~message:"Subscript out of range"
    "10 N=-2\n20 DIM A(N)\n30 END\n"

(* Confirmed on the manual page: DIM-ing an array a second time, without
   ERASE in between, is a "Duplicate Difinition" -- the same error the
   manual's own ERASE note names (spec/errors.json #10). *)
let test_redim_without_erase_is_a_duplicate_definition () =
  check_failure "re-DIM" ~line:20 ~message:"Duplicate Difinition"
    "10 DIM A(3)\n20 DIM A(5)\n30 END\n"

(* An array's first use -- not just an explicit DIM -- fixes its dimensions,
   per the same error's recorded meaning ("whether an earlier DIM or the
   array's first use fixed them"). *)
let test_dim_after_auto_vivify_is_a_duplicate_definition () =
  check_failure "DIM after first use" ~line:20 ~message:"Duplicate Difinition"
    "10 A(1)=1\n20 DIM A(5)\n30 END\n"

(* ERASE frees the array entirely: the manual's own consequence is that the
   same name can be DIM'd again without raising Duplicate Difinition, and
   the fresh array is unrelated to the erased one's old contents or bounds
   (spec/spec.md PROG.ERASE). *)
let test_erase_then_redim () =
  check "erase then re-DIM" " 9 \n"
    "10 DIM A(3)\n20 A(1)=42\n30 ERASE A\n40 DIM A(9)\n50 A(9)=9\n60 PRINT A(9)\n70 END\n"

(* ERASE also lets the name auto-vivify again at its default size rather than
   requiring a fresh DIM. *)
let test_erase_then_auto_vivify () =
  check "erase then auto-vivify" " 5 \n"
    "10 DIM A(3)\n20 ERASE A\n30 A(7)=5\n40 PRINT A(7)\n50 END\n"

(* ------------------------------------------------------------- OPTION BASE *)

(* Confirmed on the manual page: OPTION BASE 1 makes 0 an invalid subscript. *)
let test_option_base_one_forbids_index_zero () =
  check_failure "index 0 forbidden" ~line:30 ~message:"Subscript out of range"
    "10 OPTION BASE 1\n20 DIM A(5)\n30 A(0)=1\n40 END\n"

let test_option_base_one_allows_up_to_the_declared_bound () =
  check "1..N usable" " 9 \n"
    "10 OPTION BASE 1\n20 DIM A(5)\n30 A(5)=9\n40 PRINT A(5)\n50 END\n"

(* Without OPTION BASE, the default origin is 0, so index 0 is a real cell --
   the same behaviour arrays have always had. *)
let test_default_base_is_zero () =
  check "default base 0" " 1 \n" "10 DIM A(5)\n20 A(0)=1\n30 PRINT A(0)\n40 END\n"

(* Confirmed on the manual page: once OPTION BASE has fixed the origin, a
   second OPTION BASE statement is a re-specification, refused the same way
   a redundant DIM is. *)
let test_option_base_respecified_is_a_duplicate_definition () =
  check_failure "re-specified" ~line:20 ~message:"Duplicate Difinition"
    "10 OPTION BASE 1\n20 OPTION BASE 1\n30 END\n"

(* Confirmed on the manual page: OPTION BASE placed after an array already
   exists has no effect -- it is not an error, and the array's existing
   origin (0, the default) is unchanged. *)
let test_option_base_after_an_array_exists_has_no_effect () =
  check "no effect once an array exists" " 1 \n"
    "10 DIM A(5)\n20 OPTION BASE 1\n30 A(0)=1\n40 PRINT A(0)\n50 END\n"

(* CLEAR is the manual's own answer for how to change OPTION BASE once set:
   afterwards, OPTION BASE can be given again without raising. *)
let test_clear_lets_option_base_be_set_again () =
  check "CLEAR resets OPTION BASE" " 9 \n"
    ("10 OPTION BASE 1\n20 DIM A(5)\n30 CLEAR\n40 OPTION BASE 1\n50 DIM A(5)\n"
   ^ "60 A(5)=9\n70 PRINT A(5)\n80 END\n")

(* ------------------------------------------------------------------ CLEAR *)

(* Confirmed on the manual page: every numeric variable reverts to 0 and
   every string variable to "". *)
let test_clear_resets_scalars () =
  check "scalars reset" " 0 \n" "10 A=5\n20 CLEAR\n30 PRINT A\n40 END\n"

let test_clear_resets_string_scalars () =
  check "string scalars reset" "\n" "10 A$=\"HI\"\n20 CLEAR\n30 PRINT A$\n40 END\n"

(* Confirmed on the manual page: CLEAR's optional slots are memory-layout
   parameters this interpreter does not model; they are still evaluated
   (and can still be malformed) but otherwise have no effect. *)
let test_clear_with_arguments_ignores_them () =
  check "CLEAR ,mem,stack" " 0 \n" "10 A=5\n20 CLEAR ,1000,100\n30 PRINT A\n40 END\n"

let test_clear_resets_arrays () =
  check "arrays reset" " 0 \n"
    "10 DIM A(3)\n20 A(1)=42\n30 CLEAR\n40 DIM A(3)\n50 PRINT A(1)\n60 END\n"

(* ------------------------------------------------------ DATA/READ/RESTORE *)

(* DATA is gathered before the first statement runs, so a READ reaches data
   declared on a later line. *)
let test_read_data () =
  check "READ" " 5  3  8 \n"
    "10 FOR I=1 TO 3\n20 READ X\n30 PRINT X;\n40 NEXT I\n50 PRINT\n60 DATA 5,3,8\n70 END\n"

(* The gathering walks the line table, which is sorted by line number, so a
   DATA line written earlier in the file but numbered later is read later.
   File order would yield the two values the other way round. *)
let test_data_is_gathered_in_line_number_order () =
  check "line order" " 9  42 \n"
    "30 DATA 42\n10 DATA 9\n20 READ A: READ B: PRINT A;B\n40 END\n"

(* Everything after THEN belongs to the branch, so `IF 0 THEN DATA 5` puts the
   DATA *inside* the IF rather than beside it in the line's statement list.
   Gathering walks only the top level unless it descends deliberately, and the
   machine gathers DATA when the program loads — so the datum counts whether or
   not the branch ever runs, and it counts in its own line's place. The branch
   here is not taken and line 15 declares data of its own, so a gathering pass
   that skipped the nested statement would quietly hand READ the wrong number
   rather than fail. *)
let test_data_inside_a_then_branch_is_gathered () =
  check "DATA in THEN" " 5  9 \n"
    "10 IF 0 THEN DATA 5\n15 DATA 9\n20 READ A: READ B: PRINT A;B\n30 END\n"

let test_data_inside_an_else_branch_is_gathered () =
  check "DATA in ELSE" " 42 \n"
    "10 IF 1 THEN A=0 ELSE DATA 42\n20 READ B: PRINT B\n30 END\n"

let test_read_takes_a_string_datum () =
  check "string DATA" "AB\n" "10 READ A$\n20 PRINT A$\n30 DATA AB\n40 END\n"

let test_read_into_an_array_element () =
  check "READ A(1)" " 42 \n" "10 READ A(1)\n20 PRINT A(1)\n30 DATA 42\n40 END\n"

let test_restore () =
  check "RESTORE" " 8  8 \n"
    "10 READ X\n20 PRINT X;\n30 RESTORE\n40 READ Y\n50 PRINT Y\n60 DATA 8,3\n70 END\n"

(* RESTORE <line> resets to the first datum declared at or after that line —
   not to the start, which is what a bare RESTORE would give (1 here), and not
   to the end. *)
let test_restore_to_a_line_starts_at_that_lines_data () =
  check "RESTORE 20" " 8  6 \n"
    "10 DATA 8,3\n20 DATA 6,4\n30 READ A\n40 RESTORE 20\n50 READ B\n60 PRINT A;B\n70 END\n"

(* "At or after" matters: line 20 declares nothing, so the cursor lands on line
   30's first datum. Requiring an exact match would have nowhere to go. *)
let test_restore_to_a_line_without_data_starts_at_the_next_one () =
  check "RESTORE 20 with no data there" " 8  6 \n"
    "10 DATA 8,3\n30 DATA 6,4\n40 READ A\n50 RESTORE 20\n60 READ B\n70 PRINT A;B\n80 END\n"

(* Past every DATA line there is nothing left to read, so the cursor sits at
   the end rather than wrapping back to the start. *)
let test_restore_past_every_data_line_leaves_nothing_to_read () =
  check_failure "RESTORE past the end" ~line:30 ~message:"Out of DATA"
    "10 DATA 9\n20 RESTORE 900\n30 READ A\n40 END\n"

let test_out_of_data () =
  check_failure "out of DATA" ~line:20 ~message:"Out of DATA"
    "10 READ X\n20 READ Y\n30 DATA 9\n40 END\n"

(* The program counter still walks over DATA lines while running. *)
let test_a_data_line_executes_as_a_no_op () =
  check "DATA in the path" " 1 \n" "10 DATA 42\n20 PRINT 1\n30 END\n"

(* ------------------------------------------------------------- DEF FN *)

let test_def_fn () =
  check "DEF FN" " 9 \n" "10 DEF FNS(X)=X*X\n20 PRINT FNS(3)\n30 END\n"

let test_def_fn_does_not_leak_parameter () =
  check "no leak" " 9  5 \n"
    "10 X=5\n20 DEF FNS(X)=X*X\n30 PRINT FNS(3);\n40 PRINT X\n50 END\n"

let test_def_fn_with_two_parameters () =
  check "two parameters" " 7 \n" "10 DEF FNA(P,Q)=P+Q\n20 PRINT FNA(3,4)\n30 END\n"

(* Every argument is evaluated before any parameter is bound. Binding P first
   and then evaluating the second argument would read the freshly bound P
   (giving 11) instead of the caller's own P. *)
let test_def_fn_evaluates_its_arguments_before_binding_them () =
  check "arguments first" " 12 \n"
    "10 P=2\n20 DEF FNA(P,Q)=P*10+Q\n30 PRINT FNA(1,P)\n40 END\n"

let test_def_fn_wrong_number_of_arguments () =
  check_failure "arity" ~line:20 ~message:"Wrong number of arguments"
    "10 DEF FNA(P,Q)=P+Q\n20 PRINT FNA(1)\n30 END\n"

(* DEF FN defines when it is executed, not when the program is loaded — unlike
   DATA, which is gathered beforehand. *)
let test_a_function_is_undefined_until_its_def_runs () =
  check_failure "used too early" ~line:10 ~message:"Undefined function FNA"
    "10 PRINT FNA(1)\n20 DEF FNA(X)=X\n30 END\n"

(* ------------------------------------------------------------- INPUT *)

(* Confirmed: the prompt is echoed verbatim and the interpreter appends "? ".
   The two spaces before 14 are that appended space meeting the leading space
   of a non-negative number. *)
let test_input_with_a_prompt () =
  check_answering "prompt then result" [ "7" ] "N?  14 \n"
    "10 INPUT \"N\";N\n20 PRINT N*2\n30 END\n"

let test_input_without_a_prompt_still_asks () =
  check_answering "bare INPUT" [ "3" ] "?  3 \n" "10 INPUT N\n20 PRINT N\n30 END\n"

let test_input_into_a_string_variable_keeps_the_text () =
  check_answering "string INPUT" [ "A B" ] "? [A B]\n"
    "10 INPUT A$\n20 PRINT \"[\"+A$+\"]\"\n30 END\n"

(* One line answers the whole statement, split on commas, one field per
   variable (ref-9801 printed p.82 / PDF p.93). This test demanded a line
   per variable until the page was read -- it fed ["1"; "2"] to INPUT A,B
   and passed, which is what let the divergence stand for so long. *)
let test_input_splits_one_line_across_its_variables () =
  check_answering "two variables, one line" [ "1,2" ] "?  1  2 \n"
    "10 INPUT A,B\n20 PRINT A;B\n30 END\n"

(* A quoted field keeps the commas and the end spaces that would otherwise
   be a separator and trimmed padding; the quotes are not part of the value. *)
let test_input_quoted_field_keeps_its_commas_and_spaces () =
  check_answering "quoted field" [ "\" a,b \",2" ] "? [ a,b ] 2 \n"
    "10 INPUT A$,N\n20 PRINT \"[\"+A$+\"]\";N\n30 END\n"

(* Return pressed on an empty field is 0 or the null string. With several
   variables the commas still have to be typed, which is what makes ",," an
   answer of three empty fields rather than a mistake. *)
let test_input_empty_fields_are_zero_and_the_null_string () =
  check_answering "empty fields" [ ",," ] "? [] 0 []\n"
    "10 INPUT A$,N,B$\n20 PRINT \"[\"+A$+\"]\";N;\"[\"+B$+\"]\"\n30 END\n"

(* A field that does not fit its variable displays "?Redo from start" and
   asks again, rather than stopping the program. It used to raise. The same
   goes for a line with the wrong number of fields, which is our reading --
   the manual requires the counts to agree but does not say what happens
   when they do not. *)
let test_input_redoes_a_bad_answer_instead_of_failing () =
  check_answering "redo on type" [ "AB"; "7" ] "? ?Redo from start\n?  7 \n"
    "10 INPUT N\n20 PRINT N\n30 END\n"

let test_input_redoes_when_the_field_count_is_wrong () =
  check_answering "redo on count" [ "1"; "1,2" ] "? ?Redo from start\n?  1  2 \n"
    "10 INPUT A,B\n20 PRINT A;B\n30 END\n"

(* An answer that never fits still ends: the input source runs out and the
   loop stops rather than asking forever. *)
let test_input_of_a_non_number_eventually_runs_out () =
  check_answering_failure "never fits" [ "AB" ] ~line:10 ~message:"Out of input"
    "10 INPUT N\n20 PRINT N\n30 END\n"

let test_input_that_runs_out_is_an_error () =
  check_answering_failure "exhausted" [] ~line:10 ~message:"Out of input"
    "10 INPUT N\n20 PRINT N\n30 END\n"

(* -------------------------------------------------------- LINE INPUT *)

(* Confirmed against ref-9801: unlike INPUT, LINE INPUT's prompt is echoed
   with no "? " appended. *)
let test_line_input_with_a_prompt_adds_no_question_mark () =
  check_answering "prompt, no ?" [ "Ada" ] "NAME:GOT Ada\n"
    "10 LINE INPUT \"NAME:\"; N$\n20 PRINT \"GOT \"+N$\n30 END\n"

let test_line_input_without_a_prompt_asks_nothing () =
  check_answering "no prompt" [ "hi" ] "hi\n" "10 LINE INPUT B$\n20 PRINT B$\n30 END\n"

(* The whole line -- commas, quotes and all -- lands in the variable
   unsplit, unlike INPUT which would parse this as three separate answers. *)
let test_line_input_keeps_commas_and_quotes_verbatim () =
  check_answering "verbatim" [ "A, \"B\", C" ] "A, \"B\", C\n"
    "10 LINE INPUT L$\n20 PRINT L$\n30 END\n"

let test_line_input_that_runs_out_is_an_error () =
  check_answering_failure "exhausted" [] ~line:10 ~message:"Out of input"
    "10 LINE INPUT S$\n20 PRINT S$\n30 END\n"

(* A numeric target is not what the manual's box allows (it names a string
   variable), and assigning the typed text into one goes through the same
   coercion every other string-into-numeric assignment does. *)
let test_line_input_into_a_numeric_variable_is_a_type_error () =
  check_answering_failure "numeric target" [ "5" ] ~line:10 ~message:"Type mismatch"
    "10 LINE INPUT N\n20 PRINT N\n30 END\n"

(* --------------------------------------------------------- functions *)

let test_sin () = check "SIN" " 0 \n" "10 PRINT SIN(0)\n20 END\n"
let test_cos () = check "COS" " 1 \n" "10 PRINT COS(0)\n20 END\n"
let test_tan () = check "TAN" " 0 \n" "10 PRINT TAN(0)\n20 END\n"
let test_atn () = check "ATN" " 0 \n" "10 PRINT ATN(0)\n20 END\n"
let test_exp_of_zero_is_one () = check "EXP(0)" " 1 \n" "10 PRINT EXP(0)\n20 END\n"
let test_exp_of_one_is_e () = check "EXP(1)" " 2.71828 \n" "10 PRINT EXP(1)\n20 END\n"
let test_log_of_one_is_zero () = check "LOG(1)" " 0 \n" "10 PRINT LOG(1)\n20 END\n"

let test_log_at_zero_is_a_domain_error () =
  check_failure "LOG(0)" ~line:10 ~message:"Illegal function call" "10 PRINT LOG(0)\n20 END\n"

let test_log_of_a_negative_number_is_a_domain_error () =
  check_failure "LOG(-1)" ~line:10 ~message:"Illegal function call" "10 PRINT LOG(-1)\n20 END\n"

(* FIX truncates toward zero; INT floors toward negative infinity. They agree
   except for a negative, non-whole argument, where FIX's answer is one
   greater than INT's (spec/spec.md NUM.FIX). *)
let test_fix_and_int_differ_for_a_negative_fraction () =
  check "FIX vs INT" "-2 -3 \n" "10 PRINT FIX(-2.7);INT(-2.7)\n20 END\n"

let test_fix_and_int_agree_for_a_positive_fraction () =
  check "FIX vs INT positive" " 2  2 \n" "10 PRINT FIX(2.7);INT(2.7)\n20 END\n"

let test_cint_rounds_ties_away_from_zero () =
  check "CINT rounding" " 3 -3 \n" "10 PRINT CINT(2.5);CINT(-2.5)\n20 END\n"

let test_cint_overflow () =
  check_failure "CINT overflow" ~line:10 ~message:"Overflow (OV)" "10 PRINT CINT(40000)\n20 END\n"

let test_csng_round_trips_a_representable_value () =
  check "CSNG" " 1.5 \n" "10 PRINT CSNG(1.5)\n20 END\n"

(* CDBL widens without adding precision (ref-9801 printed p.18 / PDF p.31,
   rule 5, and CDBL's own entry printed p.42 / PDF p.53): the value it
   returns carries no more significant digits than its argument's own type
   did. 3.14 here is an unsuffixed <=7-digit literal, so it is single
   precision already (spec/spec.md NUM.TYPES) -- narrowed to a 32-bit float
   the moment it is parsed, the same narrowing CSNG performs explicitly.
   CDBL only relabels that already-narrowed value as double precision, so
   printing it at double precision's 16 significant digits shows the
   single-precision float's own imprecision (3.14 has no exact IEEE-754
   representation at either width), where the pre-existing "CDBL is the
   identity" test expected exactly its input back -- true only when every
   number shared one undifferentiated representation, which this
   interpreter no longer does. *)
let test_cdbl_widens_without_adding_precision () =
  check "CDBL" " 3.140000104904175 \n" "10 PRINT CDBL(3.14)\n20 END\n"

let test_space_dollar_length () =
  check "LEN(SPACE$(3))" " 3 \n" "10 PRINT LEN(SPACE$(3))\n20 END\n"

let test_space_dollar_is_all_spaces () =
  check "SPACE$ contents" "[   ]\n" "10 PRINT \"[\";SPACE$(3);\"]\"\n20 END\n"

let test_space_dollar_out_of_range () =
  check_failure "SPACE$ range" ~line:10 ~message:"Illegal function call"
    "10 PRINT SPACE$(256)\n20 END\n"

let test_spc_inserts_literal_spaces () =
  check "SPC" "A   B\n" "10 PRINT \"A\";SPC(3);\"B\"\n20 END\n"

let test_spc_with_a_negative_argument_is_zero () =
  check "SPC negative" "AB\n" "10 PRINT \"A\";SPC(-5);\"B\"\n20 END\n"

(* POS reads the same column counter TAB already pads to; CSRLIN counts
   newlines the PRINT writer has put (spec/spec.md PRINT.POS,
   PRINT.CSRLIN). *)
let test_pos_and_csrlin_track_the_print_writer () =
  check "POS/CSRLIN" "AB 2 \n 1 \n" "10 PRINT \"AB\";\n20 PRINT POS(0)\n30 PRINT CSRLIN\n40 END\n"

let test_rnd_zero_repeats_the_last_value () =
  check "RND(0) repeats" "-1 \n" "10 A=RND(1)\n20 PRINT A=RND(0)\n30 END\n"

let test_rnd_negative_seed_is_deterministic () =
  check "RND negative seed reseeds deterministically" "-1 \n"
    "10 A=RND(-7)\n20 B=RND(-7)\n30 PRINT A=B\n40 END\n"

(* The determinism this task asked for: two independent runs, each starting a
   fresh interpreter state, draw the same sequence -- RND is seeded from a
   fixed constant (spec/spec.md NUM.RND), never from the wall clock or any
   other process-wide state. *)
let test_rnd_default_sequence_is_reproducible_across_runs () =
  let source = "10 PRINT RND(1);RND(1);RND(1)\n20 END\n" in
  Alcotest.(check string) "same sequence every run" (run source) (run source)

(* RANDOMIZE reseeds the same sequence RND itself draws from (spec/spec.md
   NUM.RANDOMIZE): the same seed, given twice in one run, must produce the
   same next draw both times. *)
let test_randomize_same_seed_reseeds_deterministically () =
  check "RANDOMIZE reseeds deterministically" "-1 \n"
    "10 RANDOMIZE 1\n20 A=RND(1)\n30 RANDOMIZE 1\n40 B=RND(1)\n50 PRINT A=B\n60 END\n"

(* Two different seeds are not required to draw different values forever,
   but for this fixed PRNG and these two small seeds they do -- pinning
   actual output, the same way the RND tests above do. *)
let test_randomize_different_seeds_draw_different_values () =
  check "RANDOMIZE with different seeds differs" " 0 \n"
    "10 RANDOMIZE 1\n20 A=RND(1)\n30 RANDOMIZE 2\n40 B=RND(1)\n50 PRINT A=B\n60 END\n"

let test_randomize_overflow_above () =
  check_failure "RANDOMIZE overflow above" ~line:10 ~message:"Overflow (OV)"
    "10 RANDOMIZE 32768\n20 END\n"

let test_randomize_overflow_below () =
  check_failure "RANDOMIZE overflow below" ~line:10 ~message:"Overflow (OV)"
    "10 RANDOMIZE -32769\n20 END\n"

(* A bare RANDOMIZE (spec/spec.md NUM.RANDOMIZE's "partial" decision): with
   no expression given, this interpreter reads a seed through the same
   caller-supplied input source INPUT itself reads through, rather than the
   wall clock, so a program using it stays reproducible under test. *)
let test_randomize_bare_reads_a_seed_from_input () =
  check_answering "bare RANDOMIZE reads a seed" [ "1" ]
    "Random number seed (-32768 to 32767)? -1 \n"
    "10 RANDOMIZE\n20 A=RND(1)\n30 RANDOMIZE 1\n40 B=RND(1)\n50 PRINT A=B\n60 END\n"

let test_randomize_bare_out_of_input_fails () =
  check_answering_failure "bare RANDOMIZE with no input" [] ~line:10 ~message:"Out of input"
    "10 RANDOMIZE\n20 END\n"

(* Before any error is ever trapped, ERR and ERL are 0 -- this interpreter's
   own decision for a starting value the manual never states (spec/spec.md
   ERR.FN, ERR.ERL). *)
let test_err_is_zero_before_any_error () =
  check "ERR before any error" " 0 \n" "10 PRINT ERR\n20 END\n"

let test_erl_is_zero_before_any_error () =
  check "ERL before any error" " 0 \n" "10 PRINT ERL\n20 END\n"

(* The bug this task fixes: a reserved word used as a variable, array, or
   loop variable must be a clear error, never a phantom array quietly
   answering 0. *)
let test_reserved_word_as_a_scalar_is_an_error () =
  check_failure "EXP as a scalar" ~line:10
    ~message:"EXP is a reserved word and cannot be used as a variable name" "10 EXP = 5\n20 END\n"

let test_reserved_word_as_a_dim_array_is_an_error () =
  check_failure "DIM EXP" ~line:10
    ~message:"EXP is a reserved word and cannot be used as a variable name" "10 DIM EXP(5)\n20 END\n"

let test_reserved_word_as_a_for_variable_is_an_error () =
  check_failure "FOR SIN" ~line:10
    ~message:"SIN is a reserved word and cannot be used as a variable name"
    "10 FOR SIN = 1 TO 10\n20 NEXT SIN\n30 END\n"

(* A word that is part of the language (spec/spec.md §3.2/§3.3) but has no
   grammar of its own must not silently become an array either. *)
let test_out_of_scope_word_as_an_array_is_an_error () =
  check_failure "OPEN as an array" ~line:10
    ~message:"OPEN is a reserved word (not implemented here) and cannot be used as a variable name"
    "10 PRINT OPEN(1)\n20 END\n"

(* PROG.VARIABLE-NAMES: a name containing a reserved word is fine -- only a
   name that is *exactly* one is refused. Before this fix, the lexer matched
   keywords as a prefix at every position, so each of these five names failed
   to parse (TOTAL as TO+TAL, LINEAR as LINE+AR, FORM as FOR+M, ANDY as
   AND+Y, IFS as IF+S). *)
let test_names_containing_reserved_words_are_ordinary_variables () =
  check "TOTAL/LINEAR/FORM/ANDY/IFS" " 5  3  1  2  7 \n"
    "10 TOTAL=5:LINEAR=3:FORM=1:ANDY=2:IFS=7\n20 PRINT TOTAL;LINEAR;FORM;ANDY;IFS\n30 END\n"

(* The same fix must not disturb the keywords FOR, TO, THEN and ELSE
   themselves, even in a program that also uses a reserved-word-containing
   name. *)
let test_for_to_then_else_still_work_alongside_such_names () =
  check "FOR/TO/THEN/ELSE unaffected" "OK\n"
    "10 TOTAL=5\n20 FOR I=1 TO 3\n30 NEXT I\n40 IF TOTAL>1 THEN PRINT \"OK\" ELSE PRINT \"NO\"\n50 END\n"

(* PROG.VARIABLE-NAMES: periods are legal past the required leading letter. *)
let test_variable_name_may_contain_a_period () =
  check "A.B" " 9 \n" "10 A.B=9\n20 PRINT A.B\n30 END\n"

(* PROG.VARIABLE-NAMES: up to 40 significant characters -- a name at exactly
   that length is usable in full. *)
let test_variable_name_at_the_forty_character_limit () =
  let name = String.make 40 'A' in
  check "40-char name" " 1 \n" (Printf.sprintf "10 %s=1\n20 PRINT %s\n30 END\n" name name)

(* PROG.VARIABLE-NAMES: letter case is not distinguished, so "Total" and
   "TOTAL" name the same scalar. *)
let test_variable_names_are_case_insensitive () =
  check "Total/TOTAL" " 5 \n" "10 Total=5\n20 PRINT TOTAL\n30 END\n"

(* A name that is *exactly* a reserved word must still be refused -- the
   fix above must not reopen the phantom-array bug [check_not_reserved]
   exists to close. *)
let test_exact_reserved_word_is_still_refused_as_a_variable () =
  check_failure "TO as a scalar" ~line:10
    ~message:"TO is a reserved word and cannot be used as a variable name" "10 TO = 5\n20 END\n"

(* PROG.VARIABLE-NAMES: a name beginning with "FN" belongs to DEF FN and may
   never be an ordinary variable. *)
let test_variable_name_may_not_begin_with_fn () =
  check_failure "FNX as a scalar" ~line:10
    ~message:
      "FNX is not a valid variable name (a name may not begin with FN, which is reserved for DEF FN)"
    "10 FNX = 5\n20 END\n"

let test_left_dollar () =
  check "LEFT$" "AB\n" "10 PRINT LEFT$(\"ABCDE\",2)\n20 END\n"

let test_left_dollar_past_the_end_takes_the_whole_string () =
  check "LEFT$ over-long" "ABCDE\n" "10 PRINT LEFT$(\"ABCDE\",9)\n20 END\n"

let test_left_dollar_with_a_negative_count () =
  check_failure "LEFT$ negative" ~line:10 ~message:"Illegal function call"
    "10 PRINT LEFT$(\"ABCDE\",-1)\n20 END\n"

(* The manual bounds LEFT$'s count to 0-255, the same as RIGHT$, MID$ and
   STRING$ (spec/spec.md STR.LEFT); 256 is one past that. *)
let test_left_dollar_count_above_255 () =
  check_failure "LEFT$ too large" ~line:10 ~message:"Illegal function call"
    "10 PRINT LEFT$(\"ABCDE\",256)\n20 END\n"

let test_right_dollar () =
  check "RIGHT$" "CDE\n" "10 PRINT RIGHT$(\"ABCDE\",3)\n20 END\n"

let test_right_dollar_past_the_end_takes_the_whole_string () =
  check "RIGHT$ over-long" "ABCDE\n" "10 PRINT RIGHT$(\"ABCDE\",9)\n20 END\n"

let test_right_dollar_zero_is_the_null_string () =
  check "RIGHT$ zero" "|\n" "10 PRINT RIGHT$(\"ABCDE\",0);\"|\"\n20 END\n"

let test_right_dollar_with_a_negative_count () =
  check_failure "RIGHT$ negative" ~line:10 ~message:"Illegal function call"
    "10 PRINT RIGHT$(\"ABCDE\",-1)\n20 END\n"

let test_len () = check "LEN" " 5 \n" "10 PRINT LEN(\"HELLO\")\n20 END\n"

let test_len_of_the_null_string () = check "LEN empty" " 0 \n" "10 PRINT LEN(\"\")\n20 END\n"

let test_asc () = check "ASC" " 65 \n" "10 PRINT ASC(\"A\")\n20 END\n"

(* The manual is silent on ASC(""); this interpreter's decision — Illegal
   function call, matching the domain error every other out-of-range string
   function raises — is recorded as such (spec/spec.md STR.ASC, "partial"). *)
let test_asc_of_the_null_string () =
  check_failure "ASC empty" ~line:10 ~message:"Illegal function call"
    "10 PRINT ASC(\"\")\n20 END\n"

let test_mid_dollar_function_two_args () =
  check "MID$ 2 args" "CDE\n" "10 PRINT MID$(\"ABCDE\",3)\n20 END\n"

let test_mid_dollar_function_three_args () =
  check "MID$ 3 args" "BC\n" "10 PRINT MID$(\"ABCDE\",2,2)\n20 END\n"

(* When the requested length runs past the end of the string, MID$ hands
   back only what is actually there rather than padding or erroring. *)
let test_mid_dollar_function_length_past_the_end () =
  check "MID$ length past end" "CDE\n" "10 PRINT MID$(\"ABCDE\",3,99)\n20 END\n"

(* A start position past the string's own length is the null string, not an
   error — unlike LEFT$/RIGHT$, whose out-of-range count *is* an error. *)
let test_mid_dollar_function_start_past_the_end () =
  check "MID$ start past end" "|\n" "10 PRINT MID$(\"ABCDE\",9);\"|\"\n20 END\n"

let test_mid_dollar_function_start_out_of_range () =
  check_failure "MID$ start range" ~line:10 ~message:"Illegal function call"
    "10 PRINT MID$(\"ABCDE\",0)\n20 END\n"

let test_mid_dollar_statement_replaces_in_place () =
  check "MID$ statement" "AXYZEF\n"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,2,3)=\"XYZ\"\n30 PRINT B$\n40 END\n"

(* The replacement is shorter than the field named by <expr2>: only the
   replacement's own characters move, and the rest of the field is
   untouched — MID$ statement never changes B$'s length. *)
let test_mid_dollar_statement_replacement_shorter_than_the_field () =
  check "MID$ statement short" "AXYDEF\n"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,2,3)=\"XY\"\n30 PRINT B$\n40 END\n"

(* The replacement is longer than <expr2>: only its first <expr2> characters
   are used. *)
let test_mid_dollar_statement_replacement_longer_than_the_field () =
  check "MID$ statement long" "AXYZEF\n"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,2,3)=\"XYZUVW\"\n30 PRINT B$\n40 END\n"

(* <expr2> omitted: every character of the replacement is used, capped by
   what remains of the field from the start position onward. *)
let test_mid_dollar_statement_omitted_length_uses_the_whole_replacement () =
  check "MID$ statement omitted length" "AXYZEF\n"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,2)=\"XYZ\"\n30 PRINT B$\n40 END\n"

(* No <expr2>, and the replacement (8 characters) is longer than what
   remains of the field from the start position (5): only those 5
   characters move, filling the field to its own end. *)
let test_mid_dollar_statement_omitted_length_still_never_grows_the_field () =
  check "MID$ statement omitted length, long replacement" "AXYZUV\n"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,2)=\"XYZUVWXY\"\n30 PRINT B$\n40 END\n"

(* A start position past the target's own length replaces nothing — the
   manual does not state this outright, but an in-place replacement has
   nowhere else to write those characters (spec/spec.md STR.MID, "partial"). *)
let test_mid_dollar_statement_start_past_the_end_is_a_no_op () =
  check "MID$ statement start past end" "ABCDEF\n"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,9)=\"XYZ\"\n30 PRINT B$\n40 END\n"

let test_mid_dollar_statement_start_out_of_range () =
  check_failure "MID$ statement start range" ~line:20 ~message:"Illegal function call"
    "10 B$=\"ABCDEF\"\n20 MID$(B$,0)=\"X\"\n30 END\n"

let test_instr_finds_a_substring () =
  check "INSTR found" " 4 \n" "10 PRINT INSTR(\"ONETWOTHREE\",\"TWO\")\n20 END\n"

let test_instr_not_found_is_zero () =
  check "INSTR not found" " 0 \n" "10 PRINT INSTR(\"ONETWOTHREE\",\"SIX\")\n20 END\n"

let test_instr_with_a_start_position () =
  check "INSTR start" " 0 \n" "10 PRINT INSTR(7,\"ONETWOTHREE\",\"TWO\")\n20 END\n"

(* A null needle "matches" at the given position, whatever it is — the
   manual states this as INSTR's value equalling <position> exactly. *)
let test_instr_with_a_null_needle_is_the_position () =
  check "INSTR null needle" " 4 \n" "10 PRINT INSTR(4,\"ONETWOTHREE\",\"\")\n20 END\n"

let test_str_dollar_positive_has_a_leading_space () =
  check "STR$ positive" " 12|\n" "10 PRINT STR$(12);\"|\"\n20 END\n"

let test_str_dollar_negative_has_a_leading_minus () =
  check "STR$ negative" "-12|\n" "10 PRINT STR$(-12);\"|\"\n20 END\n"

let test_str_dollar_zero_has_a_leading_space () =
  check "STR$ zero" " 0|\n" "10 PRINT STR$(0);\"|\"\n20 END\n"

let test_string_dollar_from_a_character () =
  check "STRING$ char" "+++\n" "10 PRINT STRING$(3,\"+\")\n20 END\n"

(* Only the first character of a multi-character string argument is used. *)
let test_string_dollar_uses_only_the_first_character () =
  check "STRING$ first char only" "aaa\n" "10 PRINT STRING$(3,\"abc\")\n20 END\n"

let test_string_dollar_from_a_character_code () =
  check "STRING$ code" "AAA\n" "10 PRINT STRING$(3,65)\n20 END\n"

let test_string_dollar_code_out_of_range () =
  check_failure "STRING$ code range" ~line:10 ~message:"Illegal function call"
    "10 PRINT STRING$(3,300)\n20 END\n"

let test_hex_dollar () = check "HEX$" "FF\n" "10 PRINT HEX$(255)\n20 END\n"

(* Negative values are rendered as their 16-bit two's-complement bit pattern,
   the same string a positive value of 32768 or more in the same bit
   pattern would produce. *)
let test_hex_dollar_negative () = check "HEX$ negative" "FFFF\n" "10 PRINT HEX$(-1)\n20 END\n"

let test_hex_dollar_out_of_range () =
  check_failure "HEX$ range" ~line:10 ~message:"Illegal function call"
    "10 PRINT HEX$(70000)\n20 END\n"

let test_oct_dollar () = check "OCT$" "10\n" "10 PRINT OCT$(8)\n20 END\n"

let test_oct_dollar_negative () = check "OCT$ negative" "177777\n" "10 PRINT OCT$(-1)\n20 END\n"

let test_chr_dollar () = check "CHR$" "A\n" "10 PRINT CHR$(65)\n20 END\n"

let test_chr_dollar_out_of_range () =
  check_failure "CHR$ range" ~line:10 ~message:"Illegal function call"
    "10 PRINT CHR$(300)\n20 END\n"

let test_val () = check "VAL" " 12.5 \n" "10 PRINT VAL(\"12.5\")\n20 END\n"

(* Confirmed: a listing builds "&H…" by concatenation and hands it to VAL. *)
let test_val_parses_hex () =
  check "VAL &H" " 255 \n" "10 PRINT VAL(\"&H\"+\"FF\")\n20 END\n"

(* VAL reads the numeric prefix and stops; text with no numeric prefix is 0. *)
let test_val_of_text_is_zero () = check "VAL text" " 0 \n" "10 PRINT VAL(\"XY\")\n20 END\n"

let test_val_stops_at_the_first_non_numeric_character () =
  check "VAL prefix" " 12 \n" "10 PRINT VAL(\"12XY\")\n20 END\n"

(* ------------------------------------------- screen and graphics statements *)

(* Run a source string and return both the recorded display operations, oldest
   first, and everything PRINT wrote. *)
let run_recording source =
  let ops = ref [] in
  let buf = Buffer.create 64 in
  (match
     Interp.run_source
       ~on_draw:(fun op -> ops := op :: !ops)
       ~write:(Buffer.add_string buf) source
   with
  | Ok () -> ()
  | Error e -> Alcotest.fail (Error.to_string e));
  (List.rev !ops, Buffer.contents buf)

(* The graphics statements are recorded, not drawn: the operations arrive in
   program order, carrying their arguments, and nothing reaches the screen. *)
let test_display_statements_are_recorded () =
  let ops, printed =
    run_recording
      "10 CLS\n20 SCREEN 1\n30 WIDTH 40,20\n40 KEY OFF\n50 LOCATE 3,4\n\
       60 LINE (0,0)-(10,20),3,BF\n70 END\n"
  in
  Alcotest.(check string) "nothing is printed" "" printed;
  match ops with
  | [
   Display.Cls 1;
   Display.Screen { mode = Some 1; switch = None; active = None; display = None };
   Display.Width (40, Some 20);
   Display.Key { number = None; action = Display.Key_off };
   Display.Locate { column = 3; row = Some 4; cursor = None };
   Display.Line
     {
       from_point = Some (Display.Abs (0., 0.));
       to_point = Display.Abs (10., 20.);
       colour = Some 3;
       box = `Filled;
       style = None;
       fill = None;
     };
  ] ->
      ()
  | _ -> Alcotest.fail "the recorded display list does not match the program"

let test_width_takes_columns_alone () =
  match fst (run_recording "10 WIDTH 40\n20 END\n") with
  | [ Display.Width (40, None) ] -> ()
  | _ -> Alcotest.fail "WIDTH with one argument should record no row count"

(* A LINE with no start point draws from the last point referenced, which the
   record keeps as the absence of a start rather than inventing one. *)
let test_line_without_a_start_point () =
  match fst (run_recording "10 LINE -(10,20)\n20 END\n") with
  | [ Display.Line
        { from_point = None; to_point = Display.Abs (10., 20.); colour = None;
          box = `None; style = None; fill = None } ]
    ->
      ()
  | _ -> Alcotest.fail "LINE -(x,y) should record no start point"

(* All four of SCREEN's slots are optional and every one of them is legal
   (ref-9801 printed p.140 / PDF p.151). This test demanded the opposite until
   the page was read -- it asserted that "SCREEN 3,0" was an arity error, and
   so defended the divergence rather than catching it, exactly as the LOCATE
   test below once did.

   An omitted slot stays absent rather than taking a default: "SCREEN ,,0,1"
   says nothing whatever about the mode, and a renderer that grows pages must
   be able to tell that from a mode of 0. *)
let test_screen_slots_are_each_optional () =
  (match fst (run_recording "10 SCREEN 3,0\n20 END\n") with
  | [ Display.Screen { mode = Some 3; switch = Some 0; active = None; display = None } ] -> ()
  | _ -> Alcotest.fail "SCREEN 3,0 should record a mode and a switch");
  match fst (run_recording "10 SCREEN ,,0,1\n20 END\n") with
  | [ Display.Screen { mode = None; switch = None; active = Some 0; display = Some 1 } ] -> ()
  | _ -> Alcotest.fail "SCREEN ,,0,1 should record only the two pages"

(* The mode and the switch are the two slots the manual tabulates values for,
   so they are the two that can be wrong. The page numbers are not checked:
   their legal range depends on the palette mode, which is out of scope, so a
   check would be inventing a rule rather than enforcing one. *)
let test_screen_rejects_a_mode_outside_the_table () =
  check_failure "SCREEN mode" ~line:10 ~message:"Illegal function call"
    "10 SCREEN 4\n20 END\n"

(* Every one of LOCATE's three slots is optional, and an empty one is written
   as a bare comma (ref-9801 printed p.99 / PDF p.110). This test demanded the
   opposite until the page was read -- it asserted that "LOCATE 5" was an
   arity error, and so defended the divergence rather than catching it.

   X comes first and is the horizontal coordinate, so "LOCATE 5" sets the
   column and leaves the row alone; an omitted X is column 0, while an
   omitted Y means the line the cursor is already on, which is why only the
   first of the two carries a default this far. *)
let test_locate_slots_are_each_optional () =
  (match fst (run_recording "10 LOCATE 5\n20 END\n") with
  | [ Display.Locate { column = 5; row = None; cursor = None } ] -> ()
  | _ -> Alcotest.fail "LOCATE 5 should set the column and leave the row alone");
  (match fst (run_recording "10 LOCATE ,,0\n20 END\n") with
  | [ Display.Locate { column = 0; row = None; cursor = Some 0 } ] -> ()
  | _ -> Alcotest.fail "LOCATE ,,0 should set only the cursor switch");
  match fst (run_recording "10 LOCATE 10,5,1\n20 END\n") with
  | [ Display.Locate { column = 10; row = Some 5; cursor = Some 1 } ] -> ()
  | _ -> Alcotest.fail "LOCATE should record X first, then Y, then the switch"

(* CONSOLE's four slots, in the manual's order and each optional (ref-9801
   printed p.54 / PDF p.65). Both programs here are the manual's own
   examples. None of the four is defaulted: an omitted slot leaves that
   setting as it stands, so its absence is what the display list records. *)
let test_console_slots_are_each_optional () =
  (match fst (run_recording "10 CONSOLE 0,24,0,1\n20 END\n") with
  | [
   Display.Console
     { scroll_start = Some 0; scroll_lines = Some 24; function_keys = Some 0;
       colour_mode = Some 1 };
  ] ->
      ()
  | _ -> Alcotest.fail "CONSOLE 0,24,0,1 should record all four settings in order");
  match fst (run_recording "10 CONSOLE ,,1,0\n20 END\n") with
  | [
   Display.Console
     { scroll_start = None; scroll_lines = None; function_keys = Some 1;
       colour_mode = Some 0 };
  ] ->
      ()
  | _ -> Alcotest.fail "CONSOLE ,,1,0 should leave the scroll window unset"

let test_width_with_more_arguments_than_we_record () =
  check_failure "WIDTH arity" ~line:10 ~message:"WIDTH takes one or two arguments"
    "10 WIDTH 40,20,1\n20 END\n"

(* -------------------------------------------------------- PSET / PRESET *)

let test_pset_is_recorded_with_its_colour () =
  match fst (run_recording "10 PSET (100,50),4\n20 END\n") with
  | [ Display.Pset { point = Display.Abs (100., 50.); colour = Some 4 } ] -> ()
  | _ -> Alcotest.fail "PSET (x,y),c should record an absolute point and colour"

let test_pset_without_a_colour_records_none () =
  match fst (run_recording "10 PSET (1,2)\n20 END\n") with
  | [ Display.Pset { point = Display.Abs (1., 2.); colour = None } ] -> ()
  | _ -> Alcotest.fail "PSET (x,y) with no colour should record colour:None"

(* STEP(x,y) is relative to the LP — a fact only raster/ can resolve (it
   alone tracks the running point), so the record keeps the distinction
   rather than resolving it here. *)
let test_pset_step_records_a_relative_point () =
  match fst (run_recording "10 PSET STEP(5,-3)\n20 END\n") with
  | [ Display.Pset { point = Display.Step (5., -3.); colour = None } ] -> ()
  | _ -> Alcotest.fail "PSET STEP(x,y) should record a relative point"

let test_preset_is_recorded () =
  match fst (run_recording "10 PRESET (7,8)\n20 END\n") with
  | [ Display.Preset { point = Display.Abs (7., 8.); colour = None } ] -> ()
  | _ -> Alcotest.fail "PRESET (x,y) should record an absolute point"

(* --------------------------------------------------------------- COLOR *)

let test_color_records_all_four_slots () =
  match fst (run_recording "10 COLOR 1,2,3,4\n20 END\n") with
  | [
      Display.Color
        {
          function_code = Some 1;
          background = Some 2;
          border = Some 3;
          foreground = Some 4;
        };
    ] ->
      ()
  | _ -> Alcotest.fail "COLOR a,b,c,d should record all four slots"

(* A bare comma leaves a slot unset rather than zeroing it — COLOR ,,,7
   touches only the foreground. *)
let test_color_skips_leading_slots_on_bare_commas () =
  match fst (run_recording "10 COLOR ,,,7\n20 END\n") with
  | [
      Display.Color
        { function_code = None; background = None; border = None; foreground = Some 7 };
    ] ->
      ()
  | _ -> Alcotest.fail "COLOR ,,,7 should set only the foreground slot"

(* Bare COLOR is NOT [1] COLOR with every slot empty. ref-9801 printed p.51:
   omitting the equals sign and both arguments initialises the palette
   mapping. This test used to assert the opposite -- it was written from the
   implementation, which recorded an all-unset [1] COLOR and did nothing --
   and the page says otherwise. *)
let test_bare_color_initialises_the_palette () =
  match fst (run_recording "10 COLOR\n20 END\n") with
  | [ Display.Color_palette_init ] -> ()
  | _ -> Alcotest.fail "bare COLOR should initialise the palette mapping"

(* The distinguishing input for the rule above: `COLOR ,,,` also leaves every
   slot empty, and is still [1] COLOR. Without this the parser could route
   both to the initialising form and the suite would not notice. *)
let test_color_with_only_commas_is_still_the_first_form () =
  match fst (run_recording "10 COLOR ,,,\n20 END\n") with
  | [
      Display.Color
        { function_code = None; background = None; border = None; foreground = None };
    ] ->
      ()
  | _ -> Alcotest.fail "COLOR ,,, should stay [1] COLOR with every slot unset"

(* [2] COLOR = (<palette number>, <colour code>), ref-9801 printed p.51. *)
let test_color_palette_assignment_is_recorded () =
  match fst (run_recording "10 COLOR=(1,2)\n20 END\n") with
  | [ Display.Color_palette { palette = 1; code = 2 } ] -> ()
  | _ -> Alcotest.fail "COLOR=(1,2) should record a palette assignment"

(* Out of range is refused rather than wrapped, so a listing written for a
   4096-colour machine says so instead of silently painting a wrong colour.
   Ours, not the manual's -- see SCREEN.COLOR-PALETTE. *)
let test_color_palette_assignment_refuses_an_out_of_range_code () =
  check_failure "COLOR=(0,&HF00)" ~line:10 ~message:"Illegal function call"
    "10 COLOR=(0,&HF00)\n20 END\n"

let test_color_palette_assignment_refuses_an_out_of_range_palette () =
  check_failure "COLOR=(8,1)" ~line:10 ~message:"Illegal function call"
    "10 COLOR=(8,1)\n20 END\n"

(* Writing the `=` commits the statement to both arguments -- our reading of
   the page's bracketing, recorded on SCREEN.COLOR-PALETTE. *)
let test_color_palette_assignment_needs_both_arguments () =
  check_failure "COLOR=(2,)" ~line:10 ~message:"Expected an expression"
    "10 COLOR=(2,)\n20 END\n"

(* [1] COLOR's fifth slot (palette mode) is the same out-of-scope territory
   under a different syntax. *)
let test_color_palette_mode_argument_is_refused () =
  check_failure "COLOR's fifth slot" ~line:10
    ~message:"COLOR's palette-mode argument is not supported"
    "10 COLOR ,,,,1\n20 END\n"

(* --------------------------------------------------------------- POINT *)

(* POINT reads pixel state back through a caller-supplied handler
   (Interp.state's on_point) rather than basic/ knowing what a pixel is —
   this pins that the interpreter asks the handler with the coordinates the
   program gave it and returns exactly what the handler answers, without
   interpreting the result itself. *)
let test_point_asks_the_handler_and_returns_its_answer () =
  let asked = ref [] in
  let on_point x y =
    asked := (x, y) :: !asked;
    42
  in
  let buf = Buffer.create 16 in
  (match
     Interp.run_source ~on_point ~write:(Buffer.add_string buf)
       "10 PRINT POINT(12,34)\n20 END\n"
   with
  | Ok () -> ()
  | Error e -> Alcotest.fail (Error.to_string e));
  Alcotest.(check string) "POINT's value" " 42 \n" (Buffer.contents buf);
  Alcotest.(check (list (pair (float 0.) (float 0.)))) "coordinates asked" [ (12., 34.) ]
    !asked

(* No handler supplied (the default): every point reports as unlit — the
   honest answer for a caller that never rasterises anything, rather than a
   value that looks like it came from a real framebuffer. *)
let test_point_with_no_handler_reports_unlit () =
  check "POINT with no rasteriser" "-1 \n" "10 PRINT POINT(0,0)\n20 END\n"

(* POINT(1) used to be asserted here as an arity error. That was written from
   the implementation: printed p.122 documents exactly this call, "WX=POINT(0)",
   as [1] POINT reading the LP back. Three arguments is a real arity error. *)
let test_point_wrong_arity () =
  check_failure "POINT arity" ~line:10 ~message:"Wrong number of arguments"
    "10 PRINT POINT(1,2,3)\n20 END\n"

(* The POINT STATEMENT (printed p.122) moves the LP and draws nothing, so it
   records its own op rather than a Pset. *)
let test_point_statement_records_an_lp_move () =
  match fst (run_recording "10 POINT(50,60)\n20 END\n") with
  | [ Display.Point_lp { point = Display.Abs (50., 60.) } ] -> ()
  | _ -> Alcotest.fail "POINT(50,60) should record an LP move"

let test_point_statement_step_form () =
  match fst (run_recording "10 POINT STEP(10,-20)\n20 END\n") with
  | [ Display.Point_lp { point = Display.Step (10., -20.) } ] -> ()
  | _ -> Alcotest.fail "POINT STEP(10,-20) should record a relative LP move"

(* [1] POINT(<function>): 0/1 are the LP's X/Y in world coordinates, 2/3 the
   same in screen coordinates. They agree here because printed p.161 says the
   two systems coincide until WINDOW runs, and WINDOW is deferred. *)
let test_point_function_reads_the_lp_through_the_handler () =
  let buf = Buffer.create 16 in
  let on_lp () = (12.0, 34.0) in
  (match
     Interp.run_source ~on_lp ~write:(Buffer.add_string buf)
       "10 PRINT POINT(0);POINT(1);POINT(2);POINT(3)\n20 END\n"
   with
  | Ok () -> ()
  | Error e -> Alcotest.fail (Error.to_string e));
  Alcotest.(check string) "world and screen agree" " 12  34  12  34 \n" (Buffer.contents buf)

(* A code outside 0-3 is refused -- ours, not the manual's; see GFX.POINT. *)
let test_point_function_refuses_an_out_of_range_code () =
  check_failure "POINT(4)" ~line:10 ~message:"Illegal function call"
    "10 PRINT POINT(4)\n20 END\n"

(* ------------------------------------------------------ error handling *)
(* spec/spec.md ERR.ON-ERROR-GOTO, ERR.RESUME, ERR.ERROR, ERR.FN, ERR.ERL. *)

(* The trap: an ordinary runtime error (division by zero) is caught rather
   than failing the program, the handler runs, and RESUME NEXT continues
   with the statement after the one that failed -- A is never assigned, so
   it is still 0 when read back afterwards. *)
let test_trapped_division_by_zero_continues_with_resume_next () =
  check "RESUME NEXT" "TRAPPED\nAFTER 0 \n"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 PRINT \"AFTER\";A\n40 END\n\
     100 PRINT \"TRAPPED\"\n110 RESUME NEXT\n"

(* Inside the handler, ERR holds the error's number (11, Division by Zero)
   and ERL the BASIC line it happened on -- not the handler's own line. *)
let test_err_and_erl_inside_the_handler () =
  check "ERR/ERL" " 11 \n 20 \n"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 END\n\
     100 PRINT ERR\n110 PRINT ERL\n120 RESUME NEXT\n"

(* RESUME <line>: execution picks up at the given line, skipping everything
   between the failing statement and there -- including the rest of the
   handler routine itself. *)
let test_resume_line () =
  check "RESUME <line>" "HANDLED\nTARGET\n"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 PRINT \"SKIPPED\"\n40 END\n\
     100 PRINT \"HANDLED\"\n110 RESUME 200\n120 PRINT \"NEVER\"\n\
     200 PRINT \"TARGET\"\n210 END\n"

(* A bare RESUME retries the exact statement that failed. The handler
   changes D from 0 to 1 first, so the retried division succeeds instead of
   failing again -- proof it is really re-running the statement, not just
   falling through, and with no risk of looping forever. *)
let test_bare_resume_retries_the_failing_statement () =
  check "bare RESUME" "RESULT 1 \n"
    "10 D = 0\n20 ON ERROR GOTO 100\n30 A = 1/D\n40 PRINT \"RESULT\";A\n50 END\n\
     100 D = 1\n110 RESUME\n"

(* ON ERROR GOTO 0, executed in ordinary flow (after a RESUME has already
   returned control there, not from inside a handler), disables trapping:
   the next error is untrapped and fails the program exactly as if no
   ON ERROR GOTO had ever run. *)
let test_on_error_goto_zero_restores_default_behaviour () =
  check_failure "ON ERROR GOTO 0" ~line:50 ~message:"Division by zero"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 PRINT \"AFTER\"\n40 ON ERROR GOTO 0\n\
     50 A = 1/0\n60 PRINT \"NEVER\"\n100 PRINT \"HANDLED\"\n110 RESUME NEXT\n"

(* ERROR <n>, untrapped, raises the manual's own message for a defined
   number -- note this is the manual's exact wording ("Division by Zero
   (/0)"), not this interpreter's own cosmetically different "Division by
   zero" that "/" itself raises (see Error_catalog's alias note). *)
let test_error_statement_raises_a_defined_error () =
  check_failure "ERROR 11" ~line:10 ~message:"Division by Zero (/0)" "10 ERROR 11\n20 END\n"

(* ERROR <n> for a number the manual assigns no message of its own raises
   "Unprintable error" -- by design, not as a gap (spec/errors.json #21's
   note) -- and ERR still reports exactly the number given, 40, not
   anything recovered from that shared message. *)
let test_error_statement_with_an_undefined_code_is_unprintable () =
  check "ERROR 40, undefined code" " 40 \n 20 \n"
    "10 ON ERROR GOTO 100\n20 ERROR 40\n30 END\n\
     100 PRINT ERR\n110 PRINT ERL\n120 RESUME NEXT\n"

(* <integer> is documented as 0-255; outside that range this interpreter
   reads ERROR the same as every other range-checked argument in this
   library -- Illegal function call -- which the manual does not state for
   this specific case, so this is our own decision (ERR.ERROR, "partial"). *)
let test_error_statement_out_of_range () =
  check_failure "ERROR 256" ~line:10 ~message:"Illegal function call" "10 ERROR 256\n20 END\n"

(* An ordinary error with no ON ERROR GOTO ever installed still fails the
   program, exactly as before this subsystem existed -- the baseline this
   whole feature must not quietly break. *)
let test_untrapped_error_still_fails_the_program () =
  check_failure "no handler installed" ~line:20 ~message:"Type mismatch"
    "10 PRINT \"BEFORE\"\n20 A = \"X\" + 1\n30 PRINT \"NEVER\"\n"

(* RESUME executed while no error is being handled is itself an error
   (spec/errors.json #20) -- here with no ON ERROR GOTO installed at all,
   so it is untrapped and fails the program. *)
let test_resume_without_error_is_itself_an_error () =
  check_failure "bare RESUME, nothing to resume" ~line:10 ~message:"RESUME without error"
    "10 RESUME\n20 END\n"

(* The manual states plainly that no error interrupts a handler already
   running: an error raised inside one shows its own message and stops, it
   is never trapped a second time even though ON ERROR GOTO is still
   installed. *)
let test_an_error_inside_the_handler_is_not_trapped () =
  check_failure "error inside handler" ~line:100 ~message:"Division by zero"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 END\n100 B = 1/0\n110 RESUME NEXT\n"

(* "ON ERROR GOTO 0" executed *inside* the handler routine is a second,
   different case from the ordinary one above: rather than quietly
   disabling the handler and continuing, it shows the message of the
   original error that caused the trap (division by zero at line 20, not
   whatever is on line 110) and stops there. *)
let test_on_error_goto_zero_inside_the_handler_shows_the_original_error () =
  check_failure "ON ERROR GOTO 0 inside handler" ~line:20 ~message:"Division by zero"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 END\n\
     100 PRINT \"IN HANDLER\"\n110 ON ERROR GOTO 0\n120 PRINT \"NEVER\"\n"

(* No RESUME (spec/errors.json #19): control runs off the end of the
   listing while still inside the handler routine, which never reached
   RESUME, END or ON ERROR GOTO 0. There is no BASIC line left to blame, so
   line is 0 -- the same convention Error.to_string already documents for
   "no line number known". *)
let test_no_resume_when_the_handler_never_ends () =
  check_failure "handler falls off the end" ~line:0 ~message:"No RESUME"
    "10 ON ERROR GOTO 100\n20 A = 1/0\n30 END\n100 PRINT \"HANDLING\"\n"

let test_resume_cannot_be_used_as_an_array () =
  check_failure "RESUME(1)" ~line:10
    ~message:"RESUME is a reserved word and cannot be used as a variable name"
    "10 PRINT RESUME(1)\n20 END\n"

let test_error_cannot_be_used_as_an_array () =
  check_failure "ERROR(1)" ~line:10
    ~message:"ERROR is a reserved word and cannot be used as a variable name"
    "10 PRINT ERROR(1)\n20 END\n"

(* A missing statement separator after PRINT used to be reported as
   "PRINT is a reserved word and cannot be used as a variable name" -- wrong
   twice over, since nothing is being used as a variable and the listing has
   not misused PRINT at all. PRINT's item list handed every unrecognised
   token to the expression parser; it now stops at a keyword that cannot
   begin an expression, so the outer statement parser reports the missing
   separator, which is what the assignment path ("A=1 REM x") always said.

   Found by the citation sweep (tools/citation_coverage.py) reaching printed
   p.11, the special-symbols section, which nothing cited. *)
let test_missing_separator_after_print_is_not_a_variable_error () =
  check_failure "PRINT A PRINT B" ~line:10 ~message:"Unexpected token after statement"
    "10 PRINT \"a\" PRINT \"b\"\n20 END\n"

(* The apostrophe case, which was worse still: the lexer synthesises a
   Keyword "REM" for "'", so the message named a word the listing never
   contained. printed p.11 makes ' a substitute for REM, and REM is a
   statement, so a separator IS required -- the refusal is right and only
   the message was wrong. *)
let test_apostrophe_after_a_statement_names_the_separator_not_rem () =
  check_failure "PRINT then '" ~line:10 ~message:"Unexpected token after statement"
    "10 PRINT \"ok\" ' note\n20 END\n"

(* OP.INTDIV, ref-9801 printed p.20. The page's own two worked examples.
   23.75\\5 is the one that matters: 23.75 rounds to 24 and 24/5 = 4.8
   truncates to 4, so it pins BOTH halves of the rule at once -- rounding the
   quotient instead would give 5. *)
let test_integer_division_rounds_then_truncates () =
  check "10\\3" " 3 \n" "10 PRINT 10 \\ 3\n20 END\n";
  check "23.75\\5" " 4 \n" "10 PRINT 23.75 \\ 5\n20 END\n"

(* Level 6: tighter than MOD at 7, looser than * and / at 5 (printed p.25). *)
let test_integer_division_precedence () =
  check "6\\2*2 is 6\\4" " 1 \n" "10 PRINT 6 \\ 2 * 2\n20 END\n";
  check "7 MOD 5\\2 is 7 MOD 2" " 1 \n" "10 PRINT 7 MOD 5 \\ 2\n20 END\n";
  check "1+9\\2 is 1+4" " 5 \n" "10 PRINT 1 + 9 \\ 2\n20 END\n"

let test_integer_division_by_zero () =
  check_failure "1\\0" ~line:10 ~message:"Division by zero"
    "10 PRINT 1 \\ 0\n20 END\n"

(* PRINT.USING, ref-9801 printed p.128: a string containing Japanese cannot be
   edited by a string field. This printed a half-character and exited 0 until
   2026-08-18. Refusing is the page's rule; Illegal function call is ours. *)
let test_print_using_refuses_a_japanese_string_field () =
  check_failure "&  & on Japanese" ~line:10 ~message:"Illegal function call"
    "10 PRINT USING \"&  &\";\"\xe3\x81\x82\xe3\x81\x84\"\n20 END\n";
  check_failure "! on Japanese" ~line:10 ~message:"Illegal function call"
    "10 PRINT USING \"!\";\"\xe3\x81\x82\"\n20 END\n";
  (* "@" copies the string whole and so could not corrupt it, but the page
     draws no exception and calls all three fields 編集. *)
  check_failure "@ on Japanese" ~line:10 ~message:"Illegal function call"
    "10 PRINT USING \"@\";\"\xe3\x81\x82\"\n20 END\n"

(* The distinguishing inputs: the refusal must not swallow the cases the page
   says nothing against, or "it refuses Japanese" would be satisfiable by
   refusing everything. *)
let test_print_using_still_edits_ascii_and_copies_literals () =
  check "ASCII through &" "abc \n" "10 PRINT USING \"&  &\";\"abc\"\n20 END\n";
  (* Japanese as LITERAL text in the format string is copied, not edited. *)
  check "Japanese literal in the format" "\xe3\x81\x82  7\n"
    "10 PRINT USING \"\xe3\x81\x82###\";7\n20 END\n"

(* IN.INPUT, ref-9801 printed p.82. INPUT used OCaml's float_of_string until
   2026-08-18, so it accepted literals N88-BASIC never had. A typed "nan" put
   a NaN into a numeric variable; "1_000" read as 1000 and "0x10" as 16. It
   also rejected "1D3", a double-precision constant the manual defines, while
   accepting its single-precision sibling "1E3".

   It now shares DATA's whole-field reader. These are the distinguishing
   inputs -- the ones where OCaml's parser and a BASIC one disagree. *)
let prog = "10 INPUT A\n20 PRINT A\n30 END\n"

let test_input_refuses_non_basic_numbers () =
  List.iter
    (fun form ->
      check_answering ("INPUT " ^ form) [ form; "7" ] "? ?Redo from start\n?  7 \n" prog)
    [ "1_000"; "nan"; "inf"; "0x10" ]

let test_input_accepts_the_basic_numeric_forms () =
  check_answering "1D3" [ "1D3" ] "?  1000 \n" prog;
  check_answering "1E3" [ "1E3" ] "?  1000 \n" prog;
  check_answering "&HFF" [ "&HFF" ] "?  255 \n" prog;
  check_answering "-123" [ "-123" ] "? -123 \n" prog

let case n f = Alcotest.test_case n `Quick f

(* ---- The control-flow forms the manual documents and this interpreter used
   to refuse (spec/spec.md CTRL.GOTO, CTRL.RETURN, CTRL.IF, CTRL.FOR,
   CTRL.NEXT). Each was read off its page before being written. ---- *)

(* CTRL.GOTO (ref-9801 printed p.78-79 / PDF p.89-90). *)
let test_go_to_jumps_like_goto () =
  check "GO TO" "YES\n" "10 GO TO 30\n20 PRINT \"NO\";\n30 PRINT \"YES\"\n40 END\n"

(* CTRL.IF form 2 (ref-9801 printed p.80 / PDF p.91): the syntax box gives
   GOTO's branch as a line number alone, unlike THEN's, which may be a
   statement. ELSE is shared by both forms. *)
let test_if_goto_without_then () =
  check "IF GOTO" "YES\n" "10 IF 1 GOTO 40\n20 PRINT \"NO\";\n30 END\n40 PRINT \"YES\"\n50 END\n"

let test_if_goto_takes_an_else () =
  check "IF GOTO ELSE" "ELSE\n"
    "10 IF 0 GOTO 40 ELSE PRINT \"ELSE\"\n20 END\n40 PRINT \"THEN\"\n50 END\n"

(* CTRL.RETURN (ref-9801 printed p.136 / PDF p.147): RETURN <line> ends the
   subroutine but resumes at the named line rather than after the GOSUB. *)
let test_return_to_a_line () =
  check "RETURN <line>" "ABC\n"
    "10 PRINT \"A\";\n20 GOSUB 100\n30 PRINT \"NOTREACHED\";\n40 END\n100 PRINT \"B\";\n110 RETURN 200\n200 PRINT \"C\"\n210 END\n"

(* CTRL.NEXT (ref-9801 printed p.74 / PDF p.85): the manual's own example. *)
let test_next_closes_several_loops () =
  check "NEXT K, J" " 11  12  21  22 \n"
    "10 FOR J=1 TO 2\n20 FOR K=1 TO 2\n30 PRINT J*10+K;\n40 NEXT K, J\n50 PRINT\n60 END\n"

(* The reason NEXT's comma form is expanded into one NEXT per variable rather
   than kept as a single node naming both: an inner loop whose bound fails on
   entry skips to just past the NEXT closing *its* loop, and the NEXT closing
   the outer loop must still be left to run. A single combined node would
   swallow both and strand the outer FOR. *)
let test_next_list_still_closes_the_outer_loop_when_the_inner_never_runs () =
  check "NEXT K, J with an empty inner loop" "DONE\n"
    "10 FOR J=1 TO 2\n20 FOR K=1 TO 0\n30 PRINT \"NEVER\";\n40 NEXT K, J\n50 PRINT \"DONE\"\n60 END\n"

(* CTRL.FOR (ref-9801 printed p.74 / PDF p.85): the page says in as many words
   that the loop variable must be integer or single precision. The manual names
   no error for the violation, so "Type mismatch" is ours, recorded as ours. *)
let test_for_refuses_a_double_control_variable () =
  check_failure "double loop variable" ~line:10 ~message:"Type mismatch"
    "10 FOR I#=1 TO 3\n20 NEXT I#\n30 END\n"

(* The same refusal has to reach a suffix-less name made Double by DEFDBL,
   which is why it is tested against the environment and not the spelling. *)
let test_for_refuses_a_defdbl_control_variable () =
  check_failure "DEFDBL loop variable" ~line:20 ~message:"Type mismatch"
    "10 DEFDBL I\n20 FOR I=1 TO 3\n30 NEXT I\n40 END\n"

let test_for_accepts_integer_and_single_control_variables () =
  check "integer and single loop variables" " 1  2 \n 1  2 \n"
    "10 FOR I%=1 TO 2\n20 PRINT I%;\n30 NEXT I%\n40 PRINT\n50 FOR S!=1 TO 2\n60 PRINT S!;\n70 NEXT S!\n80 PRINT\n90 END\n"

(* ---- Labels (ref-9801 printed p.29 / PDF p.42, §13 ラベル名). A label name
   stands in for a line number at a branch target; it is defined by "*NAME"
   opening a line, colon-separated from the rest. ---- *)

(* The manual's own worked example, its labelled version, with the INPUT
   replaced by an assignment so the case needs no console. *)
let manual_label_example a =
  Printf.sprintf
    "10 A=%s\n20 IF A<0 THEN *MINUS\n30 IF A>0 THEN *PLUS\n40 PRINT \"zero\"\n50 GOTO *EXIT\n60 *PLUS : PRINT \"plus\"\n70 GOTO *EXIT\n80 *MINUS : PRINT \"minus\"\n90 *EXIT : END\n"
    a

let test_manual_label_example_negative () =
  check "manual example, negative" "minus\n" (manual_label_example "-5")

let test_manual_label_example_zero () = check "manual example, zero" "zero\n" (manual_label_example "0")
let test_manual_label_example_positive () = check "manual example, positive" "plus\n" (manual_label_example "5")

(* "*" is also multiplication. A label is only read where a line reference or
   a statement may begin, so an expression is untouched. *)
let test_multiplication_is_unaffected_by_labels () =
  check "multiplication" " 42  6 -8 \n"
    "10 A=6 : B=7\n20 PRINT A*B; 2*3; -4*2\n30 END\n"

let test_gosub_and_return_take_labels () =
  check "GOSUB *SUB" "IN\nBACK\n"
    "10 GOSUB *SUB\n20 PRINT \"BACK\"\n30 END\n40 *SUB : PRINT \"IN\"\n50 RETURN\n"

let test_a_label_can_be_jumped_to_backwards () =
  check "backward jump" " 3 \n"
    "10 *LOOP : C=C+1\n20 IF C<3 THEN *LOOP\n30 PRINT C\n40 END\n"

(* The manual gives labels as a substitute for a line number and names no
   error of their own, so an undefined one is reported exactly as an
   undefined line number is. That reuse is ours. *)
let test_undefined_label_is_an_undefined_line_number () =
  check_failure "undefined label" ~line:10 ~message:"Undefined line number"
    "10 GOTO *NOWHERE\n20 END\n"

(* Every definition the manual writes opens its line. One anywhere else would
   read as defined and be unreachable, so it is refused -- ours, not the
   manual's, which simply does not address the case. *)
let test_a_label_must_open_its_line () =
  let e = run_expecting_failure "mid-line label" "10 PRINT \"A\" : *MID : PRINT \"B\"\n20 END\n" in
  Alcotest.(check bool)
    "names the label"
    true
    (String.length e.Error.message > 0
    && String.sub e.Error.message 0 4 = "*MID")

let test_a_label_inside_a_then_branch_is_refused () =
  let e = run_expecting_failure "hidden label" "10 IF 1 THEN PRINT \"A\" : *HID\n20 END\n" in
  Alcotest.(check bool) "names the label" true (String.sub e.Error.message 0 4 = "*HID")

let () =
  Alcotest.run "interp"
    [ ( "print",
        [ case "number" test_print_number;
          case "string" test_print_string_has_no_padding;
          case "semicolon" test_semicolon_packs;
          case "comma" test_comma_uses_zones;
          case "trailing semicolon" test_trailing_semicolon_suppresses_newline;
          case "trailing comma" test_trailing_comma_tabs_without_a_newline;
          case "bare PRINT" test_bare_print_emits_a_newline;
          case "TAB" test_tab_pads_to_a_one_based_column;
          case "TAB behind the cursor" test_tab_behind_the_cursor_emits_nothing;
          case "non-positive TAB" test_a_non_positive_tab_emits_nothing;
          case "trailing TAB" test_tab_at_the_end_of_a_list_still_breaks_the_line;
          case "LPRINT" test_lprint_goes_to_the_printer;
          case "LPRINT default sink" test_lprint_defaults_to_the_screen_sink;
          case "LPRINT column" test_lprint_keeps_its_own_column;
          case "WRITE quotes and separates with commas"
            test_write_quotes_strings_and_commas_between_items;
          case "WRITE treats ; like ," test_write_treats_comma_and_semicolon_the_same;
          case "WRITE trailing newline" test_write_emits_a_trailing_newline;
          case "bare WRITE is a parse error" test_bare_write_is_a_parse_error ] );
      ( "using",
        [ case "formats its value" test_print_using_formats_its_value;
          case "one value per field" test_print_using_takes_one_value_per_field;
          case "no free-format padding" test_print_using_does_not_pad_like_free_format;
          case "trailing semicolon"
            test_print_using_trailing_semicolon_suppresses_the_newline;
          case "restart for extra values" test_print_using_reuses_the_format_for_extra_values;
          case "TAB before USING" test_a_tab_before_using_positions_the_text;
          case "TAB after a value" test_a_tab_after_a_value_in_a_using_list_is_refused;
          case "string in a # field" test_a_string_in_a_numeric_field_is_a_type_error;
          case "LPRINT USING" test_lprint_using_reaches_the_printer ] );
      ( "expressions",
        [ case "precedence" test_arithmetic_precedence;
          case "power and unary minus" test_power_and_unary_minus;
          case "variables" test_variables;
          case "unset variables" test_unset_variables_are_zero_and_empty;
          case "LET" test_let_keyword_is_accepted;
          case "array elements" test_array_elements;
          case "concatenation" test_string_concatenation;
          case "string equality" test_string_equality;
          case "comparison" test_comparison_yields_minus_one;
          case "relational operators" test_relational_operators;
          case "logical operators" test_logical_operators;
          case "intrinsics" test_intrinsics;
          case "division by zero" test_division_by_zero;
          case "type mismatch" test_type_mismatch;
          case "ordering strings" test_ordering_strings_is_a_type_mismatch;
          case "unknown function" test_unknown_function;
          case "subscript error line" test_subscript_error_carries_the_line ] );
      ( "numeric types",
        [ case "integer boundary values" test_integer_boundary_values_are_accepted;
          case "integer overflow above" test_integer_assignment_overflow_above;
          case "integer overflow below" test_integer_assignment_overflow_below;
          case "fractional assignment to integer rounds"
            test_fractional_assignment_to_integer_rounds;
          case "DEFINT makes unsuffixed names integer"
            test_defint_makes_unsuffixed_names_integer;
          case "explicit suffix overrides DEFINT" test_explicit_suffix_overrides_defint;
          case "DEFSTR makes unsuffixed names strings"
            test_defstr_makes_unsuffixed_names_strings;
          case "coercion in a mixed expression" test_coercion_in_a_mixed_expression;
          case "int/int division is real" test_division_of_two_integers_is_real;
          case "single vs double significant digits"
            test_single_vs_double_significant_digits;
          case "exponent form switches both directions"
            test_exponent_form_switches_both_directions;
          case "leading and trailing space by sign" test_leading_and_trailing_space_by_sign
        ] );
      ( "control",
        [ case "GOTO and IF" test_goto_and_if;
          case "IF ELSE" test_if_else;
          case "IF without ELSE" test_if_without_else_falls_through;
          case "jump abandons its branch" test_a_jump_abandons_the_rest_of_its_branch;
          case "jump abandons an ELSE branch"
            test_a_jump_from_the_else_branch_abandons_its_tail;
          case "nested jump abandons the outer branch"
            test_a_nested_jump_abandons_the_outer_branch_tail;
          case "END abandons its branch" test_end_inside_a_branch_abandons_its_tail;
          case "colon" test_colon_separates_statements;
          case "REM" test_rem_is_a_no_op;
          case "END" test_end_stops_before_later_lines;
          case "STOP names its line" test_stop_halts_and_names_its_line;
          case "implicit stop" test_falls_off_end_without_END;
          case "line number order" test_lines_run_in_number_order_not_file_order;
          case "error line" test_error_carries_line;
          case "parse error" test_a_parse_error_refuses_to_run;
          case "error span" test_runtime_errors_carry_a_span;
          case "GOTO span underlines the digits"
            test_an_undefined_line_number_underlines_the_digits;
          case "run takes a parsed program" test_run_takes_an_already_parsed_program ] );
      ( "loops",
        [ case "FOR" test_for_loop;
          case "zero iterations" test_for_zero_iterations;
          case "negative STEP" test_for_negative_step;
          case "fractional STEP" test_for_fractional_step;
          case "empty single-line body" test_single_line_loop_with_empty_body;
          case "nested FOR" test_nested_for;
          case "NEXT by name matches past an open inner frame"
            test_next_by_name_matches_past_an_open_inner_frame;
          case "NEXT by name discards the frames it skips"
            test_next_by_name_discards_the_frames_it_skips;
          case "NEXT without FOR" test_next_without_for;
          case "FOR without NEXT" test_for_without_next ] );
      ( "subroutines",
        [ case "GOSUB/RETURN" test_gosub_return;
          case "nested GOSUB" test_nested_gosub;
          case "RETURN without GOSUB" test_return_without_gosub ] );
      ( "while",
        [ case "false from the start never runs" test_while_false_from_the_start_never_runs;
          case "loop" test_while_loop;
          case "nested" test_nested_while;
          case "WEND without WHILE" test_wend_without_while;
          case "WHILE without WEND" test_while_without_wend ] );
      ( "on-goto-gosub",
        [ case "in range" test_on_goto_in_range;
          case "zero falls through" test_on_goto_zero_falls_through;
          case "past the end falls through" test_on_goto_past_the_end_falls_through;
          case "negative is Illegal function call"
            test_on_goto_negative_is_illegal_function_call;
          case "ON GOSUB then RETURN" test_on_gosub_returns ] );
      ( "swap",
        [ case "scalars" test_swap_scalars;
          case "array elements" test_swap_array_elements;
          case "strings" test_swap_strings;
          case "type mismatch" test_swap_type_mismatch ] );
      ( "arrays",
        [ case "DIM" test_dim_and_arrays;
          case "matrix" test_two_dimensional_array;
          case "0..N inclusive" test_dim_allocates_zero_through_n;
          case "run-time bound" test_dim_accepts_a_run_time_bound;
          case "negative bound" test_a_negative_dim_bound_is_refused;
          case "re-DIM without ERASE is Duplicate Difinition"
            test_redim_without_erase_is_a_duplicate_definition;
          case "DIM after auto-vivify is Duplicate Difinition"
            test_dim_after_auto_vivify_is_a_duplicate_definition;
          case "ERASE then re-DIM" test_erase_then_redim;
          case "ERASE then auto-vivify" test_erase_then_auto_vivify ] );
      ( "option-base",
        [ case "forbids index 0" test_option_base_one_forbids_index_zero;
          case "allows up to the declared bound"
            test_option_base_one_allows_up_to_the_declared_bound;
          case "default base is 0" test_default_base_is_zero;
          case "re-specified is Duplicate Difinition"
            test_option_base_respecified_is_a_duplicate_definition;
          case "no effect once an array exists"
            test_option_base_after_an_array_exists_has_no_effect;
          case "CLEAR lets it be set again" test_clear_lets_option_base_be_set_again ] );
      ( "clear",
        [ case "resets scalars" test_clear_resets_scalars;
          case "resets string scalars" test_clear_resets_string_scalars;
          case "arguments ignored" test_clear_with_arguments_ignores_them;
          case "resets arrays" test_clear_resets_arrays ] );
      ( "data",
        [ case "READ" test_read_data;
          case "line number order" test_data_is_gathered_in_line_number_order;
          case "DATA inside a THEN branch" test_data_inside_a_then_branch_is_gathered;
          case "DATA inside an ELSE branch" test_data_inside_an_else_branch_is_gathered;
          case "string datum" test_read_takes_a_string_datum;
          case "READ into an array" test_read_into_an_array_element;
          case "RESTORE" test_restore;
          case "RESTORE <line>" test_restore_to_a_line_starts_at_that_lines_data;
          case "RESTORE <line> with no data there"
            test_restore_to_a_line_without_data_starts_at_the_next_one;
          case "RESTORE past the end"
            test_restore_past_every_data_line_leaves_nothing_to_read;
          case "out of DATA" test_out_of_data;
          case "DATA is a no-op when executed" test_a_data_line_executes_as_a_no_op ] );
      ( "functions",
        [ case "DEF FN" test_def_fn;
          case "no parameter leak" test_def_fn_does_not_leak_parameter;
          case "two parameters" test_def_fn_with_two_parameters;
          case "arguments evaluated first"
            test_def_fn_evaluates_its_arguments_before_binding_them;
          case "wrong number of arguments" test_def_fn_wrong_number_of_arguments;
          case "undefined until DEF runs" test_a_function_is_undefined_until_its_def_runs;
          case "SIN" test_sin;
          case "COS" test_cos;
          case "TAN" test_tan;
          case "ATN" test_atn;
          case "EXP(0)" test_exp_of_zero_is_one;
          case "EXP(1)" test_exp_of_one_is_e;
          case "LOG(1)" test_log_of_one_is_zero;
          case "LOG(0) domain error" test_log_at_zero_is_a_domain_error;
          case "LOG(-1) domain error" test_log_of_a_negative_number_is_a_domain_error;
          case "FIX vs INT, negative" test_fix_and_int_differ_for_a_negative_fraction;
          case "FIX vs INT, positive" test_fix_and_int_agree_for_a_positive_fraction;
          case "CINT rounds ties away from zero" test_cint_rounds_ties_away_from_zero;
          case "CINT overflow" test_cint_overflow;
          case "CSNG round-trips" test_csng_round_trips_a_representable_value;
          case "CDBL widens without adding precision" test_cdbl_widens_without_adding_precision;
          case "LEN(SPACE$(3))" test_space_dollar_length;
          case "SPACE$ contents" test_space_dollar_is_all_spaces;
          case "SPACE$ out of range" test_space_dollar_out_of_range;
          case "SPC inserts spaces" test_spc_inserts_literal_spaces;
          case "SPC negative is zero" test_spc_with_a_negative_argument_is_zero;
          case "POS/CSRLIN track the writer" test_pos_and_csrlin_track_the_print_writer;
          case "RND(0) repeats the last value" test_rnd_zero_repeats_the_last_value;
          case "RND negative seed is deterministic" test_rnd_negative_seed_is_deterministic;
          case "RND default sequence reproducible across runs"
            test_rnd_default_sequence_is_reproducible_across_runs;
          case "RANDOMIZE reseeds deterministically" test_randomize_same_seed_reseeds_deterministically;
          case "RANDOMIZE different seeds differ" test_randomize_different_seeds_draw_different_values;
          case "RANDOMIZE overflow above" test_randomize_overflow_above;
          case "RANDOMIZE overflow below" test_randomize_overflow_below;
          case "bare RANDOMIZE reads a seed from input" test_randomize_bare_reads_a_seed_from_input;
          case "bare RANDOMIZE with no input fails" test_randomize_bare_out_of_input_fails;
          case "ERR is 0 before any error" test_err_is_zero_before_any_error;
          case "ERL is 0 before any error" test_erl_is_zero_before_any_error;
          case "reserved word as a scalar" test_reserved_word_as_a_scalar_is_an_error;
          case "reserved word as a DIM array" test_reserved_word_as_a_dim_array_is_an_error;
          case "reserved word as a FOR variable" test_reserved_word_as_a_for_variable_is_an_error;
          case "out-of-scope word as an array" test_out_of_scope_word_as_an_array_is_an_error;
          case "names containing reserved words" test_names_containing_reserved_words_are_ordinary_variables;
          case "FOR/TO/THEN/ELSE alongside such names"
            test_for_to_then_else_still_work_alongside_such_names;
          case "variable name with a period" test_variable_name_may_contain_a_period;
          case "variable name at the 40-character limit" test_variable_name_at_the_forty_character_limit;
          case "variable names are case-insensitive" test_variable_names_are_case_insensitive;
          case "exact reserved word still refused" test_exact_reserved_word_is_still_refused_as_a_variable;
          case "variable name may not begin with FN" test_variable_name_may_not_begin_with_fn;
          case "LEFT$" test_left_dollar;
          case "LEFT$ past the end" test_left_dollar_past_the_end_takes_the_whole_string;
          case "LEFT$ negative count" test_left_dollar_with_a_negative_count;
          case "LEFT$ count above 255" test_left_dollar_count_above_255;
          case "RIGHT$" test_right_dollar;
          case "RIGHT$ past the end" test_right_dollar_past_the_end_takes_the_whole_string;
          case "RIGHT$ zero" test_right_dollar_zero_is_the_null_string;
          case "RIGHT$ negative count" test_right_dollar_with_a_negative_count;
          case "LEN" test_len;
          case "LEN of the null string" test_len_of_the_null_string;
          case "ASC" test_asc;
          case "ASC of the null string" test_asc_of_the_null_string;
          case "MID$ function, 2 args" test_mid_dollar_function_two_args;
          case "MID$ function, 3 args" test_mid_dollar_function_three_args;
          case "MID$ function, length past the end" test_mid_dollar_function_length_past_the_end;
          case "MID$ function, start past the end" test_mid_dollar_function_start_past_the_end;
          case "MID$ function, start out of range" test_mid_dollar_function_start_out_of_range;
          case "MID$ statement" test_mid_dollar_statement_replaces_in_place;
          case "MID$ statement, replacement shorter than the field"
            test_mid_dollar_statement_replacement_shorter_than_the_field;
          case "MID$ statement, replacement longer than the field"
            test_mid_dollar_statement_replacement_longer_than_the_field;
          case "MID$ statement, omitted length"
            test_mid_dollar_statement_omitted_length_uses_the_whole_replacement;
          case "MID$ statement, omitted length never grows the field"
            test_mid_dollar_statement_omitted_length_still_never_grows_the_field;
          case "MID$ statement, start past the end is a no-op"
            test_mid_dollar_statement_start_past_the_end_is_a_no_op;
          case "MID$ statement, start out of range" test_mid_dollar_statement_start_out_of_range;
          case "INSTR finds a substring" test_instr_finds_a_substring;
          case "INSTR not found" test_instr_not_found_is_zero;
          case "INSTR with a start position" test_instr_with_a_start_position;
          case "INSTR with a null needle" test_instr_with_a_null_needle_is_the_position;
          case "STR$ positive" test_str_dollar_positive_has_a_leading_space;
          case "STR$ negative" test_str_dollar_negative_has_a_leading_minus;
          case "STR$ zero" test_str_dollar_zero_has_a_leading_space;
          case "STRING$ from a character" test_string_dollar_from_a_character;
          case "STRING$ uses only the first character"
            test_string_dollar_uses_only_the_first_character;
          case "STRING$ from a character code" test_string_dollar_from_a_character_code;
          case "STRING$ code out of range" test_string_dollar_code_out_of_range;
          case "HEX$" test_hex_dollar;
          case "HEX$ negative" test_hex_dollar_negative;
          case "HEX$ out of range" test_hex_dollar_out_of_range;
          case "OCT$" test_oct_dollar;
          case "OCT$ negative" test_oct_dollar_negative;
          case "CHR$" test_chr_dollar;
          case "CHR$ out of range" test_chr_dollar_out_of_range;
          case "VAL" test_val;
          case "VAL &H" test_val_parses_hex;
          case "VAL of text" test_val_of_text_is_zero;
          case "VAL prefix" test_val_stops_at_the_first_non_numeric_character ] );
      ( "input",
        [ case "prompt" test_input_with_a_prompt;
          case "no prompt" test_input_without_a_prompt_still_asks;
          case "string variable" test_input_into_a_string_variable_keeps_the_text;
          case "one line split across variables"
            test_input_splits_one_line_across_its_variables;
          case "quoted field keeps commas and spaces"
            test_input_quoted_field_keeps_its_commas_and_spaces;
          case "empty fields" test_input_empty_fields_are_zero_and_the_null_string;
          case "redo on a bad answer" test_input_redoes_a_bad_answer_instead_of_failing;
          case "redo on a wrong field count"
            test_input_redoes_when_the_field_count_is_wrong;
          case "never fits, runs out" test_input_of_a_non_number_eventually_runs_out;
          case "out of input" test_input_that_runs_out_is_an_error;
          case "LINE INPUT prompt has no ?"
            test_line_input_with_a_prompt_adds_no_question_mark;
          case "LINE INPUT no prompt" test_line_input_without_a_prompt_asks_nothing;
          case "LINE INPUT keeps commas and quotes"
            test_line_input_keeps_commas_and_quotes_verbatim;
          case "LINE INPUT out of input" test_line_input_that_runs_out_is_an_error;
          case "LINE INPUT into numeric is a type error"
            test_line_input_into_a_numeric_variable_is_a_type_error ] );
      ( "display",
        [ case "recorded, not drawn" test_display_statements_are_recorded;
          case "WIDTH columns only" test_width_takes_columns_alone;
          case "LINE with no start point" test_line_without_a_start_point;
          case "SCREEN slots are each optional" test_screen_slots_are_each_optional;
          case "SCREEN rejects an untabulated mode" test_screen_rejects_a_mode_outside_the_table;
          case "LOCATE slots are each optional" test_locate_slots_are_each_optional;
          case "CONSOLE slots are each optional" test_console_slots_are_each_optional;
          case "WIDTH arity" test_width_with_more_arguments_than_we_record ] );
      ( "pset/preset",
        [ case "PSET records point and colour" test_pset_is_recorded_with_its_colour;
          case "PSET without a colour" test_pset_without_a_colour_records_none;
          case "PSET STEP is relative" test_pset_step_records_a_relative_point;
          case "PRESET records" test_preset_is_recorded ] );
      ( "color",
        [ case "all four slots" test_color_records_all_four_slots;
          case "leading slots skipped" test_color_skips_leading_slots_on_bare_commas;
          case "bare COLOR initialises" test_bare_color_initialises_the_palette;
          case "COLOR ,,, is still [1]" test_color_with_only_commas_is_still_the_first_form;
          case "[2] COLOR recorded" test_color_palette_assignment_is_recorded;
          case "[2] COLOR needs both args" test_color_palette_assignment_needs_both_arguments;
          case "[2] COLOR refuses an out-of-range code"
            test_color_palette_assignment_refuses_an_out_of_range_code;
          case "[2] COLOR refuses an out-of-range palette"
            test_color_palette_assignment_refuses_an_out_of_range_palette;
          case "palette-mode slot refused" test_color_palette_mode_argument_is_refused ] );
      ( "INPUT numeric forms",
        [ case "refuses non-BASIC numbers" test_input_refuses_non_basic_numbers;
          case "accepts the BASIC forms" test_input_accepts_the_basic_numeric_forms ] );
      ( "PRINT USING and Japanese",
        [ case "string fields refuse it" test_print_using_refuses_a_japanese_string_field;
          case "ASCII and literals unaffected"
            test_print_using_still_edits_ascii_and_copies_literals ] );
      ( "integer division",
        [ case "rounds operands then truncates" test_integer_division_rounds_then_truncates;
          case "level 6 precedence" test_integer_division_precedence;
          case "zero divisor" test_integer_division_by_zero ] );
      ( "point",
        [ case "asks the handler" test_point_asks_the_handler_and_returns_its_answer;
          case "default reports unlit" test_point_with_no_handler_reports_unlit;
          case "wrong arity" test_point_wrong_arity;
          case "statement records an LP move" test_point_statement_records_an_lp_move;
          case "statement STEP form" test_point_statement_step_form;
          case "[1] POINT reads the LP" test_point_function_reads_the_lp_through_the_handler;
          case "[1] POINT refuses a bad code"
            test_point_function_refuses_an_out_of_range_code ] );
      ( "error handling",
        [ case "RESUME NEXT continues after the failing statement"
            test_trapped_division_by_zero_continues_with_resume_next;
          case "ERR/ERL inside the handler" test_err_and_erl_inside_the_handler;
          case "RESUME <line>" test_resume_line;
          case "bare RESUME retries" test_bare_resume_retries_the_failing_statement;
          case "ON ERROR GOTO 0 restores default behaviour"
            test_on_error_goto_zero_restores_default_behaviour;
          case "ERROR <n>, defined code" test_error_statement_raises_a_defined_error;
          case "ERROR <n>, undefined code" test_error_statement_with_an_undefined_code_is_unprintable;
          case "ERROR <n> out of range" test_error_statement_out_of_range;
          case "untrapped error still fails" test_untrapped_error_still_fails_the_program;
          case "RESUME without error" test_resume_without_error_is_itself_an_error;
          case "error inside the handler is not trapped"
            test_an_error_inside_the_handler_is_not_trapped;
          case "ON ERROR GOTO 0 inside the handler shows the original error"
            test_on_error_goto_zero_inside_the_handler_shows_the_original_error;
          case "No RESUME" test_no_resume_when_the_handler_never_ends;
          case "RESUME as an array" test_resume_cannot_be_used_as_an_array;
          case "ERROR as an array" test_error_cannot_be_used_as_an_array;
          case "missing separator after PRINT"
            test_missing_separator_after_print_is_not_a_variable_error;
          case "apostrophe after a statement"
            test_apostrophe_after_a_statement_names_the_separator_not_rem ] );
      ( "control-flow forms",
        [ case "GO TO" test_go_to_jumps_like_goto;
          case "IF GOTO" test_if_goto_without_then;
          case "IF GOTO ELSE" test_if_goto_takes_an_else;
          case "RETURN <line>" test_return_to_a_line;
          case "NEXT K, J" test_next_closes_several_loops;
          case "NEXT list with an empty inner loop"
            test_next_list_still_closes_the_outer_loop_when_the_inner_never_runs;
          case "FOR refuses a double variable" test_for_refuses_a_double_control_variable;
          case "FOR refuses a DEFDBL variable" test_for_refuses_a_defdbl_control_variable;
          case "FOR accepts integer and single"
            test_for_accepts_integer_and_single_control_variables ] );
      ( "labels",
        [ case "manual example, negative" test_manual_label_example_negative;
          case "manual example, zero" test_manual_label_example_zero;
          case "manual example, positive" test_manual_label_example_positive;
          case "multiplication unaffected" test_multiplication_is_unaffected_by_labels;
          case "GOSUB and RETURN take labels" test_gosub_and_return_take_labels;
          case "backward jump to a label" test_a_label_can_be_jumped_to_backwards;
          case "undefined label" test_undefined_label_is_an_undefined_line_number;
          case "a label must open its line" test_a_label_must_open_its_line;
          case "a label inside THEN is refused" test_a_label_inside_a_then_branch_is_refused ] )
    ]
