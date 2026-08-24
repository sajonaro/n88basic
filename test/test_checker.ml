open N88lsp

let severity_name = function Checker.Error -> "error" | Checker.Warning -> "warning"

let test_clean_program_has_no_diagnostics () =
  let diags = Checker.check "10 PRINT 1\n20 GOTO 10\n" in
  Alcotest.(check int) "no diagnostics" 0 (List.length diags)

let test_goto_to_missing_line () =
  let diags = Checker.check "10 GOTO 999\n20 PRINT 1\n" in
  Alcotest.(check int) "one diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check int) "0-based file line" 0 d.Checker.line;
  Alcotest.(check (pair int int)) "brackets just the digits" (8, 11) (d.Checker.start_col, d.Checker.end_col);
  Alcotest.(check string) "severity" "error" (severity_name d.Checker.severity);
  Alcotest.(check (option string)) "code" (Some "undefined-line") d.Checker.code

let test_gosub_then_else_on_goto_and_restore_all_checked () =
  let diags =
    Checker.check
      "10 GOSUB 900\n\
       20 IF 1 THEN 901\n\
       30 IF 1 THEN 10 ELSE 902\n\
       40 ON 1 GOTO 903, 904\n\
       50 ON 1 GOSUB 905\n\
       60 RESTORE 906\n\
       70 END\n"
  in
  let targets =
    List.filter_map
      (fun (d : Checker.diagnostic) -> if d.code = Some "undefined-line" then Some d.message else None)
      diags
  in
  Alcotest.(check int) "one diagnostic per missing target" 7 (List.length targets)

let test_goto_to_existing_line_is_clean () =
  let diags = Checker.check "10 GOTO 20\n20 END\n" in
  Alcotest.(check int) "no diagnostics" 0 (List.length diags)

let test_syntax_error_is_reported_with_its_span () =
  let diags = Checker.check "10 PRINT (\n" in
  Alcotest.(check int) "one diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check string) "severity" "error" (severity_name d.Checker.severity);
  Alcotest.(check (option string)) "code" (Some "syntax-error") d.Checker.code

let test_syntax_errors_recover_across_lines () =
  (* basic/program.ml recovers per physical line (test_program.ml: "reports
     every bad line"), so a checker built on it should report a syntax
     diagnostic per broken line, not stop at the first. *)
  let diags = Checker.check "10 PRINT (\n20 A=1\n30 PRINT )\n" in
  let syntax = List.filter (fun (d : Checker.diagnostic) -> d.code = Some "syntax-error") diags in
  Alcotest.(check int) "both bad lines reported" 2 (List.length syntax)

let test_duplicate_line_number () =
  let diags = Checker.check "10 PRINT 1\n10 PRINT 2\n" in
  Alcotest.(check int) "one diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check (option string)) "code" (Some "duplicate-line") d.Checker.code;
  Alcotest.(check int) "flags the second occurrence" 1 d.Checker.line

let test_line_out_of_ascending_order () =
  let diags = Checker.check "20 PRINT 1\n10 PRINT 2\n" in
  Alcotest.(check int) "one diagnostic" 1 (List.length diags);
  let d = List.hd diags in
  Alcotest.(check (option string)) "code" (Some "line-order") d.Checker.code;
  Alcotest.(check string) "severity is a warning, not an error" "warning" (severity_name d.Checker.severity)

let case n f = Alcotest.test_case n `Quick f

let () =
  Alcotest.run "checker"
    [
      ( "check",
        [
          case "clean program has no diagnostics" test_clean_program_has_no_diagnostics;
          case "GOTO to a missing line" test_goto_to_missing_line;
          case "GOTO to an existing line is clean" test_goto_to_existing_line_is_clean;
          case "GOSUB/THEN/ELSE/ON-GOTO/ON-GOSUB/RESTORE are all checked"
            test_gosub_then_else_on_goto_and_restore_all_checked;
          case "syntax error is reported with its span" test_syntax_error_is_reported_with_its_span;
          case "syntax errors recover across lines" test_syntax_errors_recover_across_lines;
          case "duplicate line number" test_duplicate_line_number;
          case "line out of ascending order" test_line_out_of_ascending_order;
        ] );
    ]
