open N88basic

let num = function Value.Num (_, n) -> n | Value.Str _ -> Alcotest.fail "expected a number"

let test_scalar_defaults () =
  let e = Env.create () in
  Alcotest.(check (float 1e-12)) "numeric default" 0.0 (num (Env.get_scalar e "A"));
  match Env.get_scalar e "A$" with
  | Value.Str "" -> ()
  | _ -> Alcotest.fail "string default should be empty"

let test_scalar_roundtrip () =
  let e = Env.create () in
  Env.set_scalar e "X" (Value.Num (Numtype.Single, 3.5));
  Alcotest.(check (float 1e-12)) "roundtrip" 3.5 (num (Env.get_scalar e "X"))

let test_scalar_and_array_share_name () =
  let e = Env.create () in
  Env.set_scalar e "T$" (Value.Str "hello");
  Env.dim e "T$" [ 2 ];
  Env.set_element e "T$" [ 1 ] (Value.Str "world");
  (match Env.get_scalar e "T$" with
  | Value.Str "hello" -> ()
  | _ -> Alcotest.fail "scalar T$ should be unaffected by array T$()");
  match Env.get_element e "T$" [ 1 ] with
  | Value.Str "world" -> ()
  | _ -> Alcotest.fail "array element T$(1) should hold its own value"

let test_dim_is_inclusive () =
  let e = Env.create () in
  Env.dim e "A" [ 3 ];
  Env.set_element e "A" [ 3 ] (Value.Num (Numtype.Single, 9.0));
  Alcotest.(check (float 1e-12)) "index 3 exists" 9.0 (num (Env.get_element e "A" [ 3 ]))

let test_subscript_out_of_range () =
  let e = Env.create () in
  Env.dim e "A" [ 2 ];
  Alcotest.check_raises "out of range"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> ignore (Env.get_element e "A" [ 3 ]))

(* DIM takes a bound computed at run time, so a program can hand it a negative
   one. Array.make would raise Invalid_argument, which is not a BASIC error and
   would escape the interpreter's result type instead of stopping the program
   with a line number. *)
let test_negative_dim_bound () =
  let e = Env.create () in
  Alcotest.check_raises "negative bound"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> Env.dim e "A" [ -2 ])

(* The other end of the same class: a bound too large to allocate. Refused by
   arithmetic, before anything is allocated, so neither Array.make's
   Invalid_argument nor a doomed allocation escapes. The product of the axes is
   what matters, not any single one of them. *)
let test_oversized_dim_bound () =
  let e = Env.create () in
  let expected =
    Error.Basic_error { line = 0; message = "Out of memory"; span = None; code = None }
  in
  Alcotest.check_raises "one axis too large" expected (fun () ->
      Env.dim e "A" [ Sys.max_array_length ]);
  Alcotest.check_raises "axes that overflow together" expected (fun () ->
      Env.dim e "B" [ 1000000000; 1000000000 ])

let test_two_dimensions () =
  let e = Env.create () in
  Env.dim e "M" [ 2; 2 ];
  Env.set_element e "M" [ 1; 2 ] (Value.Num (Numtype.Single, 7.0));
  Alcotest.(check (float 1e-12)) "M(1,2)" 7.0 (num (Env.get_element e "M" [ 1; 2 ]));
  Alcotest.(check (float 1e-12)) "M(2,1) untouched" 0.0 (num (Env.get_element e "M" [ 2; 1 ]))

let test_wrong_subscript_count_get () =
  let e = Env.create () in
  Env.dim e "M" [ 2; 2 ];
  Alcotest.check_raises "get_element with wrong rank"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> ignore (Env.get_element e "M" [ 1 ]))

let test_wrong_subscript_count_set () =
  let e = Env.create () in
  Env.dim e "M" [ 2; 2 ];
  Alcotest.check_raises "set_element with wrong rank"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> Env.set_element e "M" [ 1 ] (Value.Num (Numtype.Single, 1.0)))

let test_string_array_default () =
  let e = Env.create () in
  Env.dim e "N$" [ 3 ];
  match Env.get_element e "N$" [ 2 ] with
  | Value.Str "" -> ()
  | _ -> Alcotest.fail "untouched string array cell should default to Str \"\""

let test_undimensioned_array_defaults_to_ten () =
  let e = Env.create () in
  Env.set_element e "L" [ 7 ] (Value.Num (Numtype.Single, 42.0));
  Alcotest.(check (float 1e-12)) "L(7) set" 42.0 (num (Env.get_element e "L" [ 7 ]));
  Alcotest.(check (float 1e-12)) "L(10) is the top of the implicit range" 0.0
    (num (Env.get_element e "L" [ 10 ]));
  Alcotest.check_raises "L(11) is out of range"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> ignore (Env.get_element e "L" [ 11 ]))

let test_undimensioned_array_defaults_to_ten_per_axis () =
  let e = Env.create () in
  Env.set_element e "K" [ 3; 5 ] (Value.Num (Numtype.Single, 1.0));
  Alcotest.(check (float 1e-12)) "K(10,10) is within the implicit per-axis range" 0.0
    (num (Env.get_element e "K" [ 10; 10 ]));
  Alcotest.check_raises "K(11,0) is out of range on the first axis"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> ignore (Env.get_element e "K" [ 11; 0 ]));
  Alcotest.check_raises "K(0,11) is out of range on the second axis"
    (Error.Basic_error { line = 0; message = "Subscript out of range"; span = None; code = None })
    (fun () -> ignore (Env.get_element e "K" [ 0; 11 ]))

let test_data_cursor () =
  let e = Env.create () in
  Env.load_data e [ Value.Num (Numtype.Single, 1.0); Value.Num (Numtype.Single, 2.0) ];
  Alcotest.(check (float 1e-12)) "first" 1.0 (num (Option.get (Env.read_datum e)));
  Alcotest.(check (float 1e-12)) "second" 2.0 (num (Option.get (Env.read_datum e)));
  Alcotest.(check bool) "exhausted" true (Env.read_datum e = None);
  Env.restore e 0;
  Alcotest.(check (float 1e-12)) "after RESTORE" 1.0 (num (Option.get (Env.read_datum e)))

let test_load_data_resets_an_advanced_cursor () =
  let e = Env.create () in
  Env.load_data e [ Value.Num (Numtype.Single, 1.0); Value.Num (Numtype.Single, 2.0) ];
  ignore (Env.read_datum e);
  Env.load_data e [ Value.Num (Numtype.Single, 9.0); Value.Num (Numtype.Single, 8.0) ];
  Alcotest.(check (float 1e-12)) "cursor restarts at the new data's first item" 9.0
    (num (Option.get (Env.read_datum e)))

let test_user_defined_function () =
  let e = Env.create () in
  let body : Ast.expr = { enode = Ast.Num (Numtype.Single, 42.0); espan = Span.{ line = 0; start_col = 0; end_col = 0 } } in
  Env.define_fn e "FNA" [ "X" ] body;
  match Env.find_fn e "FNA" with
  | Some (params, { enode = Ast.Num (Numtype.Single, 42.0); _ }) -> Alcotest.(check (list string)) "params" [ "X" ] params
  | _ -> Alcotest.fail "expected the defined function to be found"

let test_find_fn_missing () =
  let e = Env.create () in
  Alcotest.(check bool) "missing function" true (Env.find_fn e "FNZ" = None)

let case n f = Alcotest.test_case n `Quick f

(* ref-9801 printed p.15 section 6.2: A!, A#, A% and A$ are four distinct
   variables, but "A!とAは同じ" -- A! and A are the SAME one. A bare name is
   the same name carrying whichever suffix its default kind implies.

   Env keyed the raw spelling until 2026-08-18, so these were two cells and
   "A=5 : PRINT A!" answered 0 -- a silent wrong answer, not an error. *)
let test_bare_name_aliases_its_default_suffix () =
  let e = Env.create () in
  Env.set_scalar e "A" (Value.Num (Numtype.Single, 5.0));
  Alcotest.(check (float 1e-12)) "A! reads what A wrote" 5.0 (num (Env.get_scalar e "A!"));
  Env.set_scalar e "B!" (Value.Num (Numtype.Single, 7.0));
  Alcotest.(check (float 1e-12)) "B reads what B! wrote" 7.0 (num (Env.get_scalar e "B"))

(* The distinguishing input for the rule above: the OTHER three suffixes must
   stay separate cells, or "they are the same" would be trivially satisfiable
   by collapsing everything onto one name. *)
let test_the_other_suffixes_stay_distinct () =
  let e = Env.create () in
  Env.set_scalar e "C!" (Value.Num (Numtype.Single, 1.0));
  Env.set_scalar e "C#" (Value.Num (Numtype.Double, 2.0));
  Env.set_scalar e "C%" (Value.Num (Numtype.Int, 3.0));
  Alcotest.(check (float 1e-12)) "C! kept its own value" 1.0 (num (Env.get_scalar e "C!"));
  Alcotest.(check (float 1e-12)) "C# kept its own value" 2.0 (num (Env.get_scalar e "C#"));
  Alcotest.(check (float 1e-12)) "C% kept its own value" 3.0 (num (Env.get_scalar e "C%"))

(* DEFxxx moves which suffix a bare name carries (printed p.60), so it moves
   which cell the bare name is. *)
let test_deftype_moves_which_suffix_a_bare_name_carries () =
  let e = Env.create () in
  Env.def_type e (Env.KNum Numtype.Int) [ ('E', 'E') ];
  Env.set_scalar e "E" (Value.Num (Numtype.Int, 9.0));
  Alcotest.(check (float 1e-12)) "E% reads what E wrote" 9.0 (num (Env.get_scalar e "E%"));
  Alcotest.(check (float 1e-12)) "E! is untouched" 0.0 (num (Env.get_scalar e "E!"))

let () =
  Alcotest.run "env"
    [ ( "scalars",
        [ case "defaults" test_scalar_defaults;
          case "roundtrip" test_scalar_roundtrip;
          case "shares name with array in separate namespace" test_scalar_and_array_share_name;
          case "bare name aliases its default suffix"
            test_bare_name_aliases_its_default_suffix;
          case "the other suffixes stay distinct" test_the_other_suffixes_stay_distinct;
          case "DEFxxx moves which suffix a bare name carries"
            test_deftype_moves_which_suffix_a_bare_name_carries
        ] );
      ( "arrays",
        [ case "inclusive DIM" test_dim_is_inclusive;
          case "out of range" test_subscript_out_of_range;
          case "negative bound" test_negative_dim_bound;
          case "oversized bound" test_oversized_dim_bound;
          case "two dimensions" test_two_dimensions;
          case "wrong subscript count on get_element" test_wrong_subscript_count_get;
          case "wrong subscript count on set_element" test_wrong_subscript_count_set;
          case "string array default" test_string_array_default;
          case "undimensioned defaults to 10" test_undimensioned_array_defaults_to_ten;
          case "undimensioned defaults to 10 per axis" test_undimensioned_array_defaults_to_ten_per_axis
        ] );
      ("functions", [ case "define and find" test_user_defined_function; case "missing" test_find_fn_missing ]);
      ( "data",
        [ case "cursor" test_data_cursor;
          case "load_data resets an advanced cursor" test_load_data_resets_an_advanced_cursor
        ] )
    ]
