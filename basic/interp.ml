(* The evaluator: a program counter walking the line table one statement at a
   time. There is no call into the parser from here — a program is parsed in
   full before a single statement runs, so a listing with a broken line is
   refused rather than half-executed.

   Two counters rather than one: [pc] indexes [prog.lines] and [si] indexes
   that line's statement list, because this dialect puts several statements on
   a line and a GOTO targets a line, never a statement within one. *)

(* An open FOR loop: enough to test the bound and to jump back to the first
   statement of the body without re-running the FOR itself. *)
type for_frame = {
  var : string;
  limit : float;
  step : float;
  body_pc : int; (* line index of the statement after FOR *)
  body_si : int;
}

type state = {
  prog : Program.t;
  env : Env.t;
  w : Print_format.writer; (* PRINT — the screen *)
  lw : Print_format.writer;
      (* LPRINT — the printer. A separate writer, so the printer counts its
         print zones from its own column: a half-finished PRINT line on screen
         must not shift what lands on paper. *)
  input : unit -> string option;
  on_draw : Display.op -> unit;
      (* Where the screen and graphics statements go. They are recorded rather
         than rendered, and the interpreter does not keep the record: a caller
         that wants the whole display list accumulates it here. *)
  on_in_window : Display.point -> bool;
      (* Whether a graphics point lands inside the window. PAINT's entry makes
         a start point outside it an Illegal function call (ref-9801 printed
         p.117 / PDF p.128), and that is a run-time error at the statement, so
         it cannot be left to raster/, which runs afterwards over a finished
         display list and has no statement to blame.

         It takes a [Display.point], not a resolved pair, so that a STEP start
         can be answered too: resolving one needs the last point referenced,
         which basic/ deliberately does not track. This hands over exactly the
         value that would go into the display list and lets the caller resolve
         it, so basic/ still never learns what a pixel is.

         The default answers "inside" rather than "outside" -- the opposite of
         [on_point] below, and deliberately. A caller with no rasteriser cannot
         know, and [on_point]'s pessimistic default is safe only because it
         reports a colour nobody drew; the same choice here would make every
         PAINT raise for callers that draw nothing at all. *)
  on_point : float -> float -> int;
      (* POINT(x,y): the one place this interpreter reads state back rather
         than only ever appending to it. basic/ still touches no pixel — it
         hands the caller a screen coordinate and gets back a palette number,
         exactly the shape of [input] above, and never sees a Framebuffer or
         a Palette. Answering correctly is the caller's problem: it means
         resolving the display list recorded so far, which is raster/'s job,
         so the default here (used by any caller that has no rasteriser, e.g.
         a test not exercising graphics) reports every point as unlit rather
         than pretending to know. *)
  on_lp : unit -> float * float;
      (* [1] POINT(<function>): the LP (last referenced point), for the same
         reason and by the same route as [on_point] -- basic/ does not track
         the LP, raster/ does, because six operations move it and a second
         copy here would be free to drift. The default (0,0) matches
         raster/'s own starting LP, so a caller with no rasteriser gets the
         same answer a rasteriser would give before anything has drawn. *)
  mutable data_lines : int array;
      (* The BASIC line each gathered datum was declared on, parallel to the
         values in [Env]. RESTORE <line> searches it for the first datum at or
         after that line. *)
  mutable pc : int; (* index into prog.lines — NOT a BASIC line number *)
  mutable si : int; (* index into the current line's statement list *)
  mutable jumped : bool; (* set by any statement that rewrites pc/si *)
  mutable halted : bool;
  mutable fors : for_frame list; (* open FOR loops, innermost first *)
  mutable gosub : (int * int) list; (* return (pc, si) stack, innermost first *)
  mutable whiles : (int * int) list;
      (* open WHILE loops, innermost first: each entry is the (pc, si) of the
         WHILE statement itself, not of its body's first statement -- WEND
         jumps back there to re-evaluate the condition, unlike a FOR frame,
         which remembers the body's start because NEXT re-tests the bound
         itself rather than re-running FOR (spec/spec.md CTRL.WHILE,
         CTRL.WEND). *)
  mutable rnd : Random.State.t;
      (* RND's one pseudo-random sequence (spec/spec.md NUM.RND). Seeded from
         [default_rnd_seed] at the start of every run, and reseeded whenever
         the program calls RND with a negative argument, so a program's
         output is exactly reproducible from run to run and under test —
         never drawn from the process-wide [Random] state. *)
  mutable rnd_last : float; (* what RND(0) repeats; 0.0 before any draw *)
  (* Error handling (spec/spec.md ERR.ON-ERROR-GOTO, ERR.RESUME, ERR.ERROR,
     ERR.FN, ERR.ERL; ref-9801 printed p.71,109,136 / PDF p.82,120,147).
     [handler] is ON ERROR GOTO's installed target, or [None] before any
     ON ERROR GOTO has run or after "ON ERROR GOTO 0" -- the manual's own
     way to disable trapping. [in_handler] is true for exactly the
     statements the handler routine itself runs: the manual states plainly
     that no *further* error interrupts a handler already running -- an
     error there always shows its own message and stops, never nests. *)
  mutable handler : Ast.line_ref option;
  mutable in_handler : bool;
  mutable err_number : int; (* ERR: 0 before any error is ever trapped *)
  mutable erl_line : int; (* ERL: 0 before any error is ever trapped *)
  (* Where the statement that raised the error being handled sits, so RESUME
     (retry it) and RESUME NEXT (continue after it) know where "it" is. Only
     ever read while [in_handler] is true. *)
  mutable failing_pc : int;
  mutable failing_si : int;
  (* The error that put us into the handler now running, kept so
     "ON ERROR GOTO 0" executed *inside* that handler can show that error's
     own message and stop -- what the manual says that specific case does,
     distinct from disabling the handler outside of one. *)
  mutable trapped_error : Error.t option;
}

(* An interpreter-chosen constant, not a value the manual states: it exists
   only so that a fresh run's RND sequence is fixed rather than seeded from
   the wall clock, which the manual itself requires (RND repeats the same
   series across RUN and CLEAR unless RANDOMIZE changes it) and which a test
   suite requires even more directly. *)
let default_rnd_seed = 1

let rnd_next (st : state) : float =
  let v = Random.State.float st.rnd 1.0 in
  st.rnd_last <- v;
  v

(* Reseeds RND's one sequence and nothing else -- the shared machinery
   behind both RND(n) for n < 0 and RANDOMIZE (spec/spec.md NUM.RND,
   NUM.RANDOMIZE), so neither introduces a second source of randomness.
   [rnd] is the only mutable random state on [st]; this never touches
   [rnd_last], since reseeding alone draws nothing to repeat. *)
let rnd_seed_state (st : state) (seed : float) : unit =
  st.rnd <- Random.State.make [| int_of_float (Float.round seed) |]

let rnd_seed (st : state) (seed : float) : float =
  rnd_seed_state st seed;
  rnd_next st

(* The BASIC line number now executing, for error messages. Zero once the
   counter has walked off the end, which [Error.to_string] renders as "no line
   number known" rather than as a line 0. *)
let current_line (st : state) : int =
  if st.pc < Array.length st.prog.Program.lines then
    st.prog.Program.lines.(st.pc).Program.number
  else 0

let fail (st : state) ?span (message : string) : 'a =
  Error.raise_at ?span (current_line st) message

(* Like [fail], but for the one raise site that already knows its own
   N88-BASIC(86) error number without having to recover it from [message] --
   the ERROR statement, which is *given* a number by the program
   (spec/spec.md ERR.ERROR). *)
let fail_code (st : state) ?span (code : int) (message : string) : 'a =
  Error.raise_at ?span ~code (current_line st) message

(* [Env] raises with neither a BASIC line number nor a span — it is handed bare
   names and subscripts and knows nothing about the program they came from.
   This refills both from the node being evaluated, so a subscript error
   underlines the reference that made it. Only a bare error is rewritten; one
   that already carries a position was raised by something that knew better. *)
let locate (st : state) (span : Span.t) (f : unit -> 'a) : 'a =
  try f ()
  with Error.Basic_error e when e.Error.line = 0 && e.Error.span = None ->
    Error.raise_at ~span ?code:e.Error.code (current_line st) e.Error.message

(* A relational or logical operator's result is always Integer (spec/spec.md
   NUM.COERCION; ref-9801 printed p.18 / PDF p.31, rule 3: a logical
   operation converts its operands to integer and yields an integer result)
   -- -1 and 0 are both exactly representable there, so this never overflows
   or rounds. *)
let truth (b : bool) : Value.t = Value.Num (Numtype.Int, if b then -1.0 else 0.0)

(* A [Value.Num] tag for a float about to be handed to [Env.set_scalar] or
   [Env.set_element], both of which always re-derive the tag they actually
   store from the *target* variable's own declared kind (basic/env.ml's
   [coerce_to]) and discard whatever tag arrives here. [Double] is used only
   because [Value.make Double] itself never overflows or rounds -- the
   target's own coercion is what will, once its kind is known. *)
let pending (x : float) : Value.t = Value.Num (Numtype.Double, x)

let as_num (st : state) (span : Span.t) (v : Value.t) : float =
  match v with Value.Num (_, n) -> n | Value.Str _ -> fail st ~span "Type mismatch"

(* Like [as_num], but keeps the value's BASIC numeric type -- needed
   wherever that type feeds into the result (arithmetic coercion, unary
   negation, a function's own result type). *)
let as_typed (st : state) (span : Span.t) (v : Value.t) : Numtype.t * float =
  match v with Value.Num (t, n) -> (t, n) | Value.Str _ -> fail st ~span "Type mismatch"

let as_str (st : state) (span : Span.t) (v : Value.t) : string =
  match v with Value.Str s -> s | Value.Num _ -> fail st ~span "Type mismatch"

let is_digit (c : char) : bool = c >= '0' && c <= '9'

let hex_digit (c : char) : int option =
  if is_digit c then Some (Char.code c - Char.code '0')
  else
    let lower = Char.lowercase_ascii c in
    if lower >= 'a' && lower <= 'f' then Some (Char.code lower - Char.code 'a' + 10)
    else None

(* VAL: the numeral at the start of a string, or zero when there is none --
   text after the number is ignored rather than rejected (ref-9801 printed
   p.154 / PDF p.165).

   The page states more than a decimal reader: every integer notation
   (octal, decimal, hexadecimal) and every real notation (decimal point,
   exponent) may be given, and "spaces within the string are ignored" --
   anywhere in it, not merely at its ends, so VAL("1 2") is twelve. Spaces
   are therefore stripped from the whole string before anything is scanned,
   which is also what makes a space between a sign and its digits harmless.

   Scanning stops at the first character that is not a digit of the base in
   hand, and the page is explicit about what counts: A-F are digits under
   &H, while 8 and 9 are not digits under octal, so VAL("&O19") is one.

   The two scanners the lexer already uses do the work, so VAL reads a
   numeral by exactly the rule that reads one in program text -- one
   definition of "what a numeral looks like", not a second that can drift
   from it. *)
let val_of_string (text : string) : float =
  let s = String.concat "" (String.split_on_char ' ' text) in
  let s = String.concat "" (String.split_on_char '\t' s) in
  let len = String.length s in
  let sign, start =
    if len > 0 && s.[0] = '-' then (-1.0, 1)
    else if len > 0 && s.[0] = '+' then (1.0, 1)
    else (1.0, 0)
  in
  if start >= len then 0.0
  else if s.[start] = '&' then
    (* [Lexer.scan_radix] answers None when no digit of the base follows,
       which is the manual's "value is 0" case for a lone "&". *)
    match Lexer.scan_radix s start with
    | Some (_, _, v) -> sign *. v
    | None -> 0.0
  else if is_digit s.[start] || s.[start] = '.' then
    let _, _, magnitude = Lexer.scan_number s start in
    sign *. magnitude
  else 0.0

(* HEX$/OCT$ read their argument as a 16-bit machine word: -32768..-1 and
   32768..65535 both name the same bit patterns (two's complement), which is
   why both ranges are accepted and rendered identically (spec/spec.md
   STR.HEX, STR.OCT). *)
let to_word (st : state) (span : Span.t) (n : float) : int =
  let i = int_of_float (Float.round n) in
  if i < -32768 || i > 65535 then fail st ~span "Illegal function call"
  else if i < 0 then i + 65536
  else i

(* INSTR's search, 1-based throughout: [start] is the first character
   position tried, and a match's position in the result is likewise 1-based.
   An empty needle is not searched for — it "matches" at [start] itself,
   whatever that position is, per the manual (spec/spec.md STR.INSTR). *)
let instr_of (_st : state) (_span : Span.t) (hay : string) (needle : string)
    (start : int) : int =
  if needle = "" then start
  else
    let hay_len = String.length hay and needle_len = String.length needle in
    let rec go i =
      if i + needle_len > hay_len then 0
      else if String.sub hay i needle_len = needle then i + 1
      else go (i + 1)
    in
    if start < 1 then 0 else go (start - 1)

(* [locate]d as a whole: any Overflow or other line-less error raised while
   evaluating this expression -- a literal out of its own type's range, an
   arithmetic result too big for its widened type, a user function's
   argument too big for its parameter's declared type -- picks up this
   expression's span and the current BASIC line here, the one place low
   enough in the call stack to still have both in scope for every case
   below, numeric or not. An error raised evaluating a *sub*-expression is
   caught by that sub-expression's own (nested) call to [eval] first, so it
   already carries a span by the time it reaches here, and [locate]'s own
   guard leaves it untouched. *)
let rec eval (st : state) (e : Ast.expr) : Value.t =
  locate st e.Ast.espan (fun () ->
      match e.Ast.enode with
      | Ast.Num (t, n) -> Value.make t n
      | Ast.Str s -> Value.Str s
      | Ast.Var name -> Env.get_scalar st.env name
      | Ast.Index (name, args) -> Env.get_element st.env name (rounded_ints st args)
      | Ast.Call (name, args) -> eval_call st e.Ast.espan name args
      | Ast.Unary ("-", operand) ->
          let t, x = as_typed st operand.Ast.espan (eval st operand) in
          Value.make t (-.x)
      (* NOT is the bitwise complement, not a boolean negation
         (ref-9801 printed p.22): NOT 5 is -6, because 5's bits inverted in
         16-bit two's complement are -6. It agrees with the boolean reading
         on the -1/0 a comparison yields — NOT 0 is -1 and NOT -1 is 0 —
         which is why every conditional kept working while NOT 5 returned 0. *)
      | Ast.Unary ("NOT", operand) ->
          let i = int_of_float (Value.coerce Numtype.Int (eval_num st operand)) in
          Value.make Numtype.Int (float_of_int (lnot i))
      | Ast.Unary (op, _) ->
          fail st ~span:e.Ast.espan (Printf.sprintf "Unknown operator %s" op)
      | Ast.Binop (op, l, r) -> eval_binop st e.Ast.espan op l r)

and eval_num (st : state) (e : Ast.expr) : float = as_num st e.Ast.espan (eval st e)
and eval_str (st : state) (e : Ast.expr) : string = as_str st e.Ast.espan (eval st e)

(* The whole-number arguments of this dialect — subscripts, screen coordinates,
   colours — are rounded rather than truncated: A(N/2) with N odd names a cell,
   and floor would silently pick the one below. *)
and rounded_ints (st : state) (args : Ast.expr list) : int list =
  List.map (fun e -> int_of_float (Float.round (eval_num st e))) args

and eval_binop (st : state) (span : Span.t) (op : string) (l : Ast.expr)
    (r : Ast.expr) : Value.t =
  let lv = eval st l and rv = eval st r in
  match (op, lv, rv) with
  | "+", Value.Str a, Value.Str b -> Value.Str (a ^ b)
  | "=", Value.Str a, Value.Str b -> truth (a = b)
  | "<>", Value.Str a, Value.Str b -> truth (a <> b)
  (* Every other operator, and every mixed pair, is a type error: this dialect
     orders numbers only. *)
  | _, Value.Str _, _ | _, _, Value.Str _ -> fail st ~span "Type mismatch"
  | _ -> (
      let ta, a = as_typed st l.Ast.espan lv and tb, b = as_typed st r.Ast.espan rv in
      (* Mixed-precision arithmetic converts to the more precise operand's
         type before the operation runs (spec/spec.md NUM.COERCION;
         ref-9801 printed p.18 / PDF p.31, rule 2). *)
      let widened = Numtype.widen ta tb in
      match op with
      | "+" -> Value.make widened (a +. b)
      | "-" -> Value.make widened (a -. b)
      | "*" -> Value.make widened (a *. b)
      | "/" ->
          if b = 0.0 then fail st ~span "Division by zero"
          else
            (* "/" is real-number division even when both operands are
               integers (ref-9801 printed p.19 / PDF p.32: the operator
               table names "/" itself "実数の除算", real-number division,
               distinct from "\\", integer division, which this dialect does
               not implement) -- Integer never survives it, unlike "+", "-"
               and "*", which can. *)
            let t = if widened = Numtype.Int then Numtype.Single else widened in
            Value.make t (a /. b)
      (* Integer never survives ^, for the same reason it never survives /:
         an integer base and an integer exponent routinely give a fractional
         result, and 2^-1 is 0.5 rather than a number an Integer could hold.
         Coercing the result to Integer rounded that to 1 -- and 2^-2 to 0,
         3^-1 to 0, 10^-3 to 0 -- a whole class of silently wrong answers,
         not one input.

         The manual does not state ^'s result type in the type-conversion
         rules (printed p.18), but its own worked example settles it: p.20
         prints 0^-1 as 1.70141E+38, a single-precision value, from two
         integer operands. An integer result could not display that way. *)
      | "^" ->
          let t = if widened = Numtype.Int then Numtype.Single else widened in
          Value.make t (Float.pow a b)
      | "=" -> truth (a = b)
      | "<>" -> truth (a <> b)
      | "<" -> truth (a < b)
      | ">" -> truth (a > b)
      | "<=" -> truth (a <= b)
      | ">=" -> truth (a >= b)
      (* AND and OR are BITWISE, not boolean (ref-9801 printed p.22 / PDF
         p.35). The page gives per-bit truth tables and closes by using AND
         to mask all but the wanted bits of a device port's status byte —
         a use only possible per bit. So 12 AND 10 is 8, not "both are
         non-zero, so true".

         The boolean reading happens to agree wherever the operands are the
         -1/0 a comparison produces, which is most conditions in most
         programs, and that is why it survived: IF A>0 AND B>0 gives the
         same answer either way. It differs the moment a program masks bits,
         which era listings do constantly.

         Operands convert to integer first, which rounds and range-checks
         them to 16 bits (Value.coerce); within that range OCaml's own land
         and lor already give the two's-complement answer, so no masking is
         needed here. *)
      | "AND" | "OR" | "XOR" | "IMP" | "EQV" ->
          let ia = int_of_float (Value.coerce Numtype.Int a) in
          let ib = int_of_float (Value.coerce Numtype.Int b) in
          (* IMP is (NOT X) OR Y and EQV is NOT (X XOR Y): each reproduces
             its truth table on printed p.22 and its worked example on p.23
             -- 28 IMP 9 is -21, 17 EQV 12 is -30. Written with lnot rather
             than a mask because the operands are already the signed
             integers Value.coerce produced, and OCaml's lnot on those is
             the two's-complement answer the manual's binary columns show. *)
          let r =
            match op with
            | "AND" -> ia land ib
            | "OR" -> ia lor ib
            | "XOR" -> ia lxor ib
            | "IMP" -> lnot ia lor ib
            | _ -> lnot (ia lxor ib)
          in
          Value.make Numtype.Int (float_of_int r)
      (* MOD is the integer remainder, and it is NOT one of the logical
         operators: printed p.21's conversion rule speaks of 論理演算子, and
         MOD sits at level 7 among the arithmetic rows rather than with AND
         and OR at 11 and 12 (printed p.25). So the manual states nothing
         about how MOD reduces its operands to integers, nor the sign of a
         negative remainder. Rounding them the way every other whole-number
         argument in this interpreter is rounded, and taking the sign from
         the dividend as OCaml's own mod does, are decisions of ours
         (spec OP.MOD). A zero divisor is Division by zero, the same as / --
         which the manual does not state for MOD either. *)
      | "MOD" ->
          let ia = int_of_float (Float.round a) and ib = int_of_float (Float.round b) in
          if ib = 0 then fail st ~span "Division by zero"
          else Value.make Numtype.Int (float_of_int (ia mod ib))
      (* "\\", integer division -- ref-9801 printed p.20, which states both
         halves outright, unlike MOD above: real operands are ROUNDED before
         the operation, and the quotient is then TRUNCATED. Its own worked
         examples are 10\\3 -> 3 and 23.75\\5 -> 4, the second being 24/5 =
         4.8 truncated. So the rounding here is the manual's rule and not, as
         with MOD, ours.

         A zero divisor is Division by zero, which the page does not state for
         this operator any more than for MOD; that part is ours. *)
      | "\\" ->
          let ia = int_of_float (Float.round a) and ib = int_of_float (Float.round b) in
          if ib = 0 then fail st ~span "Division by zero"
          else
            Value.make Numtype.Int
              (Float.of_int (int_of_float (Float.trunc (float_of_int ia /. float_of_int ib))))
      | _ -> fail st ~span (Printf.sprintf "Unknown operator %s" op))

(* MID$ the function: the substring of [text] starting at the 1-based
   [start_e], [len_e] characters long (or every character to the end of
   [text] when [len_e] is omitted or reaches past it). A [start_e] beyond
   the end of [text] is not an error — it yields the null string
   (spec/spec.md STR.MID) — but [start_e] and any given [len_e] must still
   fall in 1-255 and 0-255 respectively, the range every sibling
   substring function shares. *)
and mid_of (st : state) (span : Span.t) (text : string) (start_e : Ast.expr)
    (len_e : Ast.expr option) : string =
  let start = int_of_float (Float.round (eval_num st start_e)) in
  if start < 1 || start > 255 then fail st ~span "Illegal function call";
  let text_len = String.length text in
  if start > text_len then ""
  else
    let avail = text_len - (start - 1) in
    let want =
      match len_e with
      | None -> avail
      | Some e ->
          let n = int_of_float (Float.round (eval_num st e)) in
          if n < 0 || n > 255 then fail st ~span "Illegal function call" else n
    in
    String.sub text (start - 1) (min want avail)

and eval_call (st : state) (span : Span.t) (name : string) (args : Ast.expr list)
    : Value.t =
  let one () =
    match args with
    | [ a ] -> eval_num st a
    | _ -> fail st ~span "Wrong number of arguments"
  in
  (* The single argument of a one-argument numeric function, with its type.
     Used by the transcendental functions below, whose result type follows
     their argument's (ref-9801 printed p.29 / PDF p.40, and again printed
     p.98 / PDF p.109: an elementary math function such as SIN, COS, TAN,
     ATN, LOG or EXP returns double precision when given a double-precision
     argument, and single precision otherwise -- even when the argument is
     an integer). SQR's own entry states the same rule in the same words
     (ref-9801 printed p.146 / PDF p.157), so applying it there is the
     manual's rule and not, as this comment once claimed, a decision of
     ours. ABS's entry (printed p.38 / PDF p.49) states it in those words
     too, which is why [single_unless_double] is named for the rule rather
     than for the transcendental functions that first needed it -- ABS is
     not transcendental and obeys it anyway. *)
  let one_typed () =
    match args with
    | [ a ] -> as_typed st a.Ast.espan (eval st a)
    | _ -> fail st ~span "Wrong number of arguments"
  in
  let single_unless_double (f : float -> float) : Value.t =
    let t, x = one_typed () in
    let result_t = if t = Numtype.Double then Numtype.Double else Numtype.Single in
    Value.make result_t (f x)
  in
  match name with
  (* ABS obeys the stated rule above, despite looking like it should keep
     its argument's type the way INT and FIX do: its own entry says single
     precision unless the argument carries a double, and that is observable
     rather than bookkeeping -- A%=-32768 : PRINT ABS(A%) is 32768 under the
     rule, and used to raise Overflow here when the result stayed an integer
     that cannot hold it (spec/clauses.json NUM.ABS, once divergent). *)
  | "ABS" -> single_unless_double Float.abs
  (* INT and FIX, by contrast, keep the argument's own type: their result is
     exactly representable in it (FIX never introduces a fraction that was
     not already there; INT only ever removes one). The manual states no
     result type for either, so unlike ABS that is a decision of ours. *)
  | "INT" ->
      let t, x = one_typed () in
      Value.make t (Float.floor x)
  | "SQR" ->
      let t, x = one_typed () in
      if x < 0.0 then fail st ~span "Illegal function call"
      else Value.make (if t = Numtype.Double then Numtype.Double else Numtype.Single) (sqrt x)
  (* SGN's result is always exactly -1, 0 or 1 regardless of its argument's
     type -- an inherently whole-number answer, so it is always Integer
     rather than following the argument's type the way ABS/INT/FIX do. The
     manual does not state this outright either; it is a decision of ours. *)
  | "SGN" ->
      let x = one () in
      Value.make Numtype.Int (if x > 0.0 then 1.0 else if x < 0.0 then -1.0 else 0.0)
  | "SIN" -> single_unless_double sin
  | "COS" -> single_unless_double cos
  | "TAN" -> single_unless_double tan
  | "ATN" -> single_unless_double atan
  | "EXP" -> single_unless_double exp
  | "LOG" ->
      let t, x = one_typed () in
      if x <= 0.0 then fail st ~span "Illegal function call"
      else Value.make (if t = Numtype.Double then Numtype.Double else Numtype.Single) (log x)
  (* FIX truncates toward zero; INT (above) floors toward negative infinity.
     They agree for every non-negative argument and for every whole number,
     and differ by exactly one for a negative argument with a fractional
     part: FIX(-2.7) is -2, INT(-2.7) is -3 (spec/spec.md NUM.FIX). *)
  | "FIX" ->
      let t, x = one_typed () in
      Value.make t (Float.trunc x)
  (* CINT/CDBL/CSNG go through the same [Value.make]/[Value.coerce] every
     other numeric construction does, so their rounding and Overflow bound
     are exactly [Value.coerce]'s for that target type -- no separate copy
     of the rule to keep in sync (spec/spec.md NUM.CINT, NUM.CDBL,
     NUM.CSNG). *)
  | "CINT" -> Value.make Numtype.Int (one ())
  | "CDBL" -> Value.make Numtype.Double (one ())
  | "CSNG" -> Value.make Numtype.Single (one ())
  | "SPACE$" -> (
      match args with
      | [ e ] ->
          let n = int_of_float (Float.round (eval_num st e)) in
          if n < 0 || n > 255 then fail st ~span "Illegal function call"
          else Value.Str (String.make n ' ')
      | _ -> fail st ~span "Wrong number of arguments")
  (* POS's argument is a required dummy -- the manual is explicit it cannot
     be omitted, but any value has the same effect (spec/spec.md
     PRINT.POS) -- so it is evaluated (for its side effects and to enforce
     arity) and then ignored. *)
  | "POS" -> (
      match args with
      | [ _dummy ] -> Value.make Numtype.Int (float_of_int (Print_format.column st.w))
      | _ -> fail st ~span "Wrong number of arguments")
  | "CSRLIN" -> (
      match args with
      | [] -> Value.make Numtype.Int (float_of_int (Print_format.row st.w))
      | _ -> fail st ~span "Wrong number of arguments")
  (* ERR and ERL hold the error code and BASIC line number of the most
     recently trapped error (spec/spec.md ERR.FN, ERR.ERL). Both are 0
     before any error is ever trapped -- the manual does not state this
     starting value outright, but nothing else is coherent: it is not one of
     the 52 error numbers or a line a program's own numbering can collide
     with. Neither is reset when the handler that reads them returns via
     RESUME; the manual describes only what sets them, never anything that
     clears them, so they keep answering the *last* trapped error's numbers
     until another error is trapped. *)
  | "ERR" -> (
      match args with
      | [] -> Value.make Numtype.Int (float_of_int st.err_number)
      | _ -> fail st ~span "Wrong number of arguments")
  | "ERL" -> (
      match args with
      | [] -> Value.make Numtype.Int (float_of_int st.erl_line)
      | _ -> fail st ~span "Wrong number of arguments")
  (* RND's result is always single precision (ref-9801 printed p.137 / PDF
     p.148 shows it used directly as a single-precision value; the manual
     does not say this outright for RND itself, so this is a decision of
     ours, matching the default type of an unsuffixed value described at
     printed p.14 / PDF p.27). *)
  | "RND" -> (
      match args with
      | [] -> Value.make Numtype.Single (rnd_next st)
      | [ e ] ->
          let x = eval_num st e in
          if x < 0.0 then Value.make Numtype.Single (rnd_seed st x)
          else if x = 0.0 then Value.make Numtype.Single st.rnd_last
          else Value.make Numtype.Single (rnd_next st)
      | _ -> fail st ~span "Wrong number of arguments")
  | "LEFT$" -> (
      match args with
      | [ text; count ] ->
          let text = eval_str st text in
          let n = int_of_float (Float.round (eval_num st count)) in
          if n < 0 || n > 255 then fail st ~span "Illegal function call"
          else Value.Str (String.sub text 0 (min n (String.length text)))
      | _ -> fail st ~span "Wrong number of arguments")
  | "RIGHT$" -> (
      match args with
      | [ text; count ] ->
          let text = eval_str st text in
          let n = int_of_float (Float.round (eval_num st count)) in
          if n < 0 || n > 255 then fail st ~span "Illegal function call"
          else
            let len = String.length text in
            let take = min n len in
            Value.Str (String.sub text (len - take) take)
      | _ -> fail st ~span "Wrong number of arguments")
  | "MID$" -> (
      match args with
      | [ text; start ] -> Value.Str (mid_of st span (eval_str st text) start None)
      | [ text; start; len ] ->
          Value.Str (mid_of st span (eval_str st text) start (Some len))
      | _ -> fail st ~span "Wrong number of arguments")
  | "LEN" -> (
      match args with
      | [ text ] -> Value.make Numtype.Int (float_of_int (String.length (eval_str st text)))
      | _ -> fail st ~span "Wrong number of arguments")
  | "ASC" -> (
      match args with
      | [ text ] -> (
          match eval_str st text with
          | "" -> fail st ~span "Illegal function call"
          | s -> Value.make Numtype.Int (float_of_int (Char.code s.[0])))
      | _ -> fail st ~span "Wrong number of arguments")
  | "INSTR" -> (
      match args with
      | [ hay; needle ] ->
          Value.make Numtype.Int
            (float_of_int (instr_of st span (eval_str st hay) (eval_str st needle) 1))
      | [ pos; hay; needle ] ->
          let start = int_of_float (Float.round (eval_num st pos)) in
          if start < 1 then fail st ~span "Illegal function call";
          Value.make Numtype.Int
            (float_of_int (instr_of st span (eval_str st hay) (eval_str st needle) start))
      | _ -> fail st ~span "Wrong number of arguments")
  | "STR$" -> (
      match args with
      | [ e ] ->
          (* [Print_format.format_number] carries the leading sign character
             STR$ wants (space for non-negative, "-" for negative) plus the
             trailing space PRINT adds for its own column spacing, which
             STR$ does not — the last character is dropped to remove it. *)
          let t, x = as_typed st e.Ast.espan (eval st e) in
          let formatted = Print_format.format_number t x in
          Value.Str (String.sub formatted 0 (String.length formatted - 1))
      | _ -> fail st ~span "Wrong number of arguments")
  | "STRING$" -> (
      match args with
      | [ count; ch ] ->
          let n = int_of_float (Float.round (eval_num st count)) in
          if n < 0 || n > 255 then fail st ~span "Illegal function call";
          let c =
            match eval st ch with
            | Value.Str "" -> fail st ~span "Illegal function call"
            | Value.Str s -> s.[0]
            | Value.Num (_, code) ->
                let i = int_of_float (Float.round code) in
                if i < 0 || i > 255 then fail st ~span "Illegal function call"
                else Char.chr i
          in
          Value.Str (String.make n c)
      | _ -> fail st ~span "Wrong number of arguments")
  | "HEX$" -> (
      match args with
      | [ e ] -> Value.Str (Printf.sprintf "%X" (to_word st span (eval_num st e)))
      | _ -> fail st ~span "Wrong number of arguments")
  | "OCT$" -> (
      match args with
      | [ e ] -> Value.Str (Printf.sprintf "%o" (to_word st span (eval_num st e)))
      | _ -> fail st ~span "Wrong number of arguments")
  | "CHR$" ->
      let code = int_of_float (Float.round (one ())) in
      if code < 0 || code > 255 then fail st ~span "Illegal function call"
      else Value.Str (String.make 1 (Char.chr code))
  (* VAL's result is always single precision -- the manual does not state
     VAL's result type, and [val_of_string] does not track the digit count
     or suffix a numeric-literal classification would need, so this is a
     decision of ours rather than an attempt to reproduce that
     classification (matching the default type of an unsuffixed value,
     printed p.14 / PDF p.27). *)
  | "VAL" -> (
      match args with
      | [ text ] -> Value.make Numtype.Single (val_of_string (eval_str st text))
      | _ -> fail st ~span "Wrong number of arguments")
  (* POINT names two different functions, told apart by arity.

     [2] POINT(Sx,Sy) — printed p.123 — is the palette number of the dot at
     screen coordinates (Sx,Sy), or -1 outside the viewport; see [on_point].

     [1] POINT(<function>) — printed p.122 — reads the LP back, with the
     function code choosing which coordinate and in which system:
       0 = LP's X in world coordinates    2 = LP's X in screen coordinates
       1 = LP's Y in world coordinates    3 = LP's Y in screen coordinates
     Codes 0/1 and 2/3 return the same numbers here, and that is the
     MANUAL'S rule rather than a shortcut: printed p.161 states that until
     WINDOW has been executed the window stays in its initial state and
     "(world coordinate) = (screen coordinate)". WINDOW is deferred
     (spec.md §3.2), so that condition holds for every program this
     interpreter can run. If WINDOW is ever built, these two pairs must
     part company — see GFX.POINT.

     A code outside 0-3 is refused with Illegal function call. That is
     ours: the page gives the four codes and does not say what a fifth
     would do, and it matches the refusals SCREEN, WIDTH and KEY already
     make. *)
  | "POINT" -> (
      match args with
      | [ code ] ->
          let n = int_of_float (Float.round (eval_num st code)) in
          if n < 0 || n > 3 then fail st ~span "Illegal function call";
          let x, y = st.on_lp () in
          Value.make Numtype.Single (if n = 0 || n = 2 then x else y)
      | [ x; y ] ->
          Value.make Numtype.Int (float_of_int (st.on_point (eval_num st x) (eval_num st y)))
      | _ -> fail st ~span "Wrong number of arguments")
  (* Anything else is a user-defined FN, which exists only once its DEF has
     been executed. *)
  | _ -> (
      match Env.find_fn st.env name with
      | None -> fail st ~span (Printf.sprintf "Undefined function %s" name)
      | Some (params, body) ->
          if List.length params <> List.length args then
            fail st ~span "Wrong number of arguments";
          (* Every argument is evaluated before any parameter is bound, so
             FNA(1,P) passes the caller's P rather than the one this very call
             has just rebound. The parameters shadow globals of the same name
             for the duration of the call and are put back afterwards. *)
          let values = List.map (eval st) args in
          let saved = List.map (fun p -> (p, Env.get_scalar st.env p)) params in
          List.iter2 (Env.set_scalar st.env) params values;
          let result = eval st body in
          List.iter (fun (p, v) -> Env.set_scalar st.env p v) saved;
          result)

(* The name an assignment target carries its type in: A and A(1) are both
   numeric, A$ and A$(1) both strings. *)
let lvalue_name (target : Ast.lvalue) : string =
  match target with Ast.LVar name -> name | Ast.LIndex (name, _) -> name

let assign (st : state) (span : Span.t) (target : Ast.lvalue) (v : Value.t) : unit =
  locate st span (fun () ->
      match target with
      | Ast.LVar name -> Env.set_scalar st.env name v
      | Ast.LIndex (name, args) -> Env.set_element st.env name (rounded_ints st args) v)

(* SWAP reads both operands' current values before writing either back, the
   same shape [assign] writes one -- used only by SWAP (spec/spec.md
   PROG.SWAP), which needs the "before" value of each side. *)
let get_lvalue (st : state) (span : Span.t) (target : Ast.lvalue) : Value.t =
  match target with
  | Ast.LVar name -> Env.get_scalar st.env name
  | Ast.LIndex (name, args) ->
      locate st span (fun () -> Env.get_element st.env name (rounded_ints st args))

let print_value (w : Print_format.writer) (v : Value.t) : unit =
  match v with
  | Value.Num (t, n) -> Print_format.put_unbroken w (Print_format.format_number t n)
  | Value.Str s -> Print_format.put w s

(* WRITE's own rendering of one value (spec/spec.md PRINT.WRITE): a string
   comes back quoted, a number comes back as the bare digits -- no leading
   sign column, no trailing space -- since [format_body] is exactly PRINT's
   number text before [format_number] adds that padding. *)
let write_value (v : Value.t) : string =
  match v with
  | Value.Num (t, n) -> Print_format.format_body t n
  | Value.Str s -> "\"" ^ s ^ "\""

(* TAB(n) pads to the 1-based column n, which is internal column n-1. A writer
   already at or past that column emits nothing: padding to a column behind the
   cursor would wrap onto the next line, and a listing lining a table up means
   "at least here", not "start again below". *)
let column_argument (st : state) (w : Print_format.writer) (e : Ast.expr) : int =
  let n = int_of_float (Float.round (eval_num st e)) in
  let width = Print_format.width w in
  if n < 0 then 0 else if n >= width && width > 0 then n mod width else n

let tab_to (st : state) (w : Print_format.writer) (e : Ast.expr) : unit =
  let target = column_argument st w e - 1 in
  let col = Print_format.column w in
  if col < target then Print_format.put w (String.make (target - col) ' ')

(* SPC(n): n literal spaces, n<0 treated as 0 (spec/spec.md PRINT.SPC). Unlike
   TAB, this never wraps via the current WIDTH -- this interpreter's writer
   does not track WIDTH, the same simplification [tab_to] above already
   makes for its own target column. *)
let spc_to (st : state) (w : Print_format.writer) (e : Ast.expr) : unit =
  let n = column_argument st w e in
  if n > 0 then Print_format.put w (String.make n ' ')

(* A print list ends with a newline unless its last item is a separator: a
   trailing `;` or `,` leaves the cursor where it is for the next PRINT. A
   trailing TAB is not a separator and still breaks the line. *)
let exec_print (st : state) (w : Print_format.writer) (items : Ast.print_item list)
    : unit =
  let rec go = function
    | [] -> Print_format.newline w
    | [ Ast.PSemi ] -> ()
    | [ Ast.PComma ] -> Print_format.tab_to_zone w
    | Ast.PSemi :: rest -> go rest
    | Ast.PComma :: rest ->
        Print_format.tab_to_zone w;
        go rest
    | Ast.PExpr e :: rest ->
        print_value w (eval st e);
        go rest
    | Ast.PTab e :: rest ->
        tab_to st w e;
        go rest
    | Ast.PSpc e :: rest ->
        spc_to st w e;
        go rest
  in
  go items

(* PRINT USING renders the whole item list as one formatted string, so its
   items are not printed one at a time.

   TAB is not filtered out on the way: the source confirms USING may follow a
   TAB(n); clause, and dropping it would lose the positioning while still
   printing plausible output. A leading TAB positions the writer before the
   formatted text is emitted; a TAB *after* a value has no position left to
   take effect at, so it is refused rather than ignored. *)
let exec_print_using (st : state) ~(span : Span.t) (w : Print_format.writer)
    (format : string) (items : Ast.print_item list) : unit =
  let values = ref [] in
  let seen_value = ref false in
  List.iter
    (fun item ->
      match item with
      | Ast.PTab n ->
          if !seen_value then fail st ~span "TAB after a value in a PRINT USING list";
          tab_to st w n
      | Ast.PSpc n -> spc_to st w n
      | Ast.PExpr e ->
          seen_value := true;
          values := eval st e :: !values
      | Ast.PComma | Ast.PSemi -> ())
    items;
  let text =
    (* [Print_using.format] rejects a string handed to a numeric field with
       [Invalid_argument], which is not a BASIC error and must not escape the
       interpreter's result type. It raises that for no other reason. *)
    try Print_using.format format (List.rev !values) with
    | Invalid_argument _ -> fail st ~span "Type mismatch"
    (* ref-9801 printed p.128 bars a string field from editing a string that
       contains Japanese. The page says only that the edit cannot be done and
       names no error, so the choice of Illegal function call is OURS -- the
       same one this interpreter already makes for an out-of-range SCREEN
       mode, WIDTH, KEY number or COLOR palette argument. Refusing is the
       page's rule; which error says so is not. *)
    | Print_using.Japanese_in_string_field -> fail st ~span "Illegal function call"
  in
  Print_format.put w text;
  (* A trailing ; suppresses the newline, as in free-format PRINT. *)
  match List.rev items with Ast.PSemi :: _ -> () | _ -> Print_format.newline w

(* The line index a reference names, or None if nothing defines it. A label is
   resolved through the table the loader built (ref-9801 printed p.29 / PDF
   p.42); an unresolved one is reported exactly as an unresolved line number
   is, because the manual gives labels as a substitute for a line number and
   names no error of their own. That reuse is ours. *)
let index_of_ref (st : state) (r : Ast.line_ref) : int option =
  match r.Ast.target with
  | Ast.LineNumber n -> Program.index_of_line st.prog n
  | Ast.LabelName name -> Program.index_of_label st.prog name

(* The BASIC line number a reference names -- what RESTORE needs, since it
   compares against the recorded line of each DATA item rather than jumping. *)
let line_number_of_ref (st : state) (r : Ast.line_ref) : int option =
  match r.Ast.target with
  | Ast.LineNumber n -> Some n
  | Ast.LabelName name -> (
      match Program.index_of_label st.prog name with
      | Some i -> Some st.prog.Program.lines.(i).Program.number
      | None -> None)

let jump_to_ref (st : state) (r : Ast.line_ref) : unit =
  match index_of_ref st r with
  | Some i ->
      st.pc <- i;
      st.si <- 0;
      st.jumped <- true
  | None -> fail st ~span:r.Ast.target_span "Undefined line number"

let jump_to (st : state) ~(span : Span.t) (line : int) : unit =
  match Program.index_of_line st.prog line with
  | Some i ->
      st.pc <- i;
      st.si <- 0;
      st.jumped <- true
  | None -> fail st ~span "Undefined line number"

let loop_finished (f : for_frame) (current : float) : bool =
  if f.step >= 0.0 then current > f.limit else current < f.limit

(* Skip forward to the statement after the NEXT that closes this loop, for a
   FOR whose bound fails on entry (so its body never runs). A nested FOR
   raises [depth] so an inner loop's own NEXT is not mistaken for the one
   closing this loop; NEXT with no variable, or naming this loop's variable,
   at depth 0 is the match. *)
let skip_past_next (st : state) (var : string) : unit =
  let depth = ref 0 in
  let found = ref false in
  let pc = ref st.pc and si = ref (st.si + 1) in
  while (not !found) && !pc < Array.length st.prog.Program.lines do
    match List.nth_opt st.prog.Program.lines.(!pc).Program.stmts !si with
    | None -> incr pc; si := 0
    | Some s -> (
        match s.Ast.snode with
        | Ast.For _ -> incr depth; incr si
        | Ast.Next v ->
            if !depth > 0 then (decr depth; incr si)
            else if v = None || v = Some var then (found := true; incr si)
            else incr si
        | _ -> incr si)
  done;
  if not !found then fail st "FOR without NEXT";
  st.pc <- !pc;
  st.si <- !si;
  st.jumped <- true

(* Skip forward to the statement after the WEND that closes this loop, for a
   WHILE whose condition is false on entry (so its body never runs, per
   spec/spec.md CTRL.WHILE -- confirmed the manual states this outright
   rather than leaving it to be inferred). Mirrors [skip_past_next] exactly:
   a nested WHILE raises [depth] so an inner loop's own WEND is not mistaken
   for the one closing this loop. *)
let skip_past_wend (st : state) : unit =
  let depth = ref 0 in
  let found = ref false in
  let pc = ref st.pc and si = ref (st.si + 1) in
  while (not !found) && !pc < Array.length st.prog.Program.lines do
    match List.nth_opt st.prog.Program.lines.(!pc).Program.stmts !si with
    | None -> incr pc; si := 0
    | Some s -> (
        match s.Ast.snode with
        | Ast.While _ -> incr depth; incr si
        | Ast.Wend ->
            if !depth > 0 then (decr depth; incr si)
            else (found := true; incr si)
        | _ -> incr si)
  done;
  if not !found then fail st "WHILE without WEND";
  st.pc <- !pc;
  st.si <- !si;
  st.jumped <- true

(* Colours, like coordinates and subscripts, are rounded rather than
   truncated (see [rounded_ints] above). *)
let eval_colour (st : state) (e : Ast.expr option) : int option =
  Option.map (fun e -> int_of_float (Float.round (eval_num st e))) e

let eval_point (st : state) (p : Ast.point_spec) : Display.point =
  match p with
  | Ast.PAbs (x, y) -> Display.Abs (eval_num st x, eval_num st y)
  | Ast.PStep (x, y) -> Display.Step (eval_num st x, eval_num st y)

(* ON <selector> GOTO/GOSUB <targets>: shared by both forms, which differ
   only in whether the jump also pushes a return address (spec/spec.md
   CTRL.ON-GOTO, CTRL.ON-GOSUB). *)
let exec_on (st : state) (span : Span.t) (selector : Ast.expr) (targets : Ast.line_ref list)
    ~(gosub : bool) : unit =
  let n = int_of_float (Float.round (eval_num st selector)) in
  if n < 0 then fail st ~span "Illegal function call"
  else if n = 0 || n > List.length targets then ()
  else
    let target = List.nth targets (n - 1) in
    if gosub then st.gosub <- (st.pc, st.si + 1) :: st.gosub;
    jump_to_ref st target

(* A fill argument: the palette number or the tile string that PAINT,
   CIRCLE's F and LINE ,BF all accept in the same grammar slot. Which one it
   is settled by the value's own type at run time rather than by the parser,
   since one slot carries both (ref-9801 printed p.118-119 / PDF p.129-130,
   where the tile string is defined -- CIRCLE's and LINE's entries only
   refer to it). A tile string too short to describe even one row is
   "Illegal function call", which is the error the manual names for it and
   the reason [Tile.decode] answers an option rather than raising. *)
let paint_style (st : state) ~(span : Span.t) (v : Value.t) : Display.paint_style =
  match v with
  | Value.Num (_, n) -> Display.Solid (int_of_float (Float.round n))
  | Value.Str text -> (
      match Tile.decode text with
      | Some tile -> Display.Tiled tile
      | None -> fail st ~span "Illegal function call")

let rec exec (st : state) (s : Ast.stmt) : unit =
  match s.Ast.snode with
  | Ast.Rem _ -> ()
  (* A label definition marks a place; the loader has already recorded it in
     the line table, so reaching one at run time does nothing and execution
     falls through into whatever follows the colon. *)
  | Ast.LabelDef _ -> ()
  | Ast.Let (target, e) -> assign st s.Ast.sspan target (eval st e)
  (* MID$ the statement: overwrites characters of the string already held by
     [name], in place, starting at the 1-based [start_e]. The count actually
     replaced is the smallest of: the given (or omitted) length, how many
     characters [replacement] supplies, and how many characters remain in
     [name]'s string from [start_e] onward — so this can never grow or
     shrink [name]'s length (spec/spec.md STR.MID). A [start_e] past the end
     of the current string replaces nothing, which the manual does not state
     outright but which this in-place replacement has no other way to do
     (see the STR.MID clause note). *)
  | Ast.MidAssign (name, start_e, len_e, repl_e) ->
      let target = as_str st s.Ast.sspan (Env.get_scalar st.env name) in
      let start = int_of_float (Float.round (eval_num st start_e)) in
      if start < 1 || start > 255 then fail st ~span:s.Ast.sspan "Illegal function call";
      let replacement = eval_str st repl_e in
      let requested =
        match len_e with
        | None -> String.length replacement
        | Some e ->
            let n = int_of_float (Float.round (eval_num st e)) in
            if n < 0 || n > 255 then fail st ~span:s.Ast.sspan "Illegal function call" else n
      in
      let target_len = String.length target in
      if start <= target_len then begin
        let avail = target_len - (start - 1) in
        let count = min requested (min avail (String.length replacement)) in
        let bytes = Bytes.of_string target in
        Bytes.blit_string replacement 0 bytes (start - 1) count;
        Env.set_scalar st.env name (Value.Str (Bytes.to_string bytes))
      end
  | Ast.Print (dest, using, items) -> (
      let w = match dest with Ast.ToScreen -> st.w | Ast.ToPrinter -> st.lw in
      match using with
      | None -> exec_print st w items
      | Some fmt ->
          exec_print_using st ~span:s.Ast.sspan w
            (as_str st fmt.Ast.espan (eval st fmt))
            items)
  | Ast.Goto r -> jump_to_ref st r
  | Ast.If (cond, then_branch, else_branch) ->
      exec_branch st (if eval_num st cond <> 0.0 then then_branch else else_branch)
  | Ast.End -> st.halted <- true
  (* STOP suspends rather than ends, and says so on the way out: it prints
     "Break in <line number>", naming the BASIC line it stopped at
     (ref-9801 printed p.147 / PDF p.158). END prints nothing. There is no
     CONT here to resume with, so what follows the message is the same halt
     END performs -- the message is the whole of the difference this
     interpreter can show. *)
  | Ast.Stop ->
      Print_format.put st.w (Printf.sprintf "Break in %d" (current_line st));
      Print_format.newline st.w;
      st.halted <- true
  | Ast.For (var, from, upto, step) ->
      (* [var]'s own declared type governs, the same as any other
         assignment (spec/spec.md NUM.COERCION): FOR is exactly "var =
         from" for its first step, so the value stored -- and the bound
         [loop_finished] tests -- is read back post-coercion, not the raw
         evaluated one. *)
      locate st from.Ast.espan (fun () -> Env.set_scalar st.env var (eval st from));
      (* The manual states outright that the loop variable "must be of integer
         type or single-precision type" (ref-9801 printed p.74 / PDF p.85), so
         a Double control variable is refused rather than quietly accepted.
         The test sits here rather than in the parser because a suffix-less
         name is only Double by DEFDBL, which the environment knows and the
         source text does not. The manual names no error for the violation:
         "Type mismatch" is this interpreter's choice, recorded as ours in
         spec/clauses.json CTRL.FOR. *)
      (match Env.get_scalar st.env var with
      | Value.Num (Numtype.Double, _) -> fail st ~span:s.Ast.sspan "Type mismatch"
      | _ -> ());
      let start = as_num st from.Ast.espan (Env.get_scalar st.env var) in
      let limit = eval_num st upto in
      let step = eval_num st step in
      let frame = { var; limit; step; body_pc = st.pc; body_si = st.si + 1 } in
      if loop_finished frame start then skip_past_next st var
      else st.fors <- frame :: st.fors
  | Ast.Next var ->
      let rec pop = function
        | [] -> fail st ~span:s.Ast.sspan "NEXT without FOR"
        | f :: rest -> if var = None || var = Some f.var then (f, rest) else pop rest
      in
      let frame, rest = pop st.fors in
      let current = as_num st s.Ast.sspan (Env.get_scalar st.env frame.var) in
      let next_value = current +. frame.step in
      locate st s.Ast.sspan (fun () -> Env.set_scalar st.env frame.var (pending next_value));
      if loop_finished frame next_value then st.fors <- rest
      else begin
        st.fors <- frame :: rest;
        st.pc <- frame.body_pc;
        st.si <- frame.body_si;
        st.jumped <- true
      end
  | Ast.Gosub r ->
      st.gosub <- (st.pc, st.si + 1) :: st.gosub;
      jump_to_ref st r
  (* RETURN [<line number>] (ref-9801 printed p.136 / PDF p.147). Both forms
     end the subroutine, so both pop exactly one frame; they differ only in
     where execution resumes. The manual warns that with nested subroutines,
     or a GOSUB made from inside a FOR loop, a target at a different stack
     level consumes stack abnormally -- it describes that as the programmer's
     responsibility and names no error, so nothing is checked here. *)
  | Ast.Return target -> (
      match st.gosub with
      | [] -> fail st ~span:s.Ast.sspan "RETURN without GOSUB"
      | (pc, si) :: rest -> (
          st.gosub <- rest;
          match target with
          | None ->
              st.pc <- pc;
              st.si <- si;
              st.jumped <- true
          | Some r -> jump_to_ref st r))
  (* ON <expr> GOTO/GOSUB <line>[,<line>...]: the 1-based [n]th line in the
     list is the target. A negative [n] is "Illegal function call"; 0 or
     past the end of the list falls through to the next statement rather
     than erroring -- both read directly off the manual (spec/spec.md
     CTRL.ON-GOTO, CTRL.ON-GOSUB). Rounding [n] rather than truncating it is
     this interpreter's own choice, matching [rounded_ints] everywhere else
     a whole-number argument is read; the manual does not say either way. *)
  | Ast.OnGoto (selector, targets) -> exec_on st s.Ast.sspan selector targets ~gosub:false
  | Ast.OnGosub (selector, targets) -> exec_on st s.Ast.sspan selector targets ~gosub:true
  (* WHILE <cond>: tested before every iteration, including the first --
     confirmed directly (spec/spec.md CTRL.WHILE) rather than assumed by
     analogy with FOR. A true condition pushes a frame recording this
     statement's own position, for WEND to jump back to and re-test; a false
     one skips straight past the matching WEND, the same shape [Ast.For]
     uses for a bound that fails on entry. *)
  | Ast.While cond ->
      if eval_num st cond <> 0.0 then st.whiles <- (st.pc, st.si) :: st.whiles
      else skip_past_wend st
  | Ast.Wend -> (
      match st.whiles with
      | [] -> fail st ~span:s.Ast.sspan "WEND without WHILE"
      | (pc, si) :: rest ->
          st.whiles <- rest;
          st.pc <- pc;
          st.si <- si;
          st.jumped <- true)
  (* SWAP: both operands' current values are read before either is written,
     so `SWAP A,A` and a self-referential pair are unsurprising. The manual
     allows any type as long as both sides agree; a mismatch is the ordinary
     "Type mismatch" (spec/spec.md PROG.SWAP). *)
  | Ast.Swap (a, b) ->
      let va = get_lvalue st s.Ast.sspan a and vb = get_lvalue st s.Ast.sspan b in
      (match (va, vb) with
      | Value.Num _, Value.Num _ | Value.Str _, Value.Str _ ->
          assign st s.Ast.sspan a vb;
          assign st s.Ast.sspan b va
      | _ -> fail st ~span:s.Ast.sspan "Type mismatch")
  | Ast.Erase names -> List.iter (Env.erase st.env) names
  (* CLEAR's optional slots are all memory-layout parameters this
     interpreter does not model (spec/spec.md PROG.CLEAR); each is still
     evaluated, so a malformed one reports its own error, and then ignored. *)
  | Ast.Clear args ->
      List.iter (fun a -> Option.iter (fun e -> ignore (eval_num st e)) a) args;
      Env.clear st.env
  | Ast.OptionBase n -> locate st s.Ast.sspan (fun () -> Env.option_base st.env n)
  | Ast.Dim decls ->
      List.iter
        (fun (name, bounds) ->
          locate st s.Ast.sspan (fun () ->
              Env.dim st.env name (rounded_ints st bounds)))
        decls
  (* Gathered before the first statement ran; the program counter still walks
     over the line while running. *)
  | Ast.Data _ -> ()
  (* READ does not use the ordinary assignment rules, and the manual is
     explicit about both departures (ref-9801 printed p.134 / PDF p.145, and
     again in DATA's own entry, printed p.58 / PDF p.69).

     A string constant must go to a string variable, but a *numeric*
     constant may go to either kind -- so READ A$ over DATA 42 is legal and
     gives A$ the number's own digits. The manual does not say which
     characters those are; taking PRINT's rendering of the number without
     the sign column and trailing space it adds ([format_body], the same
     text WRITE emits) is our reading, recorded in spec/clauses.json
     DATA.READ.

     And where the kinds genuinely do not match, READ raises "Syntax error"
     -- the manual says in as many words that "Type mismatch" is not what
     happens here, which makes this the one place a type confusion in this
     interpreter reports something else. Note the lexer classifies an
     unquoted DATA item as a number only if it parses as one, so DATA 1+2
     is a string constant and READ over it lands here too: the manual bars
     expressions in DATA, and this is the error it bars them with. *)
  | Ast.Read targets ->
      List.iter
        (fun target ->
          match Env.read_datum st.env with
          | None -> fail st ~span:s.Ast.sspan "Out of DATA"
          | Some v ->
              let v =
                match (Env.kind_of st.env (lvalue_name target), v) with
                | Env.KStr, Value.Num (t, x) ->
                    Value.Str (Print_format.format_body t x)
                | Env.KNum _, Value.Str _ -> fail st ~span:s.Ast.sspan "Syntax error"
                | _ -> v
              in
              assign st s.Ast.sspan target v)
        targets
  | Ast.Restore None -> Env.restore st.env 0
  | Ast.Restore (Some r) ->
      (* The first datum declared at or after that line. A line that declares
         none of its own hands the cursor to the next line that does; a line
         past every DATA leaves it at the end, where the next READ runs out. *)
      let line =
        match line_number_of_ref st r with
        | Some n -> n
        | None -> fail st ~span:r.Ast.target_span "Undefined line number"
      in
      let rec first i =
        if i >= Array.length st.data_lines then i
        else if st.data_lines.(i) >= line then i
        else first (i + 1)
      in
      Env.restore st.env (first 0)
  | Ast.DefFn (name, params, body) -> Env.define_fn st.env name params body
  (* DEFINT/DEFSNG/DEFDBL/DEFSTR <range>[,...] (spec/spec.md PROG.DEFINT,
     PROG.DEFSNG, PROG.DEFDBL, PROG.DEFSTR): declares the default kind of
     every suffix-less name starting with a letter in one of [ranges], from
     here on (basic/env.ml's [def_type]). *)
  | Ast.DefType (kind, ranges) ->
      let k =
        match kind with
        | Ast.DInt -> Env.KNum Numtype.Int
        | Ast.DSingle -> Env.KNum Numtype.Single
        | Ast.DDouble -> Env.KNum Numtype.Double
        | Ast.DStr -> Env.KStr
      in
      Env.def_type st.env k ranges
  (* INPUT [<prompt>{;|,}] <var>[,<var>...] (ref-9801 printed p.82 / PDF
     p.93). One line answers the whole statement, however many variables it
     names: the line is split on commas and must yield exactly as many
     fields as there are variables. An answer that does not fit -- a field
     whose type does not match its variable -- displays "?Redo from start"
     and waits for the whole line again, rather than stopping the program.

     The manual states the re-prompt only for a type mismatch; applying it
     to a field count that does not match is our reading, since the page
     requires the counts to agree but never says what happens when they do
     not. Silently dropping a surplus field, or leaving a variable unset,
     would both be quieter and worse. Running out of input ends the loop --
     there is no terminal here to keep asking. *)
  | Ast.Input spec ->
      let show () =
        Print_format.put st.w
          ((match spec.Ast.prompt with Some p -> p | None -> "")
          ^ if spec.Ast.show_question then "? " else "")
      in
      (* A field's value for its variable, or None if it cannot have one.
         A DEFSTR-declared suffix-less name is a string variable too, not
         only one spelled with a trailing "$" (spec/spec.md PROG.DEFSTR),
         so this asks [Env.kind_of] rather than the spelling alone. An
         empty field is 0 or the null string, which is how the manual says
         a bare Return is read. *)
      let value_for (target : Ast.lvalue) (field : string) : Value.t option =
        match Env.kind_of st.env (lvalue_name target) with
        | Env.KStr -> Some (Value.Str field)
        | Env.KNum _ ->
            if field = "" then Some (pending 0.0)
            else
              (* The SAME whole-field number reader DATA's items go through
                 (basic/lexer.ml), not OCaml's [float_of_string_opt], which
                 this used until 2026-08-18 and which is not a BASIC number
                 reader at all. OCaml's accepted literals N88-BASIC never had
                 -- "1_000" for 1000, "0x10" for 16, and "nan" and "inf",
                 which put a NaN or an overflow into a numeric variable from
                 a typed line. It also rejected "1D3", a double-precision
                 constant the manual defines (printed p.14 SS5.6), while
                 accepting its single-precision sibling "1E3" (SS5.5) -- an
                 asymmetry no reading of the manual supports.

                 Sharing DATA's reader means one definition of "what a typed
                 number looks like" rather than a second that drifts. It also
                 makes INPUT accept the radix forms; the manual does not say
                 whether a typed datum may use them, so that is our reading,
                 recorded on IN.INPUT. *)
              Option.map (fun (_, x) -> pending x) (Lexer.parse_number_literal field)
      in
      let rec ask () =
        show ();
        match st.input () with
        | None -> fail st ~span:s.Ast.sspan "Out of input"
        | Some line -> (
            let fields = Input_line.split line in
            match
              if List.length fields <> List.length spec.Ast.targets then None
              else
                List.fold_right2
                  (fun target field acc ->
                    match (acc, value_for target field) with
                    | Some vs, Some v -> Some (v :: vs)
                    | _ -> None)
                  spec.Ast.targets fields (Some [])
            with
            | Some values -> List.iter2 (assign st s.Ast.sspan) spec.Ast.targets values
            | None ->
                Print_format.put st.w "?Redo from start";
                Print_format.newline st.w;
                ask ())
      in
      ask ()
  | Ast.LineInput (prompt, target) ->
      (* No "? " here, unlike INPUT: the manual's LINE INPUT box never shows
         one, and confirmed this differs from INPUT's own page, which states
         explicitly that INPUT adds it. The whole line typed -- delimiters
         and all -- becomes the string, verbatim; a numeric target still
         goes through [assign]/[Env.coerce_to], which raises "Type mismatch"
         the same way any other string-into-numeric assignment does. *)
      Option.iter (fun p -> Print_format.put st.w p) prompt;
      (match st.input () with
      | None -> fail st ~span:s.Ast.sspan "Out of input"
      | Some text -> assign st s.Ast.sspan target (Value.Str text))
  | Ast.Write items ->
      let text = items |> List.map (fun e -> write_value (eval st e)) |> String.concat "," in
      Print_format.put st.w text;
      Print_format.newline st.w
  (* The screen and graphics statements are recorded rather than drawn. An
     argument list this record has no room for fails loudly: a form we cannot
     represent must not reach the display list as a plausible-looking
     approximation of itself. *)
  (* SCREEN [<mode>][,<switch>][,<active page>][,<display page>] (ref-9801
     printed p.140 / PDF p.151). Every slot is optional and every one that is
     given is recorded; an omitted slot stays [None] rather than acquiring a
     default, since "SCREEN ,,0,1" genuinely says nothing about the mode.

     Mode and switch are checked against the values the manual tabulates: 0-3
     for the mode, 0-3 for the switch. The two page numbers are not checked,
     and deliberately so -- the manual makes their legal range depend on both
     the screen mode and the palette mode, and palette modes are out of scope
     (spec/spec.md), so a check here would be inventing a rule rather than
     enforcing one.

     None of the three further arguments has a visible effect: this
     interpreter has one page and a 640x400 framebuffer whatever the mode.
     They are recorded so that a renderer which grows pages finds them, and
     so that a listing using them runs instead of being refused. *)
  | Ast.Screen spec ->
      let slot (e : Ast.expr option) =
        Option.map (fun e -> int_of_float (Float.round (eval_num st e))) e
      in
      let mode = slot spec.Ast.mode in
      let switch = slot spec.Ast.switch in
      let in_range v lo hi =
        match v with
        | Some n when n < lo || n > hi ->
            fail st ~span:s.Ast.sspan "Illegal function call"
        | _ -> ()
      in
      in_range mode 0 3;
      in_range switch 0 3;
      st.on_draw
        (Display.Screen
           { mode; switch; active = slot spec.Ast.active; display = slot spec.Ast.display })
  | Ast.Width args -> (
      match rounded_ints st args with
      | [ columns ] ->
          if columns <> 40 && columns <> 80 then fail st ~span:s.Ast.sspan "Illegal function call";
          Print_format.set_width st.w columns;
          st.on_draw (Display.Width (columns, None))
      | [ columns; rows ] ->
          if columns <> 40 && columns <> 80 then fail st ~span:s.Ast.sspan "Illegal function call";
          if rows <> 20 && rows <> 25 then fail st ~span:s.Ast.sspan "Illegal function call";
          Print_format.set_width st.w columns;
          st.on_draw (Display.Width (columns, Some rows))
      | _ -> fail st ~span:s.Ast.sspan "WIDTH takes one or two arguments")
  (* CLS [<function>] (ref-9801 printed p.47-48 / PDF p.58-59). The manual
     gives 1, 2 and 3 their meanings and says 1 is used when the argument
     is left out; it does not say what a fourth value does, so refusing it
     is our decision, recorded in spec/spec.md SCREEN.CLS. Refusing rather
     than clamping: CLS 4 in a listing means the listing meant something we
     have not understood, and clearing some screen anyway would hide it. *)
  | Ast.Cls arg ->
      let code =
        match arg with
        | None -> 1
        | Some e -> int_of_float (Float.round (eval_num st e))
      in
      if code < 1 || code > 3 then fail st ~span:s.Ast.sspan "Illegal function call";
      st.on_draw (Display.Cls code)
  (* KEY[(<key number>)] ON|OFF|STOP (ref-9801 printed p.87 / PDF p.98). The
     number is 1 to 10; written without it -- parentheses and all -- the
     statement means every function key, which is why [None] is passed
     through rather than expanded into ten records.

     There are no function-key interrupts in this interpreter for ON to permit
     or OFF to forbid, so all three forms are recorded and do nothing. What
     changed is that they are accepted: until now only a bare KEY OFF parsed,
     and it was filed under the screen as though it hid the function-key
     label line, which is CONSOLE's third argument and a different thing. *)
  | Ast.Key spec ->
      let number =
        Option.map (fun e -> int_of_float (Float.round (eval_num st e))) spec.Ast.key_number
      in
      (match number with
      | Some n when n < 1 || n > 10 -> fail st ~span:s.Ast.sspan "Illegal function call"
      | _ -> ());
      let action =
        match spec.Ast.key_action with
        | Ast.Key_on -> Display.Key_on
        | Ast.Key_off -> Display.Key_off
        | Ast.Key_stop -> Display.Key_stop
      in
      st.on_draw (Display.Key { number; action })
  (* LOCATE [<X>][,<Y>][,<cursor switch>] (ref-9801 printed p.99 / PDF
     p.110). X is the horizontal coordinate and comes first; an omitted X is
     column 0, while an omitted Y leaves the cursor on the line it is
     already on, so only the first default can be applied here. *)
  | Ast.Locate spec ->
      let slot e = Option.map (fun e -> int_of_float (Float.round (eval_num st e))) e in
      st.on_draw
        (Display.Locate
           {
             column = Option.value (slot spec.Ast.x) ~default:0;
             row = slot spec.Ast.y;
             cursor = slot spec.Ast.cursor;
           })
  (* CONSOLE [<scroll start line>][,<scroll line count>][,<function key
     display switch>][,<colour/monochrome switch>] (ref-9801 printed p.54 /
     PDF p.65). No slot is given a default here: the manual gives none of
     them a constant one, and an omitted slot leaves that setting as it
     stands -- state this interpreter does not keep, so filling one in would
     be inventing the previous value rather than recording its absence. *)
  | Ast.Console spec ->
      let slot e = Option.map (fun e -> int_of_float (Float.round (eval_num st e))) e in
      st.on_draw
        (Display.Console
           {
             scroll_start = slot spec.Ast.scroll_start;
             scroll_lines = slot spec.Ast.scroll_lines;
             function_keys = slot spec.Ast.function_keys;
             colour_mode = slot spec.Ast.colour_mode;
           })
  (* LINE's trailing slot means one of three things, and which one is
     settled by the B/BF that precedes it (ref-9801 printed p.94 / PDF
     p.105). With BF it is the fill, and it may be either of the two things
     a fill can be: a palette number or a tile string. Without BF it is the
     line style, and the manual forbids one there alongside BF, so the two
     readings never compete. *)
  | Ast.Line spec ->
      let trailing = Option.map (fun e -> (e, eval st e)) spec.Ast.trailing in
      let as_int e v = int_of_float (Float.round (as_num st e.Ast.espan v)) in
      let style, fill =
        match (spec.Ast.box, trailing) with
        | _, None -> (None, None)
        | `Filled, Some (_, v) -> (None, Some (paint_style st ~span:s.Ast.sspan v))
        | (`None | `Frame), Some (e, v) -> (Some (as_int e v land 0xFFFF), None)
      in
      st.on_draw
        (Display.Line
           {
             from_point = Option.map (eval_point st) spec.Ast.from_point;
             to_point = eval_point st spec.Ast.to_point;
             colour =
               Option.map
                 (fun e -> int_of_float (Float.round (eval_num st e)))
                 spec.Ast.colour;
             box = spec.Ast.box;
             style;
             fill;
           })
  (* The POINT statement moves the LP and paints nothing (printed p.122). *)
  | Ast.PointLp point -> st.on_draw (Display.Point_lp { point = eval_point st point })
  | Ast.Pset (point, colour) ->
      st.on_draw
        (Display.Pset { point = eval_point st point; colour = eval_colour st colour })
  | Ast.Preset (point, colour) ->
      st.on_draw
        (Display.Preset { point = eval_point st point; colour = eval_colour st colour })
  | Ast.Color spec ->
      let function_code = eval_colour st spec.Ast.function_code in
      let background = eval_colour st spec.Ast.background in
      let border = eval_colour st spec.Ast.border in
      let foreground = eval_colour st spec.Ast.foreground in
      (* The fifth slot switches how many palettes exist and what a colour
         code means (DISK-mode 4096-colour palette remapping) — [2] COLOR's
         territory, which this dialect's fixed 8-colour palette does not
         support. Evaluated like every other slot, so a bad expression there
         still reports the error it would anywhere else, but its presence
         itself is refused rather than silently ignored. *)
      (match eval_colour st spec.Ast.palette_mode with
      | Some _ -> fail st ~span:s.Ast.sspan "COLOR's palette-mode argument is not supported"
      | None -> ());
      st.on_draw (Display.Color { function_code; background; border; foreground })
  (* [2] COLOR = (<palette number>, <colour code>) — ref-9801 printed p.51.

     Both arguments are refused outside 0-7 with Illegal function call, which
     is OUR choice and not the manual's: the page tabulates the legal values
     per palette mode and never says what an out-of-range one does. It
     matches how this interpreter already treats an untabulated SCREEN mode,
     an out-of-range WIDTH and a KEY number outside 1-10.

     Refusing rather than wrapping matters more here than elsewhere. The
     4096-colour modes take codes &H000-&HFFF, and this interpreter supports
     only the 8-of-8 mode, so a listing written for a 4096-colour machine
     would otherwise have COLOR=(0,&HF00) silently fold to code 0 and paint a
     wrong colour that persists for the rest of the run. A refusal says the
     mode is unsupported; a wrap says nothing and draws the wrong picture. *)
  | Ast.ColorPalette (Some pal, Some code) ->
      let palette = int_of_float (Float.round (eval_num st pal)) in
      let code = int_of_float (Float.round (eval_num st code)) in
      if palette < 0 || palette > 7 || code < 0 || code > 7 then
        fail st ~span:s.Ast.sspan "Illegal function call";
      st.on_draw (Display.Color_palette { palette; code })
  (* Bare COLOR: initialise the mapping (same page). The parser routes only a
     genuinely argument-less COLOR here, so `COLOR ,,,` still means [1]
     COLOR setting nothing. *)
  | Ast.ColorPalette (None, None) -> st.on_draw Display.Color_palette_init
  | Ast.ColorPalette _ ->
      (* Unreachable: the parser builds either both arguments or neither. *)
      fail st ~span:s.Ast.sspan "COLOR palette assignment needs both arguments"
  | Ast.Circle spec ->
      let center = eval_point st spec.Ast.center in
      let radius = eval_num st spec.Ast.radius in
      let colour = eval_colour st spec.Ast.palette in
      let start_angle = Option.map (eval_num st) spec.Ast.start_angle in
      let end_angle = Option.map (eval_num st) spec.Ast.end_angle in
      let aspect = Option.map (eval_num st) spec.Ast.aspect in
      (* F fills the interior as the circle is drawn (ref-9801 printed p.45 /
         PDF p.56): with the palette number written after the F, and with the
         colour the circle itself was drawn in when that is left out. The
         third form the page offers there is a tile string, which fills the
         interior with a pattern instead ([2] PAINT, printed p.118-119). *)
      let fill =
        match spec.Ast.fill with
        | Ast.No_fill -> None
        | Ast.Fill_default -> Some Display.Fill_current
        | Ast.Fill_with e -> (
            match paint_style st ~span:s.Ast.sspan (eval st e) with
            | Display.Solid p -> Some (Display.Fill_palette p)
            | Display.Tiled t -> Some (Display.Fill_tile t))
      in
      st.on_draw
        (Display.Circle { center; radius; colour; start_angle; end_angle; aspect; fill })
  | Ast.Paint spec ->
      let point = eval_point st spec.Ast.start in
      let area =
        Option.map (fun e -> paint_style st ~span:s.Ast.sspan (eval st e)) spec.Ast.area
      in
      let border = eval_colour st spec.Ast.boundary in
      (* The manual's own note under this entry: PAINT works only within the
         viewport, whose edge is its boundary, and a start point outside the
         window is an Illegal function call. Tested here rather than in
         raster/ because it is a run-time error belonging to this statement,
         and after the other arguments are evaluated so that a malformed one
         is still reported for what it is -- the courtesy CIRCLE's F already
         gets. Until now this interpreter did nothing at all here, which was
         a divergence recorded on GFX.PAINT before it was closed. *)
      if not (st.on_in_window point) then
        fail st ~span:s.Ast.sspan "Illegal function call";
      st.on_draw (Display.Paint { point; area; border })
  (* ON ERROR GOTO <line>|0 (spec/spec.md ERR.ON-ERROR-GOTO). Target 0
     disables trapping -- except when executed from inside the handler
     routine itself, where the manual gives it a second, different meaning:
     show the message of the error that is currently being handled and
     stop, rather than quietly going back to untrapped errors. Any other
     target is not checked for existing here; a jump to a line that turns
     out not to exist is "Undefined line number" at the moment an error
     actually tries to use it, exactly like any other jump. *)
  | Ast.OnErrorGoto r ->
      (* Only the literal 0 disables trapping. A label named "*ZERO" is a
         target like any other, never the disable form. *)
      if r.Ast.target <> Ast.LineNumber 0 then st.handler <- Some r
      else if st.in_handler then (
        match st.trapped_error with
        | Some e -> raise (Error.Basic_error e)
        | None -> st.handler <- None)
      else st.handler <- None
  (* RESUME's three forms (spec/spec.md ERR.RESUME). Valid only while a
     handler is running -- RESUME outside of one is itself the manual's own
     "RESUME without error" (spec/errors.json #20), an ordinary runtime
     error like any other, so it goes through [fail_code] rather than being
     special-cased: if some *other* ON ERROR GOTO is active around it, it is
     trapped the same as any other error would be. *)
  | Ast.Resume target ->
      if not st.in_handler then fail_code st ~span:s.Ast.sspan 20 "RESUME without error"
      else begin
        st.in_handler <- false;
        match target with
        | Ast.ResumeSame ->
            st.pc <- st.failing_pc;
            st.si <- st.failing_si;
            st.jumped <- true
        | Ast.ResumeNext ->
            st.pc <- st.failing_pc;
            st.si <- st.failing_si + 1;
            st.jumped <- true
        | Ast.ResumeLine r -> jump_to_ref st r
      end
  (* ERROR <n> (spec/spec.md ERR.ERROR): simulates error number <n>, 0-255.
     A defined <n> raises with the manual's own message for it; an
     undefined one raises "Unprintable error", the shared placeholder the
     manual's appendix uses for codes with no message of their own -- by
     design, per its own heading, so a program can use an undefined number
     as an error condition of its own (spec/errors.json #21's note). Either
     way ERR is set to <n> itself, not to a number recovered from the
     message, since <n> is exactly what the manual says ERROR puts there. *)
  | Ast.RaiseError e ->
      let n = int_of_float (Float.round (eval_num st e)) in
      if n < 0 || n > 255 then fail st ~span:s.Ast.sspan "Illegal function call"
      else
        let message = Option.value (Error_catalog.message_of_number n) ~default:Error_catalog.unprintable in
        fail_code st ~span:s.Ast.sspan n message
  (* RANDOMIZE [<expr>] (spec/spec.md NUM.RANDOMIZE; ref-9801 printed p.133 /
     PDF p.144): reseeds RND's one sequence from <expr> -- through
     [rnd_seed_state], the same reseed RND(n<0) itself uses, never a second
     source of randomness. <expr> is rounded and range-checked exactly like
     any other value converted to Integer (spec/spec.md NUM.COERCION), so a
     seed outside -32768..32767 is "Overflow (OV)" like any other. A bare
     RANDOMIZE, which the manual's own page says prompts the user for a
     seed, reads one through [st.input] instead -- the one caller-supplied
     source INPUT itself reads through -- rather than the wall clock, which
     would make a run's RND sequence irreproducible; a decision of ours
     where the manual assumes an interactive terminal this interpreter does
     not have (clause NUM.RANDOMIZE is "partial" for exactly this reason). *)
  | Ast.Randomize e ->
      let raw_seed =
        match e with
        | Some e -> eval_num st e
        | None -> (
            Print_format.put st.w "Random number seed (-32768 to 32767)? ";
            match st.input () with
            | None -> fail st ~span:s.Ast.sspan "Out of input"
            | Some text -> (
                match float_of_string_opt (String.trim text) with
                | Some n -> n
                | None -> fail st ~span:s.Ast.sspan "Redo from start"))
      in
      let seed = locate st s.Ast.sspan (fun () -> Value.coerce Numtype.Int raw_seed) in
      rnd_seed_state st seed

(* Everything after THEN on a line belongs to the branch, so a jump or a halt
   inside one abandons the statements that follow it: `IF X THEN GOTO 100 :
   PRINT "…"` must not print on its way out. *)
and exec_branch (st : state) (stmts : Ast.stmt list) : unit =
  match stmts with
  | [] -> ()
  | s :: rest ->
      exec st s;
      if not (st.jumped || st.halted) then exec_branch st rest

let step (st : state) : unit =
  let line = st.prog.Program.lines.(st.pc) in
  match List.nth_opt line.Program.stmts st.si with
  | None ->
      st.pc <- st.pc + 1;
      st.si <- 0
  | Some s ->
      exec st s;
      (* Advance past this statement unless it rewrote the counters itself.
         The flag is explicit rather than inferred by comparing pc/si before and
         after: a loop whose body is empty (`10 FOR I=1 TO 3: NEXT I`) legitimately
         jumps back to the counters it already had, and comparison would read that
         as "no jump" and end the loop after one pass. *)
      if st.jumped then st.jumped <- false else st.si <- st.si + 1

(* [step], with ON ERROR GOTO's trap wrapped around it (spec/spec.md
   ERR.ON-ERROR-GOTO). An error is left to propagate -- to an outer handler
   for [run] to report, exactly as before this subsystem existed -- when
   either no handler is installed or one is already running: the manual
   states plainly that a handler does not trap an error raised inside
   itself, it shows that error's own message and stops. Otherwise this
   records everything RESUME and ERR/ERL need and jumps to the handler,
   without going through [step]'s own post-exec bookkeeping (which is for a
   statement that ran to completion, not for this substitute jump). *)
let step_trapping (st : state) : unit =
  try step st
  with Error.Basic_error e when (not st.in_handler) && st.handler <> None -> (
    st.err_number <- (match e.Error.code with
      | Some n -> n
      | None -> Option.value (Error_catalog.number_of_message e.Error.message) ~default:0);
    st.erl_line <- e.Error.line;
    st.failing_pc <- st.pc;
    st.failing_si <- st.si;
    st.trapped_error <- Some e;
    st.in_handler <- true;
    match st.handler with
    | Some r ->
        jump_to_ref st r;
        st.jumped <- false (* consumed here, not by [step]'s post-exec logic *)
    | None -> assert false (* excluded by the [when] guard above *))

let default_input () : string option = None

(* DATA is program-wide and gathered before the first statement executes, so a
   READ can reach data declared on a later line. The walk follows the line
   table, which is sorted by line number, so file order does not matter. Each
   item records the line it was declared on, which is what RESTORE <line>
   searches.

   The walk descends into IF branches. Everything after THEN belongs to the
   branch, so a DATA written anywhere to the right of one is nested inside the
   IF rather than sitting beside it — and DATA is a declaration, gathered when
   the program loads, so it counts whether or not the branch is ever taken.
   Walking only the top level would drop those data silently: with no other
   DATA present a READ fails loudly, but with some it quietly returns the wrong
   number, which is worse. *)
let collect_data (prog : Program.t) : (int * Value.t) list =
  let datum (number : int) (e : Ast.expr) : int * Value.t =
    match e.Ast.enode with
    | Ast.Num (t, n) -> (
        (* Same construction every numeric literal goes through
           (basic/value.ml's [make]), so a DATA item outside its own
           declared type's range is "Overflow (OV)" here too -- caught and
           re-raised only to attach the line this datum was declared on,
           which [Value.make] itself has no way to know. *)
        try (number, Value.make t n)
        with Error.Basic_error err -> Error.raise_at ~span:e.Ast.espan number err.Error.message)
    | Ast.Str str -> (number, Value.Str str)
    (* The parser admits only literals here; this arm exists so a later one
       cannot slip through unnoticed. *)
    | _ -> Error.raise_at ~span:e.Ast.espan number "Syntax error in DATA"
  in
  let rec from_stmt (number : int) (s : Ast.stmt) : (int * Value.t) list =
    match s.Ast.snode with
    | Ast.Data items -> List.map (datum number) items
    | Ast.If (_, then_branch, else_branch) ->
        List.concat_map (from_stmt number) (then_branch @ else_branch)
    | _ -> []
  in
  Array.to_list prog.Program.lines
  |> List.concat_map (fun (l : Program.line) ->
         List.concat_map (from_stmt l.Program.number) l.Program.stmts)

(* No rasteriser wired up: every point reports as unlit rather than
   pretending to know. A caller that cares about POINT's answers (the CLI,
   a conformance test) supplies its own, backed by raster/. *)
let default_on_point (_ : float) (_ : float) : int = -1
let default_on_in_window (_ : Display.point) : bool = true

(* (0,0) is raster/'s own starting LP, so a caller with no rasteriser gives
   the same answer a rasteriser would before anything has drawn. *)
let default_on_lp () : float * float = (0.0, 0.0)

(* [?env], [?writer] and [?lwriter] exist for one caller: an immediate-mode
   session, where the manual's direct mode (printed pp.4-6) executes a
   statement on its own and the variables it sets are still there for the
   next one. Without them every execution starts from Env.create (), which
   is what makes a REPL over this interpreter an illusion rather than a
   session.

   The writers persist as well as the environment, and that is not an
   afterthought: Print_format.writer carries the current print-zone column,
   so "PRINT 1;" followed by a separate "PRINT 2" continues the same line
   rather than restarting it, as it does on the machine. *)
let run ?(input = default_input) ?printer ?(on_draw = ignore)
    ?(on_point = default_on_point) ?(on_in_window = default_on_in_window)
    ?(on_lp = default_on_lp) ?env ?writer ?lwriter ?start_line
    ~(write : string -> unit) (prog : Program.t) : (unit, Error.t) result =
  (* On real hardware, LPRINT output goes only to the printer, not the screen.
     This interpreter has no printer, so by default it merges the streams:
     PRINT and LPRINT both go to ~write unless the caller supplies a separate
     ~printer sink. That is a deliberate deviation from PRINT.LPRINT, made so
     a program's results are never silently discarded. *)
  let printer = Option.value printer ~default:write in
  let st =
    {
      prog;
      env = (match env with Some e -> e | None -> Env.create ());
      w = (match writer with Some w -> w | None -> Print_format.make write);
      lw = (match lwriter with Some w -> w | None -> Print_format.make printer);
      on_in_window;
      input;
      on_draw;
      on_point;
      on_lp;
      data_lines = [||];
      (* RUN <line> starts execution at that line (printed p.138). An unknown
         line falls back to the start; the caller is the one positioned to
         complain about it, not this function. *)
      pc =
        (match start_line with
        | None -> 0
        | Some n -> (
            match Program.index_of_line prog n with Some i -> i | None -> 0));
      si = 0;
      jumped = false;
      halted = false;
      fors = [];
      gosub = [];
      whiles = [];
      rnd = Random.State.make [| default_rnd_seed |];
      rnd_last = 0.0;
      handler = None;
      in_handler = false;
      err_number = 0;
      erl_line = 0;
      failing_pc = 0;
      failing_si = 0;
      trapped_error = None;
    }
  in
  try
    (* Inside the handler: a malformed DATA is reported like any other runtime
       failure rather than escaping as an exception. *)
    let data = collect_data prog in
    st.data_lines <- Array.of_list (List.map fst data);
    Env.load_data st.env (List.map snd data);
    while (not st.halted) && st.pc < Array.length prog.Program.lines do
      step_trapping st
    done;
    (* Control fell off the end of the listing while still inside the error
       handler -- the manual's own "No RESUME" case (spec/errors.json #19):
       the routine never reached RESUME, END or ON ERROR GOTO 0. A handler
       that ends the ordinary way (END/STOP) never reaches here, since
       [st.halted] is what stopped the loop. *)
    if st.in_handler && not st.halted then fail_code st 19 "No RESUME";
    Ok ()
  with Error.Basic_error e -> Error e

(* A listing with any broken line does not run at all. Half-running it would
   produce output that looks like a result. *)
let run_source ?(input = default_input) ?printer ?(on_draw = ignore)
    ?(on_point = default_on_point) ?(on_in_window = default_on_in_window)
    ?(on_lp = default_on_lp) ~(write : string -> unit) (source : string) :
    (unit, Error.t) result =
  let prog, errors = Program.of_source source in
  match errors with
  | e :: _ -> Error e
  | [] -> run ~input ?printer ~on_draw ~on_point ~on_in_window ~on_lp ~write prog
