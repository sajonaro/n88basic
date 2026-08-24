open N88basic

let parse s = Parser.parse_statements (Lexer.tokenize ~line:0 s)

(* Shape tests match through [.snode] / [.enode] so that the span wrapper
   introduced by amendment 0 costs one field name per pattern rather than a
   rewrite of every expectation. Spans themselves are pinned separately. *)

let test_let_implicit () =
  match parse "A=1+2*3" with
  | [ { snode =
          Ast.Let
            ( Ast.LVar "A",
              { enode =
                  Ast.Binop
                    ( "+",
                      { enode = Ast.Num (_, 1.0); _ },
                      { enode =
                          Ast.Binop
                            ("*", { enode = Ast.Num (_, 2.0); _ }, { enode = Ast.Num (_, 3.0); _ });
                        _ } );
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "precedence or implicit LET wrong"

let test_parens_beat_precedence () =
  match parse "A=(1+2)*3" with
  | [ { snode =
          Ast.Let
            ( _,
              { enode =
                  Ast.Binop
                    ( "*",
                      { enode = Ast.Binop ("+", _, _); _ },
                      { enode = Ast.Num (_, 3.0); _ } );
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "parentheses ignored"

let test_precedence_chain () =
  (* OR < AND < comparison, and unary NOT binds tightest of the three. *)
  match parse "A=NOT B AND C OR D" with
  | [ { snode =
          Ast.Let
            ( _,
              { enode =
                  Ast.Binop
                    ( "OR",
                      { enode =
                          Ast.Binop
                            ( "AND",
                              { enode = Ast.Unary ("NOT", { enode = Ast.Var "B"; _ }); _ },
                              { enode = Ast.Var "C"; _ } );
                        _ },
                      { enode = Ast.Var "D"; _ } );
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "OR/AND/NOT precedence wrong"

(* ref-9801 printed p.20 / PDF p.33 settles this by worked example: the
   algebraic X^(Y squared) is written in BASIC *with* parentheses as
   X^(Y^2), while (X^Y) squared is written bare as X^Y^2. A bare run of ^
   therefore groups leftwards, and 2^3^2 is (2^3)^2 = 64.

   This test previously asserted the opposite, and passed. It was not
   failing to catch the bug -- it was defending it, having been written
   from the parser rather than from the page. Most later languages do
   associate ^ rightwards, which is what made it look obviously correct. *)
let test_power_is_left_associative () =
  match parse "A=2^3^2" with
  | [ { snode =
          Ast.Let
            ( _,
              { enode =
                  Ast.Binop
                    ( "^",
                      { enode =
                          Ast.Binop
                            ("^", { enode = Ast.Num (_, 2.0); _ }, { enode = Ast.Num (_, 3.0); _ });
                        _ },
                      { enode = Ast.Num (_, 2.0); _ } );
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "^ should be left-associative (ref-9801 printed p.20)"

(* ref-9801 printed p.19 / PDF p.32: §10.1's table is ordered by execution
   order downward and puts ^ above the sign row, so -2^2 is -(2^2). *)
let test_power_binds_tighter_than_unary_minus () =
  match parse "A=-2^2" with
  | [ { snode =
          Ast.Let
            ( _,
              { enode =
                  Ast.Unary
                    ( "-",
                      { enode =
                          Ast.Binop
                            ("^", { enode = Ast.Num (_, 2.0); _ }, { enode = Ast.Num (_, 2.0); _ });
                        _ } );
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "-2^2 must parse as -(2^2) (ref-9801 printed p.19)"

(* The lexer keeps whichever character order the source used; the parser
   normalises, so the evaluator sees one spelling of each operator. *)
let test_reversed_operators_are_normalised () =
  let op src =
    match parse src with
    | [ { snode = Ast.If ({ enode = Ast.Binop (op, _, _); _ }, _, _); _ } ] -> op
    | _ -> Alcotest.fail ("no comparison parsed from " ^ src)
  in
  (* =< is the order a printed output figure in the source actually shows. *)
  Alcotest.(check string) "=<" "<=" (op "IF A=<1 THEN 10");
  Alcotest.(check string) "=>" ">=" (op "IF A=>1 THEN 10");
  Alcotest.(check string) "><" "<>" (op "IF A><1 THEN 10");
  Alcotest.(check string) "unreversed" ">=" (op "IF A>=1 THEN 10")

let test_print_items () =
  match parse "PRINT \"X=\";X,Y" with
  | [ { snode =
          Ast.Print
            ( Ast.ToScreen,
              None,
              [ Ast.PExpr { enode = Ast.Str "X="; _ };
                Ast.PSemi;
                Ast.PExpr { enode = Ast.Var "X"; _ };
                Ast.PComma;
                Ast.PExpr { enode = Ast.Var "Y"; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "print items wrong"

let test_if_then_line_becomes_goto () =
  match parse "IF A>0 THEN 100" with
  | [ { snode =
          Ast.If
            ( { enode = Ast.Binop (">", { enode = Ast.Var "A"; _ }, { enode = Ast.Num (_, 0.0); _ });
                _ },
              [ { snode = Ast.Goto { target = Ast.LineNumber 100; _ }; _ } ],
              [] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "IF ... THEN <line> should desugar to GOTO"

let test_colon_separates_statements () =
  (match parse "A=1:B=2" with
  | [ { snode = Ast.Let (Ast.LVar "A", _); _ }; { snode = Ast.Let (Ast.LVar "B", _); _ } ]
    ->
      ()
  | _ -> Alcotest.fail "colon separation wrong");
  match parse "A=1:" with
  | [ { snode = Ast.Let (Ast.LVar "A", _); _ } ] -> ()
  | _ -> Alcotest.fail "a trailing colon should end the line, not start a statement"

let test_for_default_step () =
  match parse "FOR I=1 TO 10" with
  | [ { snode =
          Ast.For
            ( "I",
              { enode = Ast.Num (_, 1.0); _ },
              { enode = Ast.Num (_, 10.0); _ },
              { enode = Ast.Num (_, 1.0); _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "default STEP should be 1"

let test_array_assignment () =
  match parse "A(2,3)=7" with
  | [ { snode =
          Ast.Let
            ( Ast.LIndex ("A", [ { enode = Ast.Num (_, 2.0); _ }; { enode = Ast.Num (_, 3.0); _ } ]),
              { enode = Ast.Num (_, 7.0); _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "array lvalue wrong"

let test_def_fn () =
  match parse "DEF FNA(X)=X*X" with
  | [ { snode =
          Ast.DefFn
            ( "FNA",
              [ "X" ],
              { enode =
                  Ast.Binop ("*", { enode = Ast.Var "X"; _ }, { enode = Ast.Var "X"; _ });
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "DEF FN wrong"

(* DATA items reach the parser already classified by the lexer: unquoted text
   needs no quotes, and a leading minus belongs to the number. *)
let test_data_items () =
  match parse "DATA 1,-2,ANCHOR,\"TWO WORDS\"" with
  | [ { snode =
          Ast.Data
            [ { enode = Ast.Num (_, 1.0); _ };
              { enode = Ast.Num (_, -2.0); _ };
              { enode = Ast.Str "ANCHOR"; _ };
              { enode = Ast.Str "TWO WORDS"; _ } ];
        _ } ] ->
      ()
  | _ -> Alcotest.fail "DATA items wrong"

(* A comma is what creates a slot: `DATA 1,` and `DATA 1,,2` both name an
   empty datum, and a `DATA` with nothing after it declares no items at all. *)
let test_a_comma_always_creates_a_datum () =
  (match parse "DATA 1," with
  | [ { snode = Ast.Data [ { enode = Ast.Num (_, 1.0); _ }; { enode = Ast.Str ""; _ } ]; _ } ] ->
      ()
  | _ -> Alcotest.fail "a trailing comma should leave an empty datum behind it");
  (match parse "DATA 1,,2" with
  | [ { snode =
          Ast.Data
            [ { enode = Ast.Num (_, 1.0); _ };
              { enode = Ast.Str ""; _ };
              { enode = Ast.Num (_, 2.0); _ } ];
        _ } ] ->
      ()
  | _ -> Alcotest.fail "an empty interior slot should be an empty datum");
  match parse "DATA" with
  | [ { snode = Ast.Data []; _ } ] -> ()
  | _ -> Alcotest.fail "DATA with no commas and no items declares nothing"

let test_lprint () =
  match parse "LPRINT \"X\";X" with
  | [ { snode =
          Ast.Print
            ( Ast.ToPrinter,
              None,
              [ Ast.PExpr { enode = Ast.Str "X"; _ };
                Ast.PSemi;
                Ast.PExpr { enode = Ast.Var "X"; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "LPRINT wrong"

(* AMENDMENT 0: every node carries the span of the source it was built from. *)

let test_statement_span_covers_the_statement () =
  match parse "PRINT 42" with
  | [ s ] ->
      Alcotest.(check (pair int int))
        "span" (0, 8)
        (s.Ast.sspan.start_col, s.Ast.sspan.end_col)
  | _ -> Alcotest.fail "expected one statement"

let test_expression_span_covers_both_operands () =
  match parse "A=1+2" with
  | [ { snode = Ast.Let (_, e); sspan } ] ->
      Alcotest.(check (pair int int))
        "statement" (0, 5) (sspan.Span.start_col, sspan.Span.end_col);
      Alcotest.(check (pair int int))
        "sum" (2, 5)
        (e.Ast.espan.Span.start_col, e.Ast.espan.Span.end_col)
  | _ -> Alcotest.fail "expected one assignment"

(* AMENDMENT 0a: a jump target's span covers only the digits. In
   "IF X>0 THEN 250 ELSE 310" the literal 250 occupies columns 12, 13 and 14,
   so the half-open span is (12, 15). *)
let test_jump_target_span_covers_only_the_digits () =
  match parse "IF X>0 THEN 250 ELSE 310" with
  | [ { snode = Ast.If (_, [ ({ snode = Ast.Goto t; _ } as jump) ], [ _ ]); _ } ] ->
      Alcotest.(check bool) "target" true (t.Ast.target = Ast.LineNumber 250);
      Alcotest.(check (pair int int))
        "span is the digits only" (12, 15)
        (t.Ast.target_span.Span.start_col, t.Ast.target_span.Span.end_col);
      Alcotest.(check (pair int int))
        "the synthesised statement spans the digits too" (12, 15)
        (jump.Ast.sspan.Span.start_col, jump.Ast.sspan.Span.end_col)
  | _ -> Alcotest.fail "IF/THEN/ELSE target span wrong"

let test_jump_statements_carry_line_refs () =
  match parse "GOSUB 500:GOTO 20:RESTORE 40:RESTORE" with
  | [ { snode = Ast.Gosub { target = Ast.LineNumber 500; target_span = gs }; _ };
      { snode = Ast.Goto { target = Ast.LineNumber 20; _ }; _ };
      { snode = Ast.Restore (Some { target = Ast.LineNumber 40; _ }); _ };
      { snode = Ast.Restore None; _ } ] ->
      Alcotest.(check (pair int int))
        "GOSUB target span" (6, 9) (gs.Span.start_col, gs.Span.end_col)
  | _ -> Alcotest.fail "jump targets wrong"

(* AMENDMENT 1: PRINT and LPRINT are one statement with a destination and an
   optional USING clause. *)

let test_print_using () =
  match parse "PRINT USING \"##.#\";X" with
  | [ { snode =
          Ast.Print
            ( Ast.ToScreen,
              Some { enode = Ast.Str "##.#"; _ },
              [ Ast.PExpr { enode = Ast.Var "X"; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "PRINT USING wrong"

let test_lprint_using () =
  match parse "LPRINT USING \"#####\";N" with
  | [ { snode =
          Ast.Print
            ( Ast.ToPrinter,
              Some { enode = Ast.Str "#####"; _ },
              [ Ast.PExpr { enode = Ast.Var "N"; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "LPRINT USING wrong"

let test_tab_in_print_list () =
  match parse "PRINT TAB(10);X" with
  | [ { snode =
          Ast.Print (Ast.ToScreen, None, [ Ast.PTab { enode = Ast.Num (_, 10.0); _ }; Ast.PSemi; _ ]);
        _ } ] ->
      ()
  | _ -> Alcotest.fail "TAB wrong"

(* USING is not required to be the first thing after PRINT: it may follow a
   TAB(n) clause. *)
let test_using_may_follow_a_tab_clause () =
  match parse "PRINT TAB(5);USING \"###\";X" with
  | [ { snode =
          Ast.Print
            ( Ast.ToScreen,
              Some { enode = Ast.Str "###"; _ },
              [ Ast.PTab { enode = Ast.Num (_, 5.0); _ };
                Ast.PSemi;
                Ast.PExpr { enode = Ast.Var "X"; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "TAB before USING wrong"

(* AMENDMENT 2: THEN and ELSE each take a statement list or a line number. *)

let test_if_then_statement_else_line () =
  match parse "IF K=0 THEN END ELSE 480" with
  | [ { snode =
          Ast.If (_, [ { snode = Ast.End; _ } ], [ { snode = Ast.Goto { target = Ast.LineNumber 480; _ }; _ } ]);
        _ } ] ->
      ()
  | _ -> Alcotest.fail "IF/THEN/ELSE wrong"

let test_if_without_else () =
  match parse "IF A>0 THEN 100" with
  | [ { snode = Ast.If (_, [ { snode = Ast.Goto { target = Ast.LineNumber 100; _ }; _ } ], []); _ } ] -> ()
  | _ -> Alcotest.fail "absent ELSE should be the empty list"

(* A colon after THEN continues the then-branch rather than ending the IF. *)
let test_then_branch_takes_the_rest_of_the_line () =
  match parse "IF A>0 THEN B=1:C=2" with
  | [ { snode =
          Ast.If
            ( _,
              [ { snode = Ast.Let (Ast.LVar "B", _); _ };
                { snode = Ast.Let (Ast.LVar "C", _); _ } ],
              [] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "statements after THEN ... : belong to the then-branch"

(* AMENDMENT 3: screen and graphics statements parse; they are recorded, not
   rendered, by the evaluator. *)

let test_screen_control_statements () =
  match parse "CLS:LOCATE 5,10:KEY OFF:SCREEN 3" with
  | [ { snode = Ast.Cls None; _ };
      { snode =
          Ast.Locate
            { x = Some { enode = Ast.Num (_, 5.0); _ };
              y = Some { enode = Ast.Num (_, 10.0); _ };
              cursor = None };
        _ };
      { snode = Ast.Key { key_number = None; key_action = Ast.Key_off }; _ };
      { snode =
          Ast.Screen { mode = Some { enode = Ast.Num (_, 3.0); _ }; switch = None;
                       active = None; display = None };
        _ } ] ->
      ()
  | _ -> Alcotest.fail "screen control statements wrong"

(* WIDTH sets the text screen geometry; the source uses both the one-argument
   and the two-argument form. *)
let test_width_takes_one_or_two_expressions () =
  match parse "WIDTH 40:WIDTH 40,20" with
  | [ { snode = Ast.Width [ { enode = Ast.Num (_, 40.0); _ } ]; _ };
      { snode = Ast.Width [ { enode = Ast.Num (_, 40.0); _ }; { enode = Ast.Num (_, 20.0); _ } ]; _ } ]
    ->
      ()
  | _ -> Alcotest.fail "WIDTH wrong"

let test_line_statement_with_box () =
  match parse "LINE (10,20)-(60,45),3,BF" with
  | [ { snode =
          Ast.Line
            { from_point = Some _; to_point = _; colour = Some { enode = Ast.Num (_, 3.0); _ };
              box = `Filled; trailing = None };
        _ } ] ->
      ()
  | _ -> Alcotest.fail "LINE ...,BF wrong"

let test_line_statement_forms () =
  (* No start point, and a box with the colour left out: the doubled comma is
     how a listing skips the colour slot. *)
  match parse "LINE -(60,45),,B" with
  | [ { snode = Ast.Line { from_point = None; colour = None; box = `Frame; _ }; _ } ] -> ()
  | _ -> Alcotest.fail "LINE -(x,y),,B wrong"

(* The first slot after the coordinates is the colour, so a colour held in a
   variable named B is a colour and not a box flag. *)
let test_line_colour_slot_is_not_a_box_flag () =
  match parse "LINE (2,3)-(P,Q),B" with
  | [ { snode = Ast.Line { colour = Some { enode = Ast.Var "B"; _ }; box = `None; _ }; _ } ]
    ->
      ()
  | _ -> Alcotest.fail "LINE ...,B should read B as the colour"

let test_input_prompt_is_optional () =
  (match parse "INPUT \"HOW MANY\";N" with
  | [ { snode =
          Ast.Input
            { prompt = Some "HOW MANY"; show_question = true; targets = [ Ast.LVar "N" ] };
        _ } ] -> ()
  | _ -> Alcotest.fail "prompted INPUT wrong");
  match parse "INPUT N,A(1)" with
  | [ { snode =
          Ast.Input
            { prompt = None; show_question = true;
              targets = [ Ast.LVar "N"; Ast.LIndex ("A", [ _ ]) ] };
        _ } ] -> ()
  | _ -> Alcotest.fail "unprompted INPUT with several targets wrong"

let test_dim_declares_several_arrays () =
  match parse "DIM A(10),B(3,4),C(N)" with
  | [ { snode =
          Ast.Dim
            [ ("A", [ { enode = Ast.Num (_, 10.0); _ } ]);
              ("B", [ { enode = Ast.Num (_, 3.0); _ }; { enode = Ast.Num (_, 4.0); _ } ]);
              ("C", [ { enode = Ast.Var "N"; _ } ]) ];
        _ } ] ->
      ()
  | _ -> Alcotest.fail "DIM wrong"

let test_intrinsic_calls () =
  match parse "A$=LEFT$(B$,1):X=VAL(A$)+SQR(2)" with
  | [ { snode = Ast.Let (Ast.LVar "A$", { enode = Ast.Call ("LEFT$", [ _; _ ]); _ }); _ };
      { snode =
          Ast.Let
            ( Ast.LVar "X",
              { enode =
                  Ast.Binop
                    ( "+",
                      { enode = Ast.Call ("VAL", [ _ ]); _ },
                      { enode = Ast.Call ("SQR", [ _ ]); _ } );
                _ } );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "intrinsic calls wrong"

(* RND's parenthesised argument is optional -- both forms parse to the same
   node shape, just with a different argument list (spec/spec.md NUM.RND). *)
let test_rnd_argument_is_optional () =
  (match parse "X=RND" with
  | [ { snode = Ast.Let (Ast.LVar "X", { enode = Ast.Call ("RND", []); _ }); _ } ] -> ()
  | _ -> Alcotest.fail "bare RND wrong");
  match parse "X=RND(1)" with
  | [ { snode = Ast.Let (Ast.LVar "X", { enode = Ast.Call ("RND", [ _ ]); _ }); _ } ] -> ()
  | _ -> Alcotest.fail "RND(n) wrong"

(* CSRLIN, ERR and ERL are always written bare -- no parenthesised form
   exists for any of the three (spec/spec.md PRINT.CSRLIN, ERR.FN,
   ERR.ERL). *)
let test_csrlin_err_erl_take_no_arguments () =
  (match parse "X=CSRLIN" with
  | [ { snode = Ast.Let (Ast.LVar "X", { enode = Ast.Call ("CSRLIN", []); _ }); _ } ] -> ()
  | _ -> Alcotest.fail "CSRLIN wrong");
  (match parse "X=ERR" with
  | [ { snode = Ast.Let (Ast.LVar "X", { enode = Ast.Call ("ERR", []); _ }); _ } ] -> ()
  | _ -> Alcotest.fail "ERR wrong");
  match parse "X=ERL" with
  | [ { snode = Ast.Let (Ast.LVar "X", { enode = Ast.Call ("ERL", []); _ }); _ } ] -> ()
  | _ -> Alcotest.fail "ERL wrong"

(* SPC, like TAB, is read as its own print_item rather than a general
   [Ast.Call] -- the manual is explicit SPC cannot be used as a string
   expression (spec/spec.md PRINT.SPC). *)
let test_spc_in_print_list () =
  match parse "PRINT \"A\";SPC(3);\"B\"" with
  | [ { snode =
          Ast.Print
            ( Ast.ToScreen,
              None,
              [ Ast.PExpr { enode = Ast.Str "A"; _ };
                Ast.PSemi;
                Ast.PSpc { enode = Ast.Num (_, 3.0); _ };
                Ast.PSemi;
                Ast.PExpr { enode = Ast.Str "B"; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "SPC in a PRINT list wrong"

(* A reserved word refused as a variable name (spec/spec.md §3.4, manual
   Appendix E): the structural fix for the bug where an unimplemented
   built-in, spelled with a following "(", parsed as an ordinary array
   reference and silently answered 0. *)
let test_reserved_word_refused_as_a_variable () =
  match parse "EXP=5" with
  | exception Error.Basic_error e ->
      Alcotest.(check string) "message"
        "EXP is a reserved word and cannot be used as a variable name" e.Error.message
  | _ -> Alcotest.fail "EXP=5 should be refused, not parsed as an assignment"

(* Same structural fix, for a word that is part of the language (spec/spec.md
   §3.2) but has no implemented grammar of its own: it must not be usable as
   an array either. *)
let test_deferred_word_refused_as_an_array () =
  match parse "X=DATE$(1)" with
  | exception Error.Basic_error e ->
      Alcotest.(check string) "message"
        "DATE$ is a reserved word (not implemented here) and cannot be used as a variable name"
        e.Error.message
  | _ -> Alcotest.fail "DATE$(1) should be refused, not parsed as an array reference"

(* MID$'s statement form is not an [lvalue]-based assignment: the parenthesised
   argument list is MID$'s own, not a subscript on the string variable named
   inside it, so it needs its own AST shape (Ast.MidAssign) rather than
   Ast.Let. The two-argument and three-argument forms both parse. *)
let test_mid_dollar_statement_two_args () =
  match parse "MID$(A$,3)=\"XY\"" with
  | [ { snode =
          Ast.MidAssign
            ("A$", { enode = Ast.Num (_, 3.0); _ }, None, { enode = Ast.Str "XY"; _ });
        _ } ] ->
      ()
  | _ -> Alcotest.fail "MID$ statement (two args) wrong"

let test_mid_dollar_statement_three_args () =
  match parse "MID$(B$,N,2)=C$" with
  | [ { snode =
          Ast.MidAssign
            ("B$", { enode = Ast.Var "N"; _ }, Some { enode = Ast.Num (_, 2.0); _ }, { enode = Ast.Var "C$"; _ });
        _ } ] ->
      ()
  | _ -> Alcotest.fail "MID$ statement (three args) wrong"

(* Without this check, a line the parser only half-understands is silently
   truncated to the part it did understand. A parse failure is reported as
   [Error.Basic_error] with the span of the token the parser choked on —
   here, the leftover "B", not the whole line. *)
let test_leftover_tokens_are_an_error () =
  match parse "A=1 B=2" with
  | exception Error.Basic_error e ->
      Alcotest.(check string) "message" "Unexpected token after statement" e.Error.message;
      (match e.Error.span with
      | Some s ->
          Alcotest.(check (pair int int)) "points at the leftover token" (4, 5)
            (s.Span.start_col, s.Span.end_col)
      | None -> Alcotest.fail "expected a span")
  | _ -> Alcotest.fail "expected a parse error"

(* A parse failure deep inside expression parsing (here, a missing operand
   right after "PRINT") still reports the token it was looking at, not
   column 1. *)
let test_syntax_error_carries_a_span () =
  match parse "PRINT )" with
  | exception Error.Basic_error e ->
      Alcotest.(check string) "message" "Expected an expression" e.Error.message;
      (match e.Error.span with
      | Some s ->
          Alcotest.(check (pair int int)) "points at the stray )" (6, 7)
            (s.Span.start_col, s.Span.end_col)
      | None -> Alcotest.fail "expected a span")
  | _ -> Alcotest.fail "expected a parse error"

(* WHILE takes a bare condition expression; WEND takes nothing at all. *)
let test_while_wend () =
  (match parse "WHILE I<5" with
  | [ { snode = Ast.While { enode = Ast.Binop ("<", { enode = Ast.Var "I"; _ }, { enode = Ast.Num (_, 5.0); _ }); _ }; _ } ] -> ()
  | _ -> Alcotest.fail "WHILE wrong");
  match parse "WEND" with
  | [ { snode = Ast.Wend; _ } ] -> ()
  | _ -> Alcotest.fail "WEND wrong"

(* ON <expr> GOTO/GOSUB <line>[,<line>...] -- both forms share a selector
   expression and a comma-separated line list, differing only in the
   keyword and the AST constructor (spec/spec.md CTRL.ON-GOTO,
   CTRL.ON-GOSUB). *)
let test_on_goto_and_on_gosub () =
  (match parse "ON X GOTO 100,200,300" with
  | [ { snode =
          Ast.OnGoto
            ( { enode = Ast.Var "X"; _ },
              [ { target = Ast.LineNumber 100; _ }; { target = Ast.LineNumber 200; _ }; { target = Ast.LineNumber 300; _ } ] );
        _ } ] ->
      ()
  | _ -> Alcotest.fail "ON...GOTO wrong");
  match parse "ON N+1 GOSUB 10,20" with
  | [ { snode = Ast.OnGosub (_, [ { target = Ast.LineNumber 10; _ }; { target = Ast.LineNumber 20; _ } ]); _ } ] -> ()
  | _ -> Alcotest.fail "ON...GOSUB wrong"

let test_swap () =
  match parse "SWAP A,B(1)" with
  | [ { snode = Ast.Swap (Ast.LVar "A", Ast.LIndex ("B", [ { enode = Ast.Num (_, 1.0); _ } ])); _ } ]
    ->
      ()
  | _ -> Alcotest.fail "SWAP wrong"

let test_erase_several_arrays () =
  match parse "ERASE C,D$" with
  | [ { snode = Ast.Erase [ "C"; "D$" ]; _ } ] -> ()
  | _ -> Alcotest.fail "ERASE wrong"

(* Every slot of CLEAR is optional, and a bare CLEAR has none of them. *)
let test_clear_optional_slots () =
  (match parse "CLEAR" with
  | [ { snode = Ast.Clear []; _ } ] -> ()
  | _ -> Alcotest.fail "bare CLEAR wrong");
  match parse "CLEAR ,1000,100" with
  | [ { snode = Ast.Clear [ None; Some { enode = Ast.Num (_, 1000.0); _ }; Some { enode = Ast.Num (_, 100.0); _ } ]; _ } ] ->
      ()
  | _ -> Alcotest.fail "CLEAR with slots wrong"

(* OPTION BASE's syntax box offers only the literal digits 0 or 1, not a
   general expression (spec/spec.md PROG.OPTION-BASE): anything else is
   refused at parse time. *)
let test_option_base () =
  (match parse "OPTION BASE 1" with
  | [ { snode = Ast.OptionBase 1; _ } ] -> ()
  | _ -> Alcotest.fail "OPTION BASE 1 wrong");
  (match parse "OPTION BASE 0" with
  | [ { snode = Ast.OptionBase 0; _ } ] -> ()
  | _ -> Alcotest.fail "OPTION BASE 0 wrong");
  match parse "OPTION BASE 2" with
  | exception Error.Basic_error _ -> ()
  | _ -> Alcotest.fail "OPTION BASE 2 should be refused"

(* The eight words this task adds are reserved the same way EXP was
   (test_reserved_word_refused_as_a_variable above): each now lexes as a
   [Token.Keyword], so spelling one with a following "(" in an expression
   position can no longer parse as an ordinary array reference -- it hits
   [reserved_word_error] in [parse_primary] before the "(" is even looked
   at. Written as a RHS reference, not as a statement's leading token,
   because every one of these words has its own statement grammar now and
   would take that path instead if written first on the line. *)
let test_new_keywords_refused_as_arrays () =
  List.iter
    (fun word ->
      match parse (Printf.sprintf "X=%s(1)" word) with
      | exception Error.Basic_error e ->
          Alcotest.(check string) (word ^ " refused")
            (word ^ " is a reserved word and cannot be used as a variable name")
            e.Error.message
      | _ -> Alcotest.fail (word ^ " should be refused as an array reference"))
    [ "WHILE"; "WEND"; "ON"; "SWAP"; "ERASE"; "CLEAR"; "OPTION"; "BASE" ]

let case n f = Alcotest.test_case n `Quick f

let () =
  Alcotest.run "parser"
    [ ( "statements",
        [ case "implicit LET" test_let_implicit;
          case "parens" test_parens_beat_precedence;
          case "precedence chain" test_precedence_chain;
          case "power associativity" test_power_is_left_associative;
          case "power outranks unary minus" test_power_binds_tighter_than_unary_minus;
          case "reversed operators" test_reversed_operators_are_normalised;
          case "PRINT" test_print_items;
          case "IF THEN line" test_if_then_line_becomes_goto;
          case "colon" test_colon_separates_statements;
          case "FOR step" test_for_default_step;
          case "array lvalue" test_array_assignment;
          case "DEF FN" test_def_fn;
          case "DATA items" test_data_items;
          case "DATA empty slots" test_a_comma_always_creates_a_datum;
          case "LPRINT" test_lprint;
          case "PRINT USING" test_print_using;
          case "LPRINT USING" test_lprint_using;
          case "TAB" test_tab_in_print_list;
          case "TAB before USING" test_using_may_follow_a_tab_clause;
          case "IF THEN stmt ELSE line" test_if_then_statement_else_line;
          case "IF without ELSE" test_if_without_else;
          case "THEN takes the rest of the line" test_then_branch_takes_the_rest_of_the_line;
          case "screen control" test_screen_control_statements;
          case "WIDTH" test_width_takes_one_or_two_expressions;
          case "LINE with box" test_line_statement_with_box;
          case "LINE forms" test_line_statement_forms;
          case "LINE colour slot" test_line_colour_slot_is_not_a_box_flag;
          case "INPUT" test_input_prompt_is_optional;
          case "DIM" test_dim_declares_several_arrays;
          case "intrinsics" test_intrinsic_calls;
          case "RND argument optional" test_rnd_argument_is_optional;
          case "CSRLIN/ERR/ERL bare" test_csrlin_err_erl_take_no_arguments;
          case "SPC in PRINT list" test_spc_in_print_list;
          case "reserved word as variable" test_reserved_word_refused_as_a_variable;
          case "deferred word as array" test_deferred_word_refused_as_an_array;
          case "MID$ statement, two args" test_mid_dollar_statement_two_args;
          case "MID$ statement, three args" test_mid_dollar_statement_three_args;
          case "leftover tokens" test_leftover_tokens_are_an_error;
          case "syntax error" test_syntax_error_carries_a_span;
          case "WHILE/WEND" test_while_wend;
          case "ON...GOTO / ON...GOSUB" test_on_goto_and_on_gosub;
          case "SWAP" test_swap;
          case "ERASE" test_erase_several_arrays;
          case "CLEAR optional slots" test_clear_optional_slots;
          case "OPTION BASE" test_option_base;
          case "new keywords refused as arrays" test_new_keywords_refused_as_arrays ] );
      ( "spans",
        [ case "statement span" test_statement_span_covers_the_statement;
          case "expression span" test_expression_span_covers_both_operands;
          case "jump target span" test_jump_target_span_covers_only_the_digits;
          case "jump statements" test_jump_statements_carry_line_refs ] )
    ]
