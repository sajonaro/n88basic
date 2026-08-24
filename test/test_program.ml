open N88basic

let line_numbers (p : Program.t) : int list =
  Array.to_list (Array.map (fun (l : Program.line) -> l.number) p.lines)

let test_sorts_lines () =
  let p, errors = Program.of_source "20 END\n10 A=1\n" in
  Alcotest.(check int) "no errors" 0 (List.length errors);
  Alcotest.(check (list int)) "sorted" [ 10; 20 ] (line_numbers p)

let test_blank_lines_ignored () =
  let p, errors = Program.of_source "10 A=1\n\n   \n20 END\n" in
  Alcotest.(check int) "no errors" 0 (List.length errors);
  Alcotest.(check int) "two lines" 2 (Array.length p.lines)

let test_index_lookup () =
  let p, errors = Program.of_source "10 A=1\n20 END\n" in
  Alcotest.(check int) "no errors" 0 (List.length errors);
  Alcotest.(check (option int)) "line 20 is index 1" (Some 1)
    (Program.index_of_line p 20);
  Alcotest.(check (option int)) "line 99 absent" None (Program.index_of_line p 99)

let test_recovers_from_a_bad_line () =
  let prog, errors = Program.of_source "10 A=1\n20 PRINT )\n30 B=2\n" in
  Alcotest.(check int) "one error" 1 (List.length errors);
  Alcotest.(check int) "error line" 20 (List.hd errors).line;
  Alcotest.(check (list int)) "good lines survive" [ 10; 30 ] (line_numbers prog)

let test_reports_every_bad_line () =
  let _, errors = Program.of_source "10 PRINT )\n20 A=1\n30 PRINT (\n" in
  Alcotest.(check int) "two errors" 2 (List.length errors);
  Alcotest.(check (list int)) "both lines named" [ 10; 30 ]
    (List.map (fun (e : Error.t) -> e.line) errors)

let test_parse_error_carries_a_span () =
  let _, errors = Program.of_source "10 A=1\n20 PRINT )\n" in
  match (List.hd errors).span with
  | Some s -> Alcotest.(check int) "span line" 1 s.Span.line
  | None -> Alcotest.fail "parse errors must carry a span"

let test_missing_line_number_is_an_error_not_an_exception () =
  let prog, errors = Program.of_source "PRINT 1\n10 A=1\n" in
  Alcotest.(check int) "one error" 1 (List.length errors);
  Alcotest.(check int) "the good line survives" 1 (Array.length prog.lines)

let test_crlf_source () =
  let prog, errors = Program.of_source "10 A=1\r\n20 END\r\n" in
  Alcotest.(check int) "no errors" 0 (List.length errors);
  Alcotest.(check (list int)) "both lines" [ 10; 20 ] (line_numbers prog)

(* REVIEW FINDING 1: a lexer failure on a numbered line must report that
   BASIC line, not 0. "30" is a real leading line number; the backtick is
   unlexable (it lexes as neither a keyword, an identifier, nor
   punctuation). This test used "?" until "?" became PRINT's short form
   (NUM/PRINT.BASIC, ref-9801 printed p.125) and stopped being unlexable
   at all -- the character had to change, the property being tested did
   not. *)
let test_lex_failure_reports_the_line_it_occurred_on () =
  let _, errors = Program.of_source "10 A=1\n30 `\n" in
  Alcotest.(check int) "one error" 1 (List.length errors);
  Alcotest.(check int) "reports BASIC line 30, not 0" 30 (List.hd errors).line

(* RE-REVIEW FINDING: the leading-digit-run fallback used by finding 1 must
   never raise, even when the run is too long for [int]. Without
   [int_of_string_opt] this line's 20-digit line number, combined with the
   unlexable backtick, made [int_of_string] escape [of_source]'s recovery fold
   entirely as an uncaught [Failure] instead of being recorded as an
   ordinary error. *)
let test_oversized_leading_number_does_not_escape_recovery () =
  let _, errors = Program.of_source "99999999999999999999 `\n" in
  Alcotest.(check int) "one recorded error, no exception" 1 (List.length errors)

(* REVIEW FINDING 2: a parse-error span must be token-precise, not a
   whole-line span that always renders as column 1. The stray ")" here sits
   in the middle of the line, at column 14 (1-based; start_col 13). *)
let test_parse_error_span_is_token_precise () =
  let _, errors = Program.of_source "10 A=1\n20 PRINT 1 + )\n" in
  match (List.hd errors).span with
  | Some s ->
      Alcotest.(check (pair int int)) "points at the stray )" (13, 14)
        (s.Span.start_col, s.Span.end_col)
  | None -> Alcotest.fail "parse errors must carry a span"

(* REVIEW FINDING 3: [number_span] covers just the line-number token, not
   the whole line — this must hold even when the line is indented, so
   start_col is not 0. *)
let test_number_span_covers_the_line_number_token () =
  let p, errors = Program.of_source "  10 A=1\n" in
  Alcotest.(check int) "no errors" 0 (List.length errors);
  let ns = p.lines.(0).Program.number_span in
  Alcotest.(check int) "line" 0 ns.Span.line;
  Alcotest.(check (pair int int)) "just the digits, after the indent" (2, 4)
    (ns.Span.start_col, ns.Span.end_col)

(* REVIEW FINDING 4: with no BASIC line number to report, the message must
   not fabricate "in line 0". *)
let test_missing_line_number_message_omits_the_line_clause () =
  let e : Error.t = { line = 0; message = "boom"; span = None; code = None } in
  Alcotest.(check string) "no fabricated line number" "boom" (Error.to_string e)

let case n f = Alcotest.test_case n `Quick f

(* ref-9801 printed p.9 SS3: line numbers are integers from 1 to 65529. The
   manual states the range outright, so this enforces its rule rather than
   inventing one. Nothing cited that page until the citation sweep
   (tools/citation_coverage.py) reported it, and both limits it states were
   unenforced -- line 0, 65530 and 99999 all ran. *)
let error_messages source =
  List.map (fun (e : Error.t) -> e.Error.message) (snd (Program.of_source source))

let out_of_range = "Line number must be between 1 and 65529"

let test_line_number_lower_bound () =
  Alcotest.(check (list string)) "line 0 is refused" [ out_of_range ] (error_messages "0 END\n");
  Alcotest.(check (list string)) "line 1 is accepted" [] (error_messages "1 END\n")

let test_line_number_upper_bound () =
  Alcotest.(check (list string))
    "65529 is accepted" [] (error_messages "65529 END\n");
  Alcotest.(check (list string))
    "65530 is refused" [ out_of_range ] (error_messages "65530 END\n")

(* printed p.9 SS2: a line, its line number included, holds statements within
   255 BYTES -- bytes, not characters, so this measures the raw text. *)
let test_line_length_limit () =
  let line n = "10 REM " ^ String.make n 'x' ^ "\n" in
  Alcotest.(check (list string)) "exactly 255 bytes is accepted" [] (error_messages (line 248));
  Alcotest.(check (list string))
    "256 bytes is refused" [ "Line is longer than 255 bytes" ] (error_messages (line 249))

(* ref-9801 printed p.30, section 13: a name that opens more than one line is
   "Duplicate label", detected when RUN begins and BEFORE any line executes,
   so a listing carrying one does not run at all.

   This replaced a "first definition wins" reading justified by "the manual
   does not address it either way". It does address it -- section 13 runs onto
   p.30 and the earlier reading stopped at the page break. Nothing cited p.30
   until tools/citation_coverage.py reported it. *)
let test_duplicate_label_is_refused () =
  Alcotest.(check (list string))
    "the same name opening two lines" [ "Duplicate label" ]
    (error_messages "10 *L\n20 PRINT 1\n30 *L\n");
  Alcotest.(check (list string))
    "distinct names are fine" [] (error_messages "10 *A\n20 *B\n")

(* The same page says this error names no line number: "エラー箇所を示す
   〈行番号〉はともないません". Line 0 is this codebase's spelling of that. *)
let contains (haystack : string) (needle : string) : bool =
  let n = String.length needle and h = String.length haystack in
  let rec go i = i + n <= h && (String.sub haystack i n = needle || go (i + 1)) in
  go 0

let test_duplicate_label_names_no_line_number () =
  match snd (Program.of_source "10 *L\n20 *L\n") with
  | [ e ] ->
      Alcotest.(check int) "no BASIC line number" 0 e.Error.line;
      Alcotest.(check bool) "message omits a line clause" false
        (contains (Error.to_string e) "in line")
  | es -> Alcotest.failf "expected exactly one error, got %d" (List.length es)

let () =
  Alcotest.run "program"
    [ ( "of_source",
        [ case "sorted" test_sorts_lines;
          case "blank lines" test_blank_lines_ignored;
          case "index" test_index_lookup;
          case "recovers from a bad line" test_recovers_from_a_bad_line;
          case "reports every bad line" test_reports_every_bad_line;
          case "parse error carries a span" test_parse_error_carries_a_span;
          case "missing line number is an error, not an exception"
            test_missing_line_number_is_an_error_not_an_exception;
          case "CRLF source" test_crlf_source;
          case "lex failure reports the line it occurred on"
            test_lex_failure_reports_the_line_it_occurred_on;
          case "oversized leading number does not escape recovery"
            test_oversized_leading_number_does_not_escape_recovery;
          case "parse error span is token-precise" test_parse_error_span_is_token_precise;
          case "number_span covers the line-number token"
            test_number_span_covers_the_line_number_token;
          case "missing line number message omits the line clause"
            test_missing_line_number_message_omits_the_line_clause;
          case "line number lower bound" test_line_number_lower_bound;
          case "line number upper bound" test_line_number_upper_bound;
          case "line length limit" test_line_length_limit;
          case "duplicate label is refused" test_duplicate_label_is_refused;
          case "duplicate label names no line number"
            test_duplicate_label_names_no_line_number
        ] )
    ]
