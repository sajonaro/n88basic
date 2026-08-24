(* The running interpreter's state: scalars, arrays, user-defined functions,
   and the DATA cursor. Scalars and arrays live in separate tables keyed by
   the same name, so a listing that uses both T$ and T$() sees two distinct
   cells — this dialect allows exactly that. *)

type array_val = { dims : int list; cells : Value.t array }

(* A name's declared kind: a string, or a numeric variable of one of the
   three types. Resolved once per name by [kind_of] below and used both to
   build a name's zero value and to coerce whatever is assigned to it. *)
type kind = KStr | KNum of Numtype.t

type t = {
  scalars : (string, Value.t) Hashtbl.t;
  arrays : (string, array_val) Hashtbl.t;
  fns : (string, string list * Ast.expr) Hashtbl.t;
  mutable data : Value.t array;
  mutable data_pos : int;
  (* OPTION BASE's chosen origin (spec/spec.md PROG.OPTION-BASE): the lower
     bound every array subscript in the program is checked against, and what
     an undeclared array's implicit bound is counted from. 0 until OPTION
     BASE sets it, per the manual's own stated default. *)
  mutable base : int;
  (* Whether OPTION BASE has already fixed [base] this run -- a second
     attempt is a re-specification, not a fresh one, and is refused
     regardless of what value it asks for (see [option_base] below). CLEAR
     is the only thing that puts this back to false, matching the manual's
     "RUN or CLEAR" answer for how to change a base once set. *)
  mutable base_set : bool;
  (* DEFINT/DEFSNG/DEFDBL/DEFSTR's per-letter default kind, indexed A=0..Z=25
     (ref-9801 printed p.60 / PDF p.71): the kind a name with no type
     -declaration suffix takes, from the first letter of its own name. Every
     slot starts [KNum Single] -- the manual's own stated default for a
     suffix-less name before any DEFxxx statement runs (ref-9801 printed
     p.14 / PDF p.27, section 6.2). *)
  mutable deftype : kind array;
}

let create () =
  { scalars = Hashtbl.create 32;
    arrays = Hashtbl.create 8;
    fns = Hashtbl.create 8;
    data = [||];
    data_pos = 0;
    base = 0;
    base_set = false;
    deftype = Array.make 26 (KNum Numtype.Single) }

let letter_index (c : char) : int = Char.code (Char.uppercase_ascii c) - Char.code 'A'

(* A name's declared kind (ref-9801 printed p.14 / PDF p.27, section 6.2;
   printed p.60 / PDF p.71 for DEFxxx): an explicit type-declaration suffix
   on the name always wins ("$"=string, "%"=integer, "!"=single,
   "#"=double); a suffix-less name takes whatever [e.deftype] says for its
   first letter. Applies equally to a scalar's name and an array's -- the
   manual states arrays follow the same rule (ref-9801 printed p.15 / PDF
   p.28, section 7). *)
let kind_of (e : t) (name : string) : kind =
  match name.[String.length name - 1] with
  | '$' -> KStr
  | '%' -> KNum Numtype.Int
  | '!' -> KNum Numtype.Single
  | '#' -> KNum Numtype.Double
  | _ -> e.deftype.(letter_index name.[0])

(* The zero value a variable holds before it is ever assigned (ref-9801
   printed p.14 / PDF p.27, section 6: a numeric variable starts at 0, a
   string variable at ""), typed as [kind_of] resolves the name -- 0 in a
   [KNum Numtype.Int] name is still exactly 0 with no coercion needed, so
   [Value.make] is not required here. *)
let default_value (e : t) (name : string) : Value.t =
  match kind_of e name with KStr -> Value.Str "" | KNum t -> Value.Num (t, 0.0)

(* Coerces [v] to [name]'s declared kind (spec/spec.md NUM.COERCION;
   ref-9801 printed p.18 / PDF p.31, rule 1: a value assigned to a
   differently-typed variable converts to that variable's own type). A
   string assigned to a numeric name, or vice versa, is "Type mismatch" --
   the same error every other type confusion in this interpreter raises. *)
let coerce_to (e : t) (name : string) (v : Value.t) : Value.t =
  match (kind_of e name, v) with
  | KStr, Value.Str _ -> v
  | KNum t, Value.Num (_, x) -> Value.make t x
  | KStr, Value.Num _ | KNum _, Value.Str _ -> Error.raise_at 0 "Type mismatch"

(* The key a name is stored under.

   ref-9801 printed p.15 (section 6.2) prints A!, A#, A% and A$ as four
   variables that ARE distinguished from one another, and says of them
   "A!とAは同じ" -- A! and A are the SAME variable. A bare name is therefore
   not a fifth cell: it is the same name carrying whichever suffix its
   current default kind implies, which is "!" until a DEFxxx statement
   changes it for that letter (printed p.60).

   Keying the raw spelling broke that. "A=5 : PRINT A!" printed 0, because
   the two spellings hashed to two cells -- a silent wrong answer rather than
   an error, which is the failure class this project keeps finding. With
   DEFINT A-C the same split put A and A% apart when the page makes them one.

   Arrays go through here too: the page states the rule for a variable's
   name, and section 7 (p.15) says an array variable's type is fixed by the
   same suffix on its own name.

   Nothing cited p.15 until tools/citation_coverage.py reported it. *)
let suffix_of_kind (k : kind) : string =
  match k with
  | KStr -> "$"
  | KNum Numtype.Int -> "%"
  | KNum Numtype.Single -> "!"
  | KNum Numtype.Double -> "#"

let canonical_name (e : t) (name : string) : string =
  match name.[String.length name - 1] with
  | '$' | '%' | '!' | '#' -> name
  | _ -> name ^ suffix_of_kind e.deftype.(letter_index name.[0])

let get_scalar (e : t) (name : string) : Value.t =
  match Hashtbl.find_opt e.scalars (canonical_name e name) with
  | Some v -> v
  | None -> default_value e name

let set_scalar (e : t) (name : string) (v : Value.t) : unit =
  Hashtbl.replace e.scalars (canonical_name e name) (coerce_to e name v)

(* DEFINT/DEFSNG/DEFDBL/DEFSTR <range>[,<range>...] (ref-9801 printed p.60 /
   PDF p.71): sets every letter in each (lo,hi) range's default kind, for
   every suffix-less name starting with that letter from here on. A range
   given backwards (e.g. "Z-A") sets nothing -- the manual's example ranges
   are always low-to-high and never describes what a reversed one means, so
   silently doing nothing is this interpreter's own choice rather than a
   stated rule, and matches DEFxxx's whole character as an additive
   declaration: nothing to declare, nothing changes. *)
let def_type (e : t) (k : kind) (ranges : (char * char) list) : unit =
  List.iter
    (fun (lo, hi) ->
      for i = letter_index lo to letter_index hi do
        e.deftype.(i) <- k
      done)
    ranges

(* DIM A(N) allocates subscripts 0..N inclusive, i.e. N+1 cells per axis.

   Both ends of the bound are refused here rather than left to [Array.make]:
   DIM takes a bound computed at run time, so a program can reach this with a
   negative one or an enormous one, and [Array.make]'s [Invalid_argument] is
   not a BASIC error — it would escape the interpreter's result type instead of
   stopping the program with a line number. The size is accumulated by division
   rather than multiplication so that the product of several axes cannot
   overflow into a small positive number on its way to being checked. *)
let allocate (e : t) (name : string) (dims : int list) : array_val =
  if List.exists (fun d -> d < 0) dims then Error.raise_at 0 "Subscript out of range";
  let size =
    List.fold_left
      (fun acc d ->
        if d >= Sys.max_array_length then Error.raise_at 0 "Out of memory";
        let cells = d + 1 in
        if acc > Sys.max_array_length / cells then Error.raise_at 0 "Out of memory";
        acc * cells)
      1 dims
  in
  (* A numeric array's element count is capped by its own type: 32767 for
     integer, 16383 for single precision, 8191 for double (ref-9801 printed
     p.63 / PDF p.74). The three are the same limit seen three ways -- at 2,
     4 and 8 bytes an element they all land just under 64K -- which is why
     exceeding one is "Out of memory", the error the manual gives for an
     array too large to fit, rather than an error of its own.
     The manual states the caps for numeric arrays only and says nothing
     about a string array's element count, so none is imposed here. *)
  (match kind_of e name with
  | KStr -> ()
  | KNum t ->
      let cap =
        match t with
        | Numtype.Int -> 32767
        | Numtype.Single -> 16383
        | Numtype.Double -> 8191
      in
      if size > cap then Error.raise_at 0 "Out of memory");
  { dims; cells = Array.make size (default_value e name) }

(* Redeclaring an array that already has dimensions -- fixed by an earlier
   DIM, or by its own first use before either -- is refused with the same
   error a re-specified OPTION BASE gets (spec/errors.json #10). ERASE is
   the only thing that clears an array's entry from [e.arrays], and doing so
   is exactly what makes it eligible for DIM again (see [erase] below). *)
let dim (e : t) (name : string) (dims : int list) : unit =
  let key = canonical_name e name in
  if Hashtbl.mem e.arrays key then Error.raise_at 0 "Duplicate Difinition"
  else Hashtbl.replace e.arrays key (allocate e name dims)

let find_or_default (e : t) (name : string) (subs : int list) : array_val =
  match Hashtbl.find_opt e.arrays (canonical_name e name) with
  | Some a -> a
  | None ->
      (* Undimensioned arrays default to 10 per axis above [e.base]: a
         subscript's implicit upper bound is "10, counted from the origin
         OPTION BASE sets" (spec/errors.json #9), so the default is
         [e.base + 10], not a bare 10 -- the count of usable cells (11) is
         the same regardless of the origin. *)
      let a = allocate e name (List.map (fun _ -> e.base + 10) subs) in
      Hashtbl.replace e.arrays (canonical_name e name) a;
      a

(* Row-major offset: the first subscript is the slowest-varying. For dims
   [d1; d2] and subs [s1; s2] this computes s1 * (d2 + 1) + s2, which is
   exactly the offset a two-dimensional [d1+1][d2+1] array uses in C order,
   and it stays in range because s1 <= d1 and s2 <= d2 are checked below.
   [base] is OPTION BASE's origin: every subscript's lower bound, in place of
   the literal 0 this dialect used before OPTION BASE existed. *)
let offset (base : int) (a : array_val) (subs : int list) : int =
  if List.length subs <> List.length a.dims then
    Error.raise_at 0 "Subscript out of range";
  let rec go dims subs acc =
    match (dims, subs) with
    | [], [] -> acc
    | d :: dt, s :: st ->
        if s < base || s > d then Error.raise_at 0 "Subscript out of range";
        go dt st ((acc * (d + 1)) + s)
    | _ -> assert false (* the length check above guarantees dims and subs are exhausted together *)
  in
  go a.dims subs 0

let get_element (e : t) (name : string) (subs : int list) : Value.t =
  let a = find_or_default e name subs in
  a.cells.(offset e.base a subs)

let set_element (e : t) (name : string) (subs : int list) (v : Value.t) : unit =
  let a = find_or_default e name subs in
  a.cells.(offset e.base a subs) <- coerce_to e name v

(* ERASE <name>: drops the array entirely rather than zeroing its cells, so
   the manual's own consequence follows for free -- the memory it held is
   free to be reused, and the same name can be DIM'd again, or auto-vivified
   again at its default size, exactly as if it had never been used
   (spec/spec.md PROG.ERASE). Erasing a name that was never dimensioned or
   referenced is not an error: there is nothing to remove, and [Hashtbl.remove]
   is already a silent no-op in that case. *)
let erase (e : t) (name : string) : unit =
  Hashtbl.remove e.arrays (canonical_name e name)

(* OPTION BASE <n>: fixes the origin every array subscript is checked
   against, but only the first time, and only before any array has been
   declared or referenced -- both read directly off the manual (see
   PROG.OPTION-BASE). A later attempt to change it is a re-specification,
   refused with the same "Duplicate Difinition" error DIM uses for
   redeclaring an array, whether or not [n] repeats the value already set.
   Once any array exists, OPTION BASE is not an error, but is not honoured
   either -- the manual states it has no effect there, not that it fails. *)
let option_base (e : t) (n : int) : unit =
  if e.base_set then Error.raise_at 0 "Duplicate Difinition"
  else if Hashtbl.length e.arrays > 0 then ()
  else begin
    e.base <- n;
    e.base_set <- true
  end

(* CLEAR: every scalar and array reverts to its just-created state (a
   scalar's absence from [e.scalars] already reads back as 0 or "" via
   [get_scalar]'s default, so dropping the entries is indistinguishable from
   resetting them), every DEF FN is forgotten, and OPTION BASE's origin is
   put back to unset -- the manual's own answer for how to change it once
   fixed (spec/spec.md PROG.CLEAR). The DATA cursor and any open FOR/GOSUB
   are untouched: the manual describes CLEAR purely as initializing
   variables and memory layout, never as unwinding control flow already in
   progress. [e.deftype] is untouched: the manual describes CLEAR as
   reinitializing values and array storage, never as undoing a DEFxxx
   declaration, and a program's variables would silently change type
   mid-run if it did -- a decision of ours where the manual is silent on
   this specific interaction, since none of its CLEAR examples involve
   DEFxxx. *)
let clear (e : t) : unit =
  Hashtbl.reset e.scalars;
  Hashtbl.reset e.arrays;
  Hashtbl.reset e.fns;
  e.base <- 0;
  e.base_set <- false

let define_fn (e : t) (name : string) (params : string list) (body : Ast.expr) : unit =
  Hashtbl.replace e.fns name (params, body)

let find_fn (e : t) (name : string) : (string list * Ast.expr) option =
  Hashtbl.find_opt e.fns name

let load_data (e : t) (items : Value.t list) : unit =
  e.data <- Array.of_list items;
  e.data_pos <- 0

let read_datum (e : t) : Value.t option =
  if e.data_pos >= Array.length e.data then None
  else begin
    let v = e.data.(e.data_pos) in
    e.data_pos <- e.data_pos + 1;
    Some v
  end

let restore (e : t) (pos : int) : unit = e.data_pos <- pos
