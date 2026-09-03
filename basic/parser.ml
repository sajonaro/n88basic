(* Recursive-descent parser for one physical line's worth of tokens. Statements
   in this dialect never cross a line, so the parser never looks past the token
   list it is given; the line table (basic/program.ml) drives it line by line
   and turns a [Failure] here into a located error. *)

type state = {
  mutable toks : Token.t list;
  (* Span of the most recently consumed token. A node's span is built by
     stretching its first token's span out to this one. *)
  mutable last : Span.t;
}

let expr_at span enode = { Ast.enode; espan = span }
let stmt_at span snode = { Ast.snode; sspan = span }

let span_over (first : Span.t) (last : Span.t) : Span.t =
  { Span.line = first.line; start_col = first.start_col; end_col = last.end_col }

(* An empty span pinned just past [s] — where a datum the source left out
   would have started. *)
let empty_span_after (s : Span.t) : Span.t =
  { Span.line = s.line; start_col = s.end_col; end_col = s.end_col }

let peek_kind (st : state) : Token.kind option =
  match st.toks with [] -> None | t :: _ -> Some t.Token.kind

let at_end (st : state) : bool = st.toks = []

(* One token past [peek_kind]. Needed only to tell "PRINT A PRINT B", a
   missing separator, from "PRINT RESUME(1)", which is an attempt to use a
   reserved word as an array -- see [parse_print]. *)
let peek2_kind (st : state) : Token.kind option =
  match st.toks with _ :: t :: _ -> Some t.Token.kind | _ -> None

let here (st : state) : Span.t =
  match st.toks with
  | t :: _ -> t.Token.span
  | [] -> failwith "Unexpected end of line"

let advance (st : state) : unit =
  match st.toks with
  | [] -> ()
  | t :: rest ->
      st.last <- t.Token.span;
      st.toks <- rest

let is_punct (st : state) (p : string) : bool =
  match peek_kind st with Some (Token.Punct q) -> q = p | _ -> false

let accept_punct (st : state) (p : string) : bool =
  if is_punct st p then (
    advance st;
    true)
  else false

let expect_punct (st : state) (p : string) : unit =
  if not (accept_punct st p) then failwith (Printf.sprintf "Expected %S" p)

let is_keyword (st : state) (k : string) : bool =
  match peek_kind st with Some (Token.Keyword q) -> q = k | _ -> false

let accept_keyword (st : state) (k : string) : bool =
  if is_keyword st k then (
    advance st;
    true)
  else false

let expect_keyword (st : state) (k : string) : unit =
  if not (accept_keyword st k) then failwith (Printf.sprintf "Expected %s" k)

(* Built-in functions that lex as keywords. Everything else spelled like a
   call is either a user-defined FN or an array reference. POINT here covers
   BOTH function forms, told apart by arity when the call is evaluated:
   [2] POINT(Sx,Sy) reads a dot's palette number, [1] POINT(<function>)
   reads the LP back. The third form, the LP-setting POINT statement, is not
   a call at all and is parsed in statement position below. *)
let intrinsics =
  [ "ABS"; "INT"; "SQR"; "SGN"; "SIN"; "LEFT$"; "CHR$"; "VAL"; "POINT"; "RIGHT$";
    "MID$"; "LEN"; "ASC"; "INSTR"; "STR$"; "STRING$"; "HEX$"; "OCT$";
    "COS"; "TAN"; "ATN"; "LOG"; "EXP"; "FIX"; "CINT"; "CSNG"; "CDBL"; "SPACE$";
    "POS" ]

(* Whether a keyword can begin an expression. Exactly the keyword branches
   [parse_primary] accepts -- the intrinsics above, RND's optional-argument
   form, the three no-argument readers, FN, and NOT from the unary layer.

   It exists for PRINT's item list, which used to hand ANY unrecognised token
   to [parse_expr] and so reported a missing statement separator as
   "PRINT is a reserved word and cannot be used as a variable name" -- a
   message wrong twice over, since nothing was being used as a variable and,
   for the apostrophe form, the named keyword was one the listing never
   contained (the lexer synthesises Keyword "REM" for "'"). Stopping the item
   list here instead lets parse_statement_list report "Unexpected token after
   statement", which is what the assignment path has always said for the same
   mistake. *)
let keyword_starts_expression (k : string) : bool =
  List.mem k intrinsics || List.mem k [ "RND"; "CSRLIN"; "ERR"; "ERL"; "FN"; "NOT" ]

(* Every reserved word must be refused wherever a variable or array name is
   expected (spec/spec.md §3.4, manual Appendix E): a program that tries
   anyway gets a diagnostic naming the word, not a phantom array quietly
   answering 0 or "". The two helpers below cover the two ways a name can
   turn out reserved:

   - a token the lexer already classifies as [Token.Keyword] (every word in
     [Token.keywords] -- built-in functions and statements alike) can never
     match the [Token.Ident] patterns below in the first place, so the sites
     that build a Var/Index/lvalue/loop-variable/etc. out of an [Ident] never
     see one; what they need instead is a clear message at the few places
     that fall through to "no identifier here" when the token turns out to
     be one of these.
   - a word that is part of the language (spec/spec.md §3.2 deferred, §3.3
     out of scope) but has no statement grammar implemented here still lexes
     as a plain [Token.Ident] -- so [check_not_reserved] is called at every
     site that turns an [Ident] into a name, before it can become a Var or
     Index and silently auto-vivify into a zero-returning array. *)
let reserved_word_error (k : string) : 'a =
  failwith (Printf.sprintf "%s is a reserved word and cannot be used as a variable name" k)

(* Part of the language (spec/spec.md §3.2 "Deferred", §3.3 "Out of scope")
   but not lexed as a keyword, because no statement or expression grammar for
   it is implemented here. Left unchecked, one of these spelled with a
   following "(" parses as an ordinary array reference and silently
   evaluates to 0 or "" -- see [Token.keywords] for the in-scope half of the
   same bug. Compound tokens (PRINT#, DEF USR, LINE INPUT#, the COM: device,
   KEY beyond OFF) are not single identifiers and are not listed here. *)
(* Lives in Token because the LEXER needs it too: a reserved word whose own
   spelling ends in a sigil has to be recognised before the run is split, or
   "INPUT$" lexes as the INPUT keyword followed by a stray "$" and never
   reaches the check below. *)
let reserved_unimplemented = Token.reserved_unimplemented

let check_not_reserved (name : string) : unit =
  if List.mem name reserved_unimplemented then
    failwith
      (Printf.sprintf
         "%s is a reserved word (not implemented here) and cannot be used as a variable name"
         name)

(* PROG.VARIABLE-NAMES: an identifier whose letters start with "FN" names a
   user function (DEF FN's own namespace), never a variable -- so it is
   refused everywhere an ordinary name is expected. This is checked
   separately from [check_not_reserved] because the two sites that *build*
   an FN name (DEF FN's own header, and a call written "FNfoo(...)") must
   accept exactly the names this rejects; they call [check_not_reserved]
   directly instead of this. *)
let is_fn_prefixed (name : string) : bool =
  String.length name > 2 && String.sub name 0 2 = "FN"

let check_valid_name (name : string) : unit =
  check_not_reserved name;
  if is_fn_prefixed name then
    failwith
      (Printf.sprintf
         "%s is not a valid variable name (a name may not begin with FN, which is reserved for DEF FN)"
         name)

(* The lexer preserves whichever character order the source wrote a relational
   operator in; the parser settles on one spelling per operator so that the
   evaluator has a single case to handle. *)
let normalise_relational = function
  | "=>" -> ">="
  | "=<" -> "<="
  | "><" -> "<>"
  | op -> op

let binop op (l : Ast.expr) (r : Ast.expr) : Ast.expr =
  expr_at (span_over l.Ast.espan r.Ast.espan) (Ast.Binop (op, l, r))

(* Precedence climbing, loosest level first, following the manual's own
   numbered table (ref-9801 printed p.25 / PDF p.38, section 10.6):

     EQV(15) < IMP(14) < XOR(13) < OR(12) < AND(11) < NOT(10)
       < relational(9) < +,-(8) < MOD(7) < *,/(5) < unary -(4) < ^(3)

   (^ outranking the sign, rather than the reverse, is printed p.19 / PDF
   p.32.) One level of the table is absent: 6, the manual's yen sign for
   integer division, has no token at all -- it is the one member of the
   table this interpreter does not accept, and it fails loudly rather than
   quietly (spec.md section 3.3). *)
let rec parse_expr st = parse_eqv st

(* The three loosest levels of the manual's table, above OR: XOR at 13, IMP
   at 14 and EQV at 15 (ref-9801 printed p.25 / PDF p.38, section 10.6). *)
and parse_eqv st =
  let left = ref (parse_imp st) in
  while accept_keyword st "EQV" do
    left := binop "EQV" !left (parse_imp st)
  done;
  !left

and parse_imp st =
  let left = ref (parse_xor st) in
  while accept_keyword st "IMP" do
    left := binop "IMP" !left (parse_xor st)
  done;
  !left

and parse_xor st =
  let left = ref (parse_or st) in
  while accept_keyword st "XOR" do
    left := binop "XOR" !left (parse_or st)
  done;
  !left

and parse_or st =
  let left = ref (parse_and st) in
  while accept_keyword st "OR" do
    left := binop "OR" !left (parse_and st)
  done;
  !left

and parse_and st =
  let left = ref (parse_not st) in
  while accept_keyword st "AND" do
    left := binop "AND" !left (parse_not st)
  done;
  !left

(* NOT is level 10 in the manual's own precedence table (ref-9801 printed
   p.25 / PDF p.38, §10.6 演算の優先順位): BELOW the relational operators at
   9 and above AND at 11. So NOT A = B is NOT (A = B), not (NOT A) = B.

   It was previously handled in parse_unary, as a tight prefix binding above
   ^ — which is where almost every other language puts it, and is why the
   placement looked unremarkable. With A=1 and B=2 the two readings differ:
   the manual's gives NOT (1 = 2) = NOT 0 = -1, the old one gave 0. *)
and parse_not st =
  let start = here st in
  if accept_keyword st "NOT" then
    let operand = parse_not st in
    expr_at (span_over start operand.Ast.espan) (Ast.Unary ("NOT", operand))
  else parse_compare st

and parse_compare st =
  let left = parse_additive st in
  match peek_kind st with
  | Some (Token.Punct (("=" | "<" | ">" | "<=" | ">=" | "<>" | "=>" | "=<" | "><") as op))
    ->
      advance st;
      binop (normalise_relational op) left (parse_additive st)
  | _ -> left

and parse_additive st =
  let left = ref (parse_mod st) in
  let continue = ref true in
  while !continue do
    match peek_kind st with
    | Some (Token.Punct (("+" | "-") as op)) ->
        advance st;
        left := binop op !left (parse_mod st)
    | _ -> continue := false
  done;
  !left

(* MOD, the integer remainder, at level 7 -- tighter than + and - at 8,
   looser than \\ at 6 (ref-9801 printed p.25 / PDF p.38). *)
and parse_mod st =
  let left = ref (parse_intdiv st) in
  while accept_keyword st "MOD" do
    left := binop "MOD" !left (parse_intdiv st)
  done;
  !left

(* "\\", integer division, at level 6 -- between MOD at 7 and * and / at 5
   (ref-9801 printed p.25). It sits in the same table as MOD and is described
   in the same paragraph of printed p.20, which is the reasoning that brought
   it into scope: excluding a table-mate of the four operators already ruled
   in was hard to justify. *)
and parse_intdiv st =
  let left = ref (parse_multiplicative st) in
  let continue = ref true in
  while !continue do
    match peek_kind st with
    | Some (Token.Punct "\\") ->
        advance st;
        left := binop "\\" !left (parse_multiplicative st)
    | _ -> continue := false
  done;
  !left

and parse_multiplicative st =
  let left = ref (parse_unary st) in
  let continue = ref true in
  while !continue do
    match peek_kind st with
    | Some (Token.Punct (("*" | "/") as op)) ->
        advance st;
        left := binop op !left (parse_unary st)
    | _ -> continue := false
  done;
  !left

(* ^ binds tighter than unary minus, and associates to the LEFT.

   Both come off ref-9801 printed p.19-20 / PDF p.32-33. §10.1's arithmetic
   table is ordered by 実行順序 with the arrow running downward, and it puts
   ^ above the 負号 row, so -2^2 is -(2^2) = -4 rather than (-2)^2 = 4.
   Page 20's worked examples settle the association from the other side: the
   algebraic X^(Y²) is written with parentheses as X^(Y^2), while (X^Y)² is
   written bare as X^Y^2 -- which is only true if a bare run of ^ groups
   leftwards. So 2^3^2 is (2^3)^2 = 64, not 2^(3^2) = 512.

   Both readings are the opposite of what most later languages do, which is
   what made the old code look right: it climbed rightwards from a unary
   operand, giving 4 and 512, and nothing complained because a wrong number
   is not an error. *)
and parse_power st =
  let base = ref (parse_primary st) in
  while accept_punct st "^" do
    (* The exponent takes its own sign but not its own ^ run: parse_exponent
       stops at an atom, so a following ^ is picked up by this loop and binds
       leftwards. Recursing into parse_power here is exactly what made it
       right-associative before. A sign is still allowed, because the manual
       prints PRINT 0^-1 on p.20. *)
    let rhs = parse_exponent st in
    base := binop "^" !base rhs
  done;
  !base

(* A signed atom: the operand on the right of ^. *)
and parse_exponent st =
  let start = here st in
  if accept_punct st "-" then
    let operand = parse_exponent st in
    expr_at (span_over start operand.Ast.espan) (Ast.Unary ("-", operand))
  else parse_primary st

and parse_unary st =
  let start = here st in
  if accept_punct st "-" then
    let operand = parse_unary st in
    expr_at (span_over start operand.Ast.espan) (Ast.Unary ("-", operand))
  else parse_power st

(* A parenthesised argument list, one or more expressions. Leaves [st.last] on
   the closing parenthesis so callers can span up to it. *)
and parse_args st =
  expect_punct st "(";
  let args = ref [ parse_expr st ] in
  while accept_punct st "," do
    args := parse_expr st :: !args
  done;
  expect_punct st ")";
  List.rev !args

(* A user function's argument list, which -- unlike an intrinsic's -- may be
   absent entirely, because DEF FN's own parameter list may be
   (ref-9801 printed p.59 / PDF p.70). DEF FNA=7 defines FNA, and FNA is
   then how it is called: there is no empty pair of parentheses to write. *)
and parse_fn_args st = if is_punct st "(" then parse_args st else []

and parse_primary st =
  match peek_kind st with
  | Some (Token.Number (t, n)) ->
      let span = here st in
      advance st;
      expr_at span (Ast.Num (t, n))
  | Some (Token.Str s) ->
      let span = here st in
      advance st;
      expr_at span (Ast.Str s)
  | Some (Token.Keyword k) when List.mem k intrinsics ->
      let start = here st in
      advance st;
      let args = parse_args st in
      expr_at (span_over start st.last) (Ast.Call (k, args))
  (* RND's argument is optional, and its parenthesised form is a single
     expression like any other intrinsic, so it cannot share the branch
     above (which always requires "("). *)
  | Some (Token.Keyword "RND") ->
      let start = here st in
      advance st;
      let args = if is_punct st "(" then parse_args st else [] in
      expr_at (span_over start st.last) (Ast.Call ("RND", args))
  (* CSRLIN, ERR and ERL are always written bare -- the manual shows no
     parenthesised form for any of the three (spec/spec.md PRINT.CSRLIN,
     ERR.FN, ERR.ERL). *)
  | Some (Token.Keyword (("CSRLIN" | "ERR" | "ERL") as k)) ->
      let span = here st in
      advance st;
      expr_at span (Ast.Call (k, []))
  (* "FN" written with a space before its name (e.g. "FN A(1)") still lexes
     as its own [Token.Keyword "FN"] followed by an [Ident] -- the scanner's
     maximal-munch identifier run only fuses "FN" and the name into one
     token when nothing delimits them (see basic/lexer.ml). The jammed form
     ("FNA(1)", how DEF FN itself is always written) is the [is_fn_prefixed]
     branch just below instead, since there the whole thing is one token. *)
  | Some (Token.Keyword "FN") ->
      let start = here st in
      advance st;
      let name =
        match peek_kind st with
        | Some (Token.Ident id) ->
            advance st;
            check_not_reserved id;
            "FN" ^ id
        | _ -> failwith "Expected a function name after FN"
      in
      let args = parse_fn_args st in
      expr_at (span_over start st.last) (Ast.Call (name, args))
  (* PROG.VARIABLE-NAMES: a name beginning with "FN" is never a variable or
     array -- it can only be a call to a user function defined by DEF FN, so
     it is dispatched to [Ast.Call] here rather than falling into the
     [Ast.Index]/[Ast.Var] case below. *)
  | Some (Token.Ident name) when is_fn_prefixed name ->
      let start = here st in
      advance st;
      check_not_reserved name;
      let args = parse_fn_args st in
      expr_at (span_over start st.last) (Ast.Call (name, args))
  | Some (Token.Ident name) ->
      let start = here st in
      advance st;
      check_valid_name name;
      if is_punct st "(" then
        let args = parse_args st in
        expr_at (span_over start st.last) (Ast.Index (name, args))
      else expr_at start (Ast.Var name)
  (* Any other reserved word (a statement keyword, or SPC -- which is only
     ever valid inside a PRINT/LPRINT list, see [parse_print]) reaching here
     was asked for where an expression was expected. *)
  | Some (Token.Keyword k) -> reserved_word_error k
  | Some (Token.Punct "(") ->
      let start = here st in
      advance st;
      let e = parse_expr st in
      expect_punct st ")";
      (* Re-span so the node covers its parentheses. *)
      { e with Ast.espan = span_over start st.last }
  | _ -> failwith "Expected an expression"

let parse_lvalue st : Ast.lvalue =
  match peek_kind st with
  | Some (Token.Ident name) ->
      advance st;
      check_valid_name name;
      if is_punct st "(" then Ast.LIndex (name, parse_args st) else Ast.LVar name
  | Some (Token.Keyword k) -> reserved_word_error k
  | _ -> failwith "Expected a variable"

let parse_lvalue_list st =
  let targets = ref [ parse_lvalue st ] in
  while accept_punct st "," do
    targets := parse_lvalue st :: !targets
  done;
  List.rev !targets

let parse_expr_list st =
  let items = ref [ parse_expr st ] in
  while accept_punct st "," do
    items := parse_expr st :: !items
  done;
  List.rev !items

(* A line reference is a line number or a label standing in for one
   (ref-9801 printed p.29 / PDF p.42). "*" is unambiguous here even though it
   also spells multiplication: a line reference is never an expression
   position, so nothing else could begin with one. *)
let parse_line_ref st : Ast.line_ref =
  match peek_kind st with
  | Some (Token.Number (_, n)) ->
      let span = here st in
      advance st;
      { Ast.target = Ast.LineNumber (int_of_float n); target_span = span }
  | Some (Token.Punct "*") -> (
      let start = here st in
      advance st;
      match peek_kind st with
      | Some (Token.Ident name) ->
          advance st;
          { Ast.target = Ast.LabelName name; target_span = span_over start st.last }
      | Some (Token.Keyword k) -> reserved_word_error k
      | _ -> failwith "Expected a label name after \"*\"")
  | _ -> failwith "Expected a line number or a label"

(* Whether a line reference could start here, so that THEN's and ELSE's
   branches can tell "*EXIT" (a jump) from a statement list. *)
let starts_line_ref (st : state) : bool =
  match peek_kind st with
  | Some (Token.Number _) | Some (Token.Punct "*") -> true
  | _ -> false

(* The comma-separated line list of ON...GOTO / ON...GOSUB. *)
let parse_line_ref_list st : Ast.line_ref list =
  let refs = ref [ parse_line_ref st ] in
  while accept_punct st "," do
    refs := parse_line_ref st :: !refs
  done;
  List.rev !refs

(* ERASE's array-name list: bare names, no subscripts or "()" (spec/spec.md
   PROG.ERASE) -- unlike [parse_lvalue], which would accept a following "(". *)
let parse_name_list st : string list =
  let one () =
    match peek_kind st with
    | Some (Token.Ident name) ->
        advance st;
        check_valid_name name;
        name
    | Some (Token.Keyword k) -> reserved_word_error k
    | _ -> failwith "Expected an array name"
  in
  let names = ref [ one () ] in
  while accept_punct st "," do
    names := one () :: !names
  done;
  List.rev !names

let parse_point st =
  expect_punct st "(";
  let x = parse_expr st in
  expect_punct st ",";
  let y = parse_expr st in
  expect_punct st ")";
  (x, y)

(* PSET/PRESET's coordinate: STEP(x,y) relative to the LP, or a bare
   (Wx,Wy). STEP is already a keyword (FOR's STEP), so no lexer change is
   needed. *)
let parse_point_spec st : Ast.point_spec =
  if accept_keyword st "STEP" then
    let x, y = parse_point st in
    Ast.PStep (x, y)
  else
    let x, y = parse_point st in
    Ast.PAbs (x, y)

let parse_box st : [ `None | `Frame | `Filled ] =
  match peek_kind st with
  | Some (Token.Ident "B") ->
      advance st;
      `Frame
  | Some (Token.Ident "BF") ->
      advance st;
      `Filled
  | _ -> failwith "Expected B or BF"

let parse_line_spec st : Ast.line_spec =
  (* Either endpoint may be written STEP(dx,dy) as well as (x,y) -- the
     manual's syntax box offers both alternatives on both sides (ref-9801
     printed p.94 / PDF p.105) -- so both go through [parse_point_spec],
     the same one PSET and PRESET use. Only the first is optional. *)
  let from_point =
    if is_punct st "(" || is_keyword st "STEP" then Some (parse_point_spec st) else None
  in
  expect_punct st "-";
  let to_point = parse_point_spec st in
  let colour = ref None in
  let box = ref `None in
  let trailing = ref None in
  (* The first slot after the coordinates is always the colour, and a listing
     that wants a box without one writes the doubled comma. B and BF are read
     only in the second slot, so `,B` is a colour held in a variable named B —
     an ordinary name in this dialect — rather than a box flag. The third
     slot is the line style, or BF's fill colour or tile string; which it is
     depends on the second, so the parser leaves it an expression and the
     evaluator decides. *)
  if accept_punct st "," then begin
    if not (is_punct st ",") then colour := Some (parse_expr st);
    if accept_punct st "," then begin
      (* The B/BF slot may itself be left empty, which is how a plain line
         reaches its line style: the manual's own worked example is
         LINE(100,100)-(135,100),7,,&HF99F -- colour, nothing, style
         (ref-9801 printed p.94 / PDF p.105). *)
      if not (is_punct st ",") then box := parse_box st;
      if accept_punct st "," then trailing := Some (parse_expr st)
    end
  end;
  { Ast.from_point; to_point; colour = !colour; box = !box; trailing = !trailing }

(* An optional expression before a slot's trailing comma (or the statement's
   end): a bare comma or nothing at all leaves that slot unset, exactly as
   `COLOR ,,,7` touches only the fourth slot. *)
let parse_optional_expr st : Ast.expr option =
  if at_end st || is_punct st "," || is_punct st ":" then None else Some (parse_expr st)

(* COLOR has two unrelated forms sharing one keyword: [1] COLOR sets the
   text/graphics colours from plain comma-separated arguments (ref-9801
   printed p.49); [2] COLOR — an `=` immediately after the keyword —
   reassigns which colour a palette number displays (printed p.51).

   A THIRD form hides between them, and it is why truly-bare COLOR cannot be
   parsed as [1] COLOR with every slot empty: printed p.51 says that omitting
   the equals sign *and* both arguments — writing just "COLOR" — initialises
   the palette mapping. That is [2] COLOR's initialising form, not a [1]
   COLOR that happens to set nothing, and the two are otherwise
   indistinguishable in the AST because `COLOR ,,,` also leaves every slot
   empty. The difference is purely syntactic, so it has to be settled here.

   Writing the `=` commits the statement to both arguments: the manual
   brackets the whole `=(<palette>,<code>)` group and neither argument
   within it, so `COLOR=` alone and `COLOR=(2,)` are syntax errors. That
   reading is ours -- the page does not discuss a malformed one. *)
let parse_color st : Ast.stmt_node =
  if accept_punct st "=" then begin
    expect_punct st "(";
    let pal = parse_expr st in
    expect_punct st ",";
    let code = parse_expr st in
    expect_punct st ")";
    Ast.ColorPalette (Some pal, Some code)
  end
  else if at_end st || is_punct st ":" then Ast.ColorPalette (None, None)
  else
    let function_code = parse_optional_expr st in
    let background = if accept_punct st "," then parse_optional_expr st else None in
    let border = if accept_punct st "," then parse_optional_expr st else None in
    let foreground = if accept_punct st "," then parse_optional_expr st else None in
    let palette_mode = if accept_punct st "," then parse_optional_expr st else None in
    Ast.Color { function_code; background; border; foreground; palette_mode }

(* The tail of CIRCLE's F clause, once the "F" token itself has already been
   consumed: an optional trailing palette number or tile string (ref-9801
   printed p.45). Which of the two it turned out to be is not decided here —
   see Ast.circle_fill. *)
let parse_circle_fill_tail st : Ast.circle_fill =
  if accept_punct st "," then Ast.Fill_with (parse_expr st) else Ast.Fill_default

(* A comma has just been accepted and the slot it introduces is expected to
   hold "F" (not an aspect ratio); used when <比率> was already given a real
   value and F can still follow as its own, separately-comma'd field. *)
let parse_fill_flag_after_comma st : Ast.circle_fill =
  match peek_kind st with
  | Some (Token.Ident "F") ->
      advance st;
      parse_circle_fill_tail st
  | _ -> failwith "Expected F"

(* CIRCLE (Wx,Wy)|STEP(x,y), <radius>[,<palette 1>][,<start angle>]
   [,<end angle>][,<aspect>][,F[,<palette 2>|<tile string>]] (ref-9801
   printed p.45). <aspect> and F share one comma-gated slot rather than
   getting one each: the manual's own second example,
   "CIRCLE STEP(40,-20),30,,,,F,TILE$", skips <palette 1>, <start angle> and
   <end angle> with one comma apiece and then reaches F with a *single*
   further comma -- not two -- so the slot after <end angle> holds either a
   numeric aspect ratio or the literal token F, and only when a real aspect
   value is given does F get a comma of its own afterward. *)
let parse_circle_spec st : Ast.circle_spec =
  let center = parse_point_spec st in
  expect_punct st ",";
  let radius = parse_expr st in
  let palette = if accept_punct st "," then parse_optional_expr st else None in
  let start_angle = if accept_punct st "," then parse_optional_expr st else None in
  let end_angle = if accept_punct st "," then parse_optional_expr st else None in
  let aspect, fill =
    if accept_punct st "," then
      match peek_kind st with
      | Some (Token.Ident "F") ->
          advance st;
          (None, parse_circle_fill_tail st)
      | _ ->
          let aspect = parse_optional_expr st in
          let fill =
            if accept_punct st "," then parse_fill_flag_after_comma st else Ast.No_fill
          in
          (aspect, fill)
    else (None, Ast.No_fill)
  in
  { Ast.center; radius; palette; start_angle; end_angle; aspect; fill }

(* PAINT (Wx,Wy)|STEP(x,y)[,<area>[,<border>]] (ref-9801 printed p.117). The
   tiling form [2] (printed p.118, out of scope) shares this exact shape
   with a tile string standing in for <area>, so both parse the same way;
   interp.ml tells them apart once <area> is evaluated and refuses form [2]. *)
let parse_paint_spec st : Ast.paint_spec =
  let start = parse_point_spec st in
  let area = if accept_punct st "," then parse_optional_expr st else None in
  let boundary = if accept_punct st "," then parse_optional_expr st else None in
  { Ast.start; area; boundary }

let rec parse_statement st : Ast.stmt =
  let start = here st in
  let node = parse_statement_node st in
  stmt_at (span_over start st.last) node

(* A bare line number as a THEN or ELSE branch. The synthesised statement spans
   the digits and nothing else, so a diagnostic about the target underlines the
   target rather than the whole IF. *)
and parse_jump_to_line st : Ast.stmt =
  let target = parse_line_ref st in
  stmt_at target.Ast.target_span (Ast.Goto target)

and parse_statement_node st : Ast.stmt_node =
  match peek_kind st with
  (* "*NAME" at a statement position defines a label (ref-9801 printed p.29 /
     PDF p.42). Every reference position consumes its "*" before reaching
     here, and multiplication only ever appears inside an expression, so a "*"
     that reaches a statement position can only be a definition. *)
  | Some (Token.Punct "*") -> (
      advance st;
      match peek_kind st with
      | Some (Token.Ident name) ->
          advance st;
          check_valid_name name;
          Ast.LabelDef name
      | Some (Token.Keyword k) -> reserved_word_error k
      | _ -> failwith "Expected a label name after \"*\"")
  | Some (Token.Keyword "REM") ->
      advance st;
      (* The lexer emits the rest of the line as a Str after REM. *)
      (match peek_kind st with
      | Some (Token.Str text) ->
          advance st;
          Ast.Rem text
      | _ -> Ast.Rem "")
  | Some (Token.Keyword "END") ->
      advance st;
      Ast.End
  | Some (Token.Keyword "STOP") ->
      advance st;
      Ast.Stop
  | Some (Token.Keyword "RETURN") ->
      advance st;
      (* RETURN [<line number>] (ref-9801 printed p.136 / PDF p.147). Only a
         following Number opens the second form, the same shape RESUME reads,
         so a bare RETURN before ":" or ELSE stays the plain one. *)
      if starts_line_ref st then Ast.Return (Some (parse_line_ref st)) else Ast.Return None
  | Some (Token.Keyword "CLS") ->
      advance st;
      Ast.Cls (parse_optional_expr st)
  | Some (Token.Keyword "KEY") ->
      advance st;
      (* KEY[(<key number>)] ON|OFF|STOP. The parentheses come as a pair with
         the number and are left out with it, which is the form that means
         every function key. *)
      let key_number =
        if accept_punct st "(" then begin
          let e = parse_expr st in
          expect_punct st ")";
          Some e
        end
        else None
      in
      let key_action =
        if accept_keyword st "ON" then Ast.Key_on
        else if accept_keyword st "OFF" then Ast.Key_off
        else if accept_keyword st "STOP" then Ast.Key_stop
        else failwith "Expected ON, OFF or STOP after KEY"
      in
      Ast.Key { Ast.key_number; key_action }
  | Some (Token.Keyword "SCREEN") ->
      advance st;
      (* Every slot optional, empty ones written as bare commas, the same
         shape LOCATE and COLOR read — so "SCREEN ,,0,1" sets only the pages
         and a bare "SCREEN" sets nothing at all. *)
      let mode = parse_optional_expr st in
      let switch = if accept_punct st "," then parse_optional_expr st else None in
      let active = if accept_punct st "," then parse_optional_expr st else None in
      let display = if accept_punct st "," then parse_optional_expr st else None in
      Ast.Screen { Ast.mode; switch; active; display }
  | Some (Token.Keyword "WIDTH") ->
      advance st;
      Ast.Width (parse_expr_list st)
  | Some (Token.Keyword "LOCATE") ->
      advance st;
      (* Every slot optional, and empty slots written as bare commas, the
         same shape [parse_color] reads — so "LOCATE ,,0" sets only the
         cursor switch and "LOCATE 10" only the column. *)
      let x = parse_optional_expr st in
      let y = if accept_punct st "," then parse_optional_expr st else None in
      let cursor = if accept_punct st "," then parse_optional_expr st else None in
      Ast.Locate { Ast.x; y; cursor }
  | Some (Token.Keyword "CONSOLE") ->
      advance st;
      (* Four optional slots, empty ones written as bare commas -- the shape
         [parse_color] reads, and what the manual's own "CONSOLE ,,1,0"
         example needs (ref-9801 printed p.54 / PDF p.65). *)
      let scroll_start = parse_optional_expr st in
      let scroll_lines = if accept_punct st "," then parse_optional_expr st else None in
      let function_keys = if accept_punct st "," then parse_optional_expr st else None in
      let colour_mode = if accept_punct st "," then parse_optional_expr st else None in
      Ast.Console { Ast.scroll_start; scroll_lines; function_keys; colour_mode }
  | Some (Token.Keyword "LINE") ->
      advance st;
      if accept_keyword st "INPUT" then
        (* LINE INPUT [<prompt>;] <string var> (ref-9801 printed p.95 / PDF
           p.106): the syntax box brackets "<prompt>;" as one unit, so a
           prompt with no following ";" is not the form given -- unlike
           INPUT's own box, there is no "," alternative here. *)
        let prompt =
          match peek_kind st with
          | Some (Token.Str s) ->
              advance st;
              expect_punct st ";";
              Some s
          | _ -> None
        in
        Ast.LineInput (prompt, parse_lvalue st)
      else Ast.Line (parse_line_spec st)
  (* POINT as a STATEMENT -- ref-9801 printed p.122, "POINT (Wx,Wy)" or
     "POINT STEP(x,y)". Unambiguous against the two POINT functions, which
     can only appear in expression position. *)
  | Some (Token.Keyword "POINT") ->
      advance st;
      Ast.PointLp (parse_point_spec st)
  | Some (Token.Keyword "PSET") ->
      advance st;
      let point = parse_point_spec st in
      let colour = if accept_punct st "," then Some (parse_expr st) else None in
      Ast.Pset (point, colour)
  | Some (Token.Keyword "PRESET") ->
      advance st;
      let point = parse_point_spec st in
      let colour = if accept_punct st "," then Some (parse_expr st) else None in
      Ast.Preset (point, colour)
  | Some (Token.Keyword "COLOR") ->
      advance st;
      parse_color st
  | Some (Token.Keyword "CIRCLE") ->
      advance st;
      Ast.Circle (parse_circle_spec st)
  | Some (Token.Keyword "PAINT") ->
      advance st;
      Ast.Paint (parse_paint_spec st)
  | Some (Token.Keyword "GOTO") ->
      advance st;
      Ast.Goto (parse_line_ref st)
  | Some (Token.Keyword "GOSUB") ->
      advance st;
      Ast.Gosub (parse_line_ref st)
  | Some (Token.Keyword "ON") ->
      advance st;
      if accept_keyword st "ERROR" then begin
        expect_keyword st "GOTO";
        Ast.OnErrorGoto (parse_line_ref st)
      end
      else
        let selector = parse_expr st in
        if accept_keyword st "GOSUB" then Ast.OnGosub (selector, parse_line_ref_list st)
        else if accept_keyword st "GOTO" then Ast.OnGoto (selector, parse_line_ref_list st)
        else failwith "Expected GOTO or GOSUB after ON <expr>"
  | Some (Token.Keyword "RESUME") ->
      advance st;
      (match peek_kind st with
      | Some (Token.Keyword "NEXT") ->
          advance st;
          Ast.Resume Ast.ResumeNext
      (* "RESUME *START" is the manual's own example for this statement
         (printed p.136 / PDF p.147), so a label is read here as well as a
         number. *)
      | Some (Token.Number _) | Some (Token.Punct "*") ->
          let r = parse_line_ref st in
          if r.Ast.target = Ast.LineNumber 0 then Ast.Resume Ast.ResumeSame
          else Ast.Resume (Ast.ResumeLine r)
      | _ -> Ast.Resume Ast.ResumeSame)
  | Some (Token.Keyword "ERROR") ->
      advance st;
      Ast.RaiseError (parse_expr st)
  | Some (Token.Keyword "WHILE") ->
      advance st;
      Ast.While (parse_expr st)
  | Some (Token.Keyword "WEND") ->
      advance st;
      Ast.Wend
  | Some (Token.Keyword "SWAP") ->
      advance st;
      let a = parse_lvalue st in
      expect_punct st ",";
      let b = parse_lvalue st in
      Ast.Swap (a, b)
  | Some (Token.Keyword "ERASE") ->
      advance st;
      Ast.Erase (parse_name_list st)
  | Some (Token.Keyword "RANDOMIZE") ->
      advance st;
      Ast.Randomize (parse_optional_expr st)
  | Some (Token.Keyword "CLEAR") ->
      advance st;
      let args = ref [] in
      if not (at_end st || is_punct st ":") then begin
        args := [ parse_optional_expr st ];
        while accept_punct st "," do
          args := parse_optional_expr st :: !args
        done
      end;
      Ast.Clear (List.rev !args)
  | Some (Token.Keyword "OPTION") ->
      advance st;
      expect_keyword st "BASE";
      (match peek_kind st with
      | Some (Token.Number (_, n)) when n = 0.0 || n = 1.0 ->
          advance st;
          Ast.OptionBase (int_of_float n)
      | _ -> failwith "Expected 0 or 1 after OPTION BASE")
  | Some (Token.Keyword "RESTORE") ->
      advance st;
      (match peek_kind st with
      | Some (Token.Number _) -> Ast.Restore (Some (parse_line_ref st))
      | _ -> Ast.Restore None)
  | Some (Token.Keyword "LET") ->
      advance st;
      parse_assignment st
  | Some (Token.Keyword "MID$") ->
      advance st;
      parse_mid_assignment st
  | Some (Token.Keyword "PRINT") ->
      advance st;
      parse_print st Ast.ToScreen
  | Some (Token.Keyword "LPRINT") ->
      advance st;
      parse_print st Ast.ToPrinter
  | Some (Token.Keyword "WRITE") ->
      advance st;
      Ast.Write (parse_write_items st)
  | Some (Token.Keyword "INPUT") ->
      advance st;
      (* The syntax box brackets the prompt together with the ";" or ","
         that follows it, so one of the two is required once a prompt is
         given -- and which one it is changes what reaches the screen
         (ref-9801 printed p.82 / PDF p.93). A statement with no prompt has
         no separator to carry, and shows "? " as though ";" had been
         written. *)
      let prompt, show_question =
        match peek_kind st with
        | Some (Token.Str s) ->
            advance st;
            if accept_punct st ";" then (Some s, true)
            else if accept_punct st "," then (Some s, false)
            else failwith "Expected \";\" or \",\" after an INPUT prompt"
        | _ -> (None, true)
      in
      Ast.Input { Ast.prompt; show_question; targets = parse_lvalue_list st }
  | Some (Token.Keyword "FOR") ->
      advance st;
      let var =
        match peek_kind st with
        | Some (Token.Ident v) ->
            advance st;
            check_valid_name v;
            v
        | Some (Token.Keyword k) -> reserved_word_error k
        | _ -> failwith "Expected a loop variable"
      in
      expect_punct st "=";
      let from = parse_expr st in
      expect_keyword st "TO";
      let upto = parse_expr st in
      let step =
        (* An omitted STEP is 1. The synthesised node stands for no source
           text, so it gets an empty span where the STEP would have been --
           and the integer type a literal "1" would itself classify as
           (Numtype's own rule: a whole number in range, no suffix). *)
        if accept_keyword st "STEP" then parse_expr st
        else expr_at (empty_span_after st.last) (Ast.Num (Numtype.Int, 1.0))
      in
      Ast.For (var, from, upto, step)
  | Some (Token.Keyword "NEXT") ->
      advance st;
      (match peek_kind st with
      | Some (Token.Ident v) ->
          advance st;
          Ast.Next (Some v)
      | _ -> Ast.Next None)
  | Some (Token.Keyword "IF") ->
      advance st;
      let cond = parse_expr st in
      (* A branch is a jump when it is a bare line reference -- a number, or a
         label, as in the manual's own "20 IF A<0 THEN *MINUS" (printed p.29 /
         PDF p.42) -- and a statement list otherwise. *)
      let branch () =
        if starts_line_ref st then [ parse_jump_to_line st ] else parse_statement_list st
      in
      (* Two forms, both in the manual's syntax box (ref-9801 printed p.80 /
         PDF p.91): "IF <cond> THEN <stmt>|<line>" and the THEN-less
         "IF <cond> GOTO <line>". Only THEN's branch may be a statement -- the
         box gives GOTO's branch as <line number> alone -- so the GOTO form
         reads a line reference and nothing else. ELSE is shared by both. *)
      let then_branch =
        if accept_keyword st "THEN" then branch ()
        else if accept_keyword st "GOTO" then [ parse_jump_to_line st ]
        else failwith "Expected THEN or GOTO after an IF condition"
      in
      let else_branch = if accept_keyword st "ELSE" then branch () else [] in
      Ast.If (cond, then_branch, else_branch)
  | Some (Token.Keyword "DIM") ->
      advance st;
      let one () =
        match peek_kind st with
        | Some (Token.Ident name) ->
            advance st;
            check_valid_name name;
            (name, parse_args st)
        | Some (Token.Keyword k) -> reserved_word_error k
        | _ -> failwith "Expected an array name"
      in
      let decls = ref [ one () ] in
      while accept_punct st "," do
        decls := one () :: !decls
      done;
      Ast.Dim (List.rev !decls)
  | Some (Token.Keyword "DATA") ->
      advance st;
      Ast.Data (parse_data_items st)
  | Some (Token.Keyword "READ") ->
      advance st;
      Ast.Read (parse_lvalue_list st)
  | Some (Token.Keyword "DEF") ->
      advance st;
      (* The ordinary spelling "DEF FNA(...)" jams "FN" against the function's
         name with no space, so the maximal-munch scanner (basic/lexer.ml)
         already hands this back as one [Ident] starting with "FN" -- the
         same shape [is_fn_prefixed] recognises in [parse_primary]. A source
         that puts a space in ("DEF FN A(...)") still lexes as
         [Keyword "FN"] followed by its own [Ident], since the space is a
         delimiter; both are accepted here. *)
      let name =
        match peek_kind st with
        | Some (Token.Ident id) when is_fn_prefixed id ->
            advance st;
            check_not_reserved id;
            id
        | Some (Token.Keyword "FN") -> (
            advance st;
            match peek_kind st with
            | Some (Token.Ident id) ->
                advance st;
                check_not_reserved id;
                "FN" ^ id
            | _ -> failwith "Expected a function name after DEF FN")
        | _ -> failwith "Expected a function name after DEF FN"
      in
      (* The parameter list is bracketed in the manual's syntax box, so it
         may be left off entirely: DEF FNA=7 defines a function of no
         arguments (ref-9801 printed p.59 / PDF p.70). *)
      let params = ref [] in
      if accept_punct st "(" then begin
        let one () =
          match peek_kind st with
          | Some (Token.Ident p) ->
              advance st;
              check_valid_name p;
              params := p :: !params
          | Some (Token.Keyword k) -> reserved_word_error k
          | _ -> failwith "Expected a parameter"
        in
        one ();
        while accept_punct st "," do
          one ()
        done;
        expect_punct st ")"
      end;
      expect_punct st "=";
      Ast.DefFn (name, List.rev !params, parse_expr st)
  | Some (Token.Keyword ("DEFINT" | "DEFSNG" | "DEFDBL" | "DEFSTR" as kw)) ->
      advance st;
      let def_kind =
        match kw with
        | "DEFINT" -> Ast.DInt
        | "DEFSNG" -> Ast.DSingle
        | "DEFDBL" -> Ast.DDouble
        | _ -> Ast.DStr
      in
      (* Each range is one letter, or two joined by "-" (ref-9801 printed
         p.60 / PDF p.71). A letter lexes as a length-1 [Ident] -- the same
         token a bare one-letter variable name would be -- so it is
         recognised by that shape rather than by any dedicated syntax. *)
      let letter () =
        match peek_kind st with
        | Some (Token.Ident s) when String.length s = 1 ->
            advance st;
            s.[0]
        | _ -> failwith "Expected a letter"
      in
      let range () =
        let lo = letter () in
        if accept_punct st "-" then (lo, letter ()) else (lo, lo)
      in
      let ranges = ref [ range () ] in
      while accept_punct st "," do
        ranges := range () :: !ranges
      done;
      Ast.DefType (def_kind, List.rev !ranges)
  | _ -> parse_assignment st

and parse_assignment st =
  let target = parse_lvalue st in
  expect_punct st "=";
  Ast.Let (target, parse_expr st)

(* MID$(A$, n[, m]) = expr — parsed separately from [parse_assignment] because
   its target is not an [lvalue]: the parenthesised argument list belongs to
   MID$ itself, not to a subscript on the variable inside it. *)
and parse_mid_assignment st =
  expect_punct st "(";
  let name =
    match peek_kind st with
    | Some (Token.Ident id) ->
        advance st;
        check_valid_name id;
        id
    | Some (Token.Keyword k) -> reserved_word_error k
    | _ -> failwith "Expected a string variable"
  in
  expect_punct st ",";
  let start = parse_expr st in
  let len = if accept_punct st "," then Some (parse_expr st) else None in
  expect_punct st ")";
  expect_punct st "=";
  Ast.MidAssign (name, start, len, parse_expr st)

(* DATA items arrive already classified by the lexer, which scans them as raw
   text: an unquoted item is a Number if it parses as one and a Str otherwise.

   Each comma declares that a further item follows it, so `DATA 1,` and
   `DATA 1,,2` both name an empty datum — at the end and in the middle. A
   `DATA` with no commas and no text is a deliberate exception rather than a
   consequence of that rule: it declares nothing, where the rule taken
   literally would give it one empty item, because an empty statement reads as
   unfinished rather than as asserting a blank. The empty datum is a Str:
   whether that is an error depends on the variable a READ puts it into, which
   is the evaluator's business, not the parser's. *)
and parse_data_items st =
  let datum () =
    match peek_kind st with
    | Some (Token.Number (t, n)) ->
        let span = here st in
        advance st;
        expr_at span (Ast.Num (t, n))
    | Some (Token.Str s) ->
        let span = here st in
        advance st;
        expr_at span (Ast.Str s)
    | None -> expr_at (empty_span_after st.last) (Ast.Str "")
    | Some _ -> failwith "Expected a DATA item"
  in
  if at_end st then []
  else begin
    let items = ref [ datum () ] in
    while accept_punct st "," do
      items := datum () :: !items
    done;
    List.rev !items
  end

(* WRITE <expr>[(,|;)<expr>...] (ref-9801 printed p.161 / PDF p.172): unlike
   PRINT, "," and ";" are interchangeable here -- the manual states outright
   there is no functional difference between them for WRITE -- so either is
   accepted between items. At least one expression is required: the box's
   first <expr> is not bracketed. *)
and parse_write_items st =
  let items = ref [ parse_expr st ] in
  let continue = ref true in
  while !continue do
    if accept_punct st "," || accept_punct st ";" then items := parse_expr st :: !items
    else continue := false
  done;
  List.rev !items

(* PRINT and LPRINT share this tail. USING is not required to lead: a listing
   may write `PRINT TAB(n);USING fmt;X`. *)
and parse_print st dest =
  let using = ref None in
  let items = ref [] in
  let continue = ref true in
  while !continue do
    match peek_kind st with
    | None -> continue := false
    | Some (Token.Punct ":") -> continue := false
    | Some (Token.Keyword "ELSE") -> continue := false
    | Some (Token.Punct ",") ->
        advance st;
        items := Ast.PComma :: !items
    | Some (Token.Punct ";") ->
        advance st;
        items := Ast.PSemi :: !items
    | Some (Token.Keyword "TAB") ->
        advance st;
        expect_punct st "(";
        let e = parse_expr st in
        expect_punct st ")";
        items := Ast.PTab e :: !items
    (* SPC only ever appears in a PRINT/LPRINT list -- the manual is explicit
       that it cannot be used as a string expression (spec/spec.md
       PRINT.SPC) -- so it is read here rather than through [intrinsics],
       where it would parse anywhere a string could. *)
    | Some (Token.Keyword "SPC") ->
        advance st;
        expect_punct st "(";
        let e = parse_expr st in
        expect_punct st ")";
        items := Ast.PSpc e :: !items
    | Some (Token.Keyword "USING") ->
        (match !using with
        | Some _ -> failwith "Only one USING clause is allowed"
        | None -> ());
        advance st;
        using := Some (parse_expr st);
        (* The semicolon separating the format from its values is punctuation,
           not a print item. *)
        ignore (accept_punct st ";")
    (* A keyword that cannot begin an expression ends the list rather than
       being parsed as one: "PRINT A PRINT B" and "PRINT A ' note" are both
       a missing separator, and saying so is the outer statement parser's
       job.

       UNLESS it is followed by "(", which no statement keyword ever is at
       this position: "PRINT RESUME(1)" is a listing trying to use a reserved
       word as an array, and the message naming the word is the useful one
       there. Both readings are wanted, so both are kept. *)
    | Some (Token.Keyword k)
      when (not (keyword_starts_expression k)) && peek2_kind st <> Some (Token.Punct "(") ->
        continue := false
    | Some _ -> items := Ast.PExpr (parse_expr st) :: !items
  done;
  Ast.Print (dest, !using, List.rev !items)

and parse_statement_list st =
  let stmts = ref [] in
  (* NEXT's comma form closes several loops in one statement, and it is in the
     manual's own syntax box -- NEXT [<var>][,<var>] -- not only in its
     "NEXT K, J" example (ref-9801 printed p.74 / PDF p.85). It is expanded
     here into one [Next] per variable, which is what "NEXT K : NEXT J" means.
     That is deliberately not the same as one node naming both: a FOR whose
     bound fails on entry skips to just past the NEXT closing its own loop,
     and the NEXT closing the enclosing loop must still be left to run. Only a
     NEXT that named a variable may continue, since the box brackets the first
     <var> together with the commas that follow it. *)
  let push_statement () =
    let start = here st in
    let node = parse_statement_node st in
    stmts := stmt_at (span_over start st.last) node :: !stmts;
    match node with
    | Ast.Next (Some _) ->
        while accept_punct st "," do
          let start = here st in
          match peek_kind st with
          | Some (Token.Ident v) ->
              advance st;
              check_valid_name v;
              stmts := stmt_at (span_over start st.last) (Ast.Next (Some v)) :: !stmts
          | Some (Token.Keyword k) -> reserved_word_error k
          | _ -> failwith "Expected a loop variable after \",\" in NEXT"
        done
    | _ -> ()
  in
  push_statement ();
  (* ref-9801 printed p.30, section 13 rule (7): where a statement follows a
     label on one line, they are separated "by a colon (:) OR BY A SPACE".
     Spaces are not tokens, so "20 *L PRINT X" arrives here as a LabelDef
     followed directly by the next statement with nothing between them.
     Only a label may be followed that way; everywhere else a colon is still
     required, which is why this tests the statement just pushed rather than
     relaxing the separator generally. *)
  let label_just_pushed () =
    match !stmts with Ast.{ snode = Ast.LabelDef _; _ } :: _ -> true | _ -> false
  in
  let go = ref true in
  while !go do
    if accept_punct st ":" then (if at_end st then go := false else push_statement ())
    else if label_just_pushed () && not (at_end st) then push_statement ()
    else go := false
  done;
  List.rev !stmts

(* Every [failwith] in this file is raised somewhere down a recursive-descent
   call chain that has no span in scope to attach to it. Rather than thread a
   span parameter through every one of those sites, this single handler at
   the top of the only entry point catches the [Failure] and attaches the
   span of whatever the parser was looking at when it gave up: the token it
   choked on, or — if it ran off the end of the line — the last token it
   managed to consume. *)
let parse_statements (toks : Token.t list) : Ast.stmt list =
  match toks with
  | [] -> []
  | first :: _ ->
      let st = { toks; last = first.Token.span } in
      (try
         let stmts = parse_statement_list st in
         (* A label may only open its line. The manual writes every definition
            that way -- "60 *PLUS : PRINT \"plus\"" (printed p.29 / PDF p.42) --
            and names no other position. Refusing the rest is ours, and it is
            the safe direction: the line table records a label against the line
            that opens with it, so a definition anywhere else would look
            defined to a reader and be unreachable to a jump. Nested branches
            are walked too, since "IF X THEN PRINT 1 : *HERE" hides one a
            top-level scan would miss. *)
         let rec check_labels ~(top : bool) (ss : Ast.stmt list) =
           List.iteri
             (fun i (s : Ast.stmt) ->
               (match s.Ast.snode with
               | Ast.LabelDef name when not (top && i = 0) ->
                   Error.raise_at ~span:s.Ast.sspan 0
                     (Printf.sprintf
                        "*%s must be the first statement on its line to define a label" name)
               | Ast.If (_, t, e) ->
                   check_labels ~top:false t;
                   check_labels ~top:false e
               | _ -> ()))
             ss
         in
         check_labels ~top:true stmts;
         if at_end st then stmts
         else
           (* Without this, a line the parser only half-understands is
              silently truncated to the part it did understand. *)
           failwith "Unexpected token after statement"
       with Failure msg ->
         let span =
           match st.toks with t :: _ -> t.Token.span | [] -> st.last
         in
         Error.raise_at ~span 0 msg)
