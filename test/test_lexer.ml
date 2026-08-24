open N88basic

let kind =
  Alcotest.testable
    (fun ppf k ->
      Format.pp_print_string ppf
        (match k with
        | Token.Number (t, n) -> Printf.sprintf "Number %s %g" (match t with Numtype.Int -> "Int" | Numtype.Single -> "Single" | Numtype.Double -> "Double") n
        | Token.Str s -> Printf.sprintf "Str %S" s
        | Token.Ident s -> Printf.sprintf "Ident %s" s
        | Token.Keyword s -> Printf.sprintf "Keyword %s" s
        | Token.Punct s -> Printf.sprintf "Punct %s" s))
    ( = )

let kinds (ts : Token.t list) : Token.kind list =
  List.map (fun (t : Token.t) -> t.Token.kind) ts

let check name expected input =
  Alcotest.(check (list kind)) name expected (kinds (Lexer.tokenize ~line:0 input))

let test_spaced_for () =
  check "spaced FOR"
    [ Token.Keyword "FOR"; Token.Ident "I"; Token.Punct "=";
      Token.Number (Numtype.Int, 1.0); Token.Keyword "TO"; Token.Number (Numtype.Int, 10.0) ]
    "FOR I = 1 TO 10"

(* PROG.VARIABLE-NAMES (ref-9801 printed p.17 / PDF p.30, §8 予約語): a
   reserved word is recognised only when a delimiter -- space, quote, "#",
   colon, or other punctuation -- sets it off on both sides. Nothing
   delimits "FOR" from the "I" in "FORI", so no keyword is recognised
   there at all; the whole run scans as one identifier, and likewise "1TO10"
   is the number 1 followed by one identifier "TO10" ("TO" is not delimited
   from what follows it either). This is the manual's own stated rule, not
   an inference -- and it is why classic Microsoft BASIC's reading of
   "FORI=1TO10" as "FOR I = 1 TO 10" does not hold here: unspaced keyword
   runs are not supported. (This test used to assert exactly that classic
   reading, which was the bug PROG.VARIABLE-NAMES fixes -- see also
   test_reserved_word_containing_names_still_lex_as_identifiers below.) *)
let test_unspaced_keyword_run_is_one_identifier () =
  check "unspaced FOR is not split"
    [ Token.Ident "FORI"; Token.Punct "="; Token.Number (Numtype.Int, 1.0); Token.Ident "TO10" ]
    "FORI=1TO10"

(* The flip side of the same rule: a name that merely *contains* a reserved
   word's letters, with nothing delimiting the reserved word inside it, is
   an ordinary identifier -- never split at the reserved word the way the
   pre-fix scanner used to (TOTAL as TO+TAL, LINEAR as LINE+AR, FORM as
   FOR+M, ANDY as AND+Y, IFS as IF+S). *)
let test_reserved_word_containing_names_still_lex_as_identifiers () =
  List.iter
    (fun name -> check name [ Token.Ident name ] name)
    [ "TOTAL"; "LINEAR"; "FORM"; "ANDY"; "IFS" ]

(* PROG.VARIABLE-NAMES: periods are legal inside a name, past the required
   leading letter. *)
let test_name_may_contain_a_period () =
  check "A.B" [ Token.Ident "A.B" ] "A.B"

(* PROG.VARIABLE-NAMES: up to 40 significant characters. A 40-character run
   is one identifier, in full. *)
let test_forty_character_name () =
  let name = String.make 40 'A' in
  check "40-char name" [ Token.Ident name ] name

(* PROG.VARIABLE-NAMES: letter case is not distinguished -- both spellings
   of a name lex to the same uppercase [Token.Ident] text. *)
let test_names_are_case_insensitive () =
  check "Total/TOTAL" [ Token.Ident "TOTAL" ] "Total";
  check "total/TOTAL" [ Token.Ident "TOTAL" ] "total"

let test_sigils () =
  check "string variable"
    [ Token.Ident "N$"; Token.Punct "="; Token.Str "HI" ]
    "N$=\"HI\""

let test_two_char_operators () =
  check "comparison"
    [ Token.Ident "A"; Token.Punct "<="; Token.Number (Numtype.Int, 3.0);
      Token.Ident "B"; Token.Punct "<>"; Token.Number (Numtype.Int, 0.0) ]
    "A<=3 B<>0"

let test_rem_swallows_rest () =
  check "REM" [ Token.Keyword "REM"; Token.Str " ANYTHING = GOES" ]
    "REM ANYTHING = GOES"

(* PROG.COMMENT-MARK: ' performs the same function as REM. *)
let test_apostrophe_is_a_comment () =
  check "apostrophe" [ Token.Keyword "REM"; Token.Str " A NOTE" ] "' A NOTE"

let test_float_literal () =
  check "float" [ Token.Number (Numtype.Single, 0.25) ] ".25"

(* AMENDMENT 1: relational operators come in both character orders. *)
let test_reversed_operators () =
  check "both orders"
    [ Token.Ident "A"; Token.Punct "=<"; Token.Number (Numtype.Int, 3.0);
      Token.Ident "B"; Token.Punct "=>"; Token.Number (Numtype.Int, 4.0) ]
    "A=<3 B=>4"

(* AMENDMENT 0: every token carries a source span. *)
let test_spans_locate_tokens () =
  match Lexer.tokenize ~line:0 "A = 42" with
  | [ a; eq; n ] ->
      Alcotest.(check (triple int int int)) "A" (0, 0, 1)
        (a.span.line, a.span.start_col, a.span.end_col);
      Alcotest.(check (triple int int int)) "=" (0, 2, 3)
        (eq.span.line, eq.span.start_col, eq.span.end_col);
      Alcotest.(check (triple int int int)) "42" (0, 4, 6)
        (n.span.line, n.span.start_col, n.span.end_col)
  | _ -> Alcotest.fail "expected three tokens"

let test_span_line_is_absolute_physical_line () =
  match Lexer.tokenize ~line:7 "X=1" with
  | [ x; _; _ ] -> Alcotest.(check int) "physical line" 7 x.span.line
  | _ -> Alcotest.fail "expected three tokens"

(* AMENDMENT 2: DATA takes raw text, not tokens.
   The item text below is chosen to exercise a range of lexical properties in
   unquoted DATA items: Cyrillic text, a trailing period, an embedded decimal
   point, and a parenthesised year inside a multi-word unquoted string. *)
let test_data_is_raw_text () =
  check "unquoted items with punctuation"
    [ Token.Keyword "DATA"; Token.Str "апр."; Token.Punct ",";
      Token.Number (Numtype.Single, 12.75); Token.Punct ",";
      Token.Str "Quarterly Series (1985)" ]
    "DATA апр.,12.75,Quarterly Series (1985)"

let test_data_negative_number () =
  check "negative datum"
    [ Token.Keyword "DATA"; Token.Number (Numtype.Int, -1.0); Token.Punct ","; Token.Number (Numtype.Int, 2.0) ]
    "DATA -1,2"

let test_quoted_data_item_keeps_its_comma () =
  check "comma inside quotes"
    [ Token.Keyword "DATA"; Token.Str "A,B"; Token.Punct ","; Token.Number (Numtype.Int, 2.0) ]
    "DATA \"A,B\",2"

let test_quoted_data_item_stays_a_string () =
  check "quoted digits are text"
    [ Token.Keyword "DATA"; Token.Str "42" ]
    "DATA \"42\""

let test_malformed_quoted_data_item_raises () =
  match Lexer.tokenize ~line:0 "DATA \"A\" 1,2" with
  | exception Error.Basic_error e ->
      Alcotest.(check string) "message"
        "Malformed DATA item: expected ',' or end of line after quoted item" e.Error.message;
      (match e.Error.span with
      | Some s ->
          Alcotest.(check (triple int int int)) "points at the junk after the quote" (0, 9, 10)
            (s.Span.line, s.Span.start_col, s.Span.end_col)
      | None -> Alcotest.fail "expected a span")
  | _ -> Alcotest.fail "expected a malformed-DATA-item error"

(* CTRL.GOTO (ref-9801 printed p.78-79 / PDF p.89-90). The manual gives "GO
   TO" as a second spelling of GOTO and then states the gap exactly: one
   space between the two words means the same statement, but two or more are
   explicitly *not* interpreted as GOTO. Both halves are asserted here,
   because only the page says the second one is a rule rather than an
   accident of some scanner. *)
let test_go_to_with_one_space_is_goto () =
  check "GO TO"
    [ Token.Keyword "GOTO"; Token.Number (Numtype.Int, 500.0) ]
    "GO TO 500"

let test_go_to_with_two_spaces_is_not_goto () =
  check "GO  TO"
    [ Token.Ident "GO"; Token.Keyword "TO"; Token.Number (Numtype.Int, 500.0) ]
    "GO  TO 500"

(* The delimiter rule of PROG.VARIABLE-NAMES applies to the second word too:
   nothing sets "TO" off from the "TAL" that follows it, so "GO TOTAL" is the
   variable TOTAL and not a jump. Without this the maximal-munch scanner would
   be entitled to read a GOTO here. *)
let test_go_followed_by_a_name_starting_to_is_not_goto () =
  check "GO TOTAL" [ Token.Ident "GO"; Token.Ident "TOTAL" ] "GO TOTAL"

(* DATA items are classified by [classify_datum], which is a SEPARATE number
   scanner from the one the rest of a line goes through. It required a digit
   after an optional sign, so a radix constant failed that test and was
   classified as a string: "DATA &HFF" then reported Syntax error on the READ
   that consumed it, not on the DATA line that held it.

   ref-9801 printed p.12 SS5.3 gives an integer constant three forms -- octal,
   decimal and hexadecimal -- and DATA takes constants, so all three belong
   here. printed p.13's own examples are &12345, &O7777, &H100 and &HCFFF. *)
let datum_number text expected =
  match Lexer.classify_datum ~quoted:false text with
  | Token.Number (_, v) -> Alcotest.(check (float 1e-9)) text expected v
  | Token.Str s -> Alcotest.failf "%s was classified as the string %S" text s
  | _ -> Alcotest.failf "%s was not classified as a number" text

let datum_string text =
  match Lexer.classify_datum ~quoted:false text with
  | Token.Str _ -> ()
  | _ -> Alcotest.failf "%s should not be a numeric constant" text

let test_datum_radix_constants () =
  datum_number "&H100" 256.0;
  datum_number "&HFFFF" (-1.0);
  datum_number "&O7777" 4095.0;
  datum_number "&12345" 5349.0;
  datum_number "42" 42.0;
  datum_number "-123" (-123.0)

(* The distinguishing inputs: what is not a constant must stay a string, or
   "radix constants are recognised" would be satisfiable by calling every
   ampersand a number. A SIGN is not part of the radix forms -- printed p.13
   states the sign rule for the decimal form alone. *)
let test_datum_non_constants_stay_strings () =
  datum_string "&HGG";
  datum_string "&H";
  datum_string "-&HFF";
  datum_string "hello"

let () =
  Alcotest.run "lexer"
    [ ( "DATA items",
        [ Alcotest.test_case "radix constants" `Quick test_datum_radix_constants;
          Alcotest.test_case "non-constants stay strings" `Quick
            test_datum_non_constants_stay_strings ] ); ("tokenize",
       [ Alcotest.test_case "spaced FOR" `Quick test_spaced_for;
         Alcotest.test_case "unspaced keyword run is one identifier" `Quick
           test_unspaced_keyword_run_is_one_identifier;
         Alcotest.test_case "reserved-word-containing names lex as identifiers" `Quick
           test_reserved_word_containing_names_still_lex_as_identifiers;
         Alcotest.test_case "name may contain a period" `Quick test_name_may_contain_a_period;
         Alcotest.test_case "forty-character name" `Quick test_forty_character_name;
         Alcotest.test_case "names are case-insensitive" `Quick test_names_are_case_insensitive;
         Alcotest.test_case "sigils" `Quick test_sigils;
         Alcotest.test_case "operators" `Quick test_two_char_operators;
         Alcotest.test_case "REM" `Quick test_rem_swallows_rest;
         Alcotest.test_case "apostrophe" `Quick test_apostrophe_is_a_comment;
         Alcotest.test_case "float" `Quick test_float_literal;
         Alcotest.test_case "reversed operators" `Quick test_reversed_operators;
         Alcotest.test_case "spans" `Quick test_spans_locate_tokens;
         Alcotest.test_case "span line is absolute" `Quick test_span_line_is_absolute_physical_line;
         Alcotest.test_case "DATA raw text" `Quick test_data_is_raw_text;
         Alcotest.test_case "DATA negative number" `Quick test_data_negative_number;
         Alcotest.test_case "quoted DATA item keeps its comma" `Quick
           test_quoted_data_item_keeps_its_comma;
         Alcotest.test_case "quoted DATA item stays a string" `Quick
           test_quoted_data_item_stays_a_string;
         Alcotest.test_case "malformed quoted DATA item raises" `Quick
           test_malformed_quoted_data_item_raises;
         Alcotest.test_case "GO TO with one space is GOTO" `Quick
           test_go_to_with_one_space_is_goto;
         Alcotest.test_case "GO TO with two spaces is not GOTO" `Quick
           test_go_to_with_two_spaces_is_not_goto;
         Alcotest.test_case "GO before a name starting TO is not GOTO" `Quick
           test_go_followed_by_a_name_starting_to_is_not_goto ]) ]
