(* The syntax tree. Every node is a record pairing its variant with the
   [Span.t] of the source text it was built from: a node's span runs from the
   start of its first token to the end of its last. Spans exist so that a
   diagnostic can name a position — "in line 230, column 14" beats "parse
   error" — and so that a tool reading this library can locate what it reads.
   Nothing here knows anything about who consumes it. *)

(* Which of DEFINT/DEFSNG/DEFDBL/DEFSTR a [DefType] statement is: the first
   three name a [Numtype.t] a suffix-less name should default to; [DStr]
   names the string type, which has no [Numtype.t] of its own to reuse. *)
type def_kind = DInt | DSingle | DDouble | DStr

type expr = { enode : expr_node; espan : Span.t }

and expr_node =
  | Num of Numtype.t * float
  | Str of string
  | Var of string
  | Index of string * expr list (* array element: A(1,2) *)
  | Call of string * expr list (* ABS(X), SQR(X), FNA(X) *)
  | Unary of string * expr (* "-" or "NOT" *)
  | Binop of string * expr * expr

type lvalue = LVar of string | LIndex of string * expr list

(* A reference to a BASIC line number, from GOTO, GOSUB, RESTORE, or a
   desugared THEN/ELSE target. [target_span] covers only the digits of the
   literal — not the keyword and not the enclosing statement — so that a
   diagnostic can underline exactly the offending number, and so that a
   renumbering pass can rewrite it by surgical text edit rather than by
   re-emitting the line and losing its comments and spacing. *)
(* What a line reference names: a literal line number, or a label standing in
   for one. The manual introduces labels as a substitute for a line number "at
   a program's branch targets and when editing the program", and its motivating
   example is RENUM -- with labels there is no new line number to re-check
   after renumbering (ref-9801 printed p.29 / PDF p.42, §13 ラベル名). A
   variant rather than an int-with-optional-label so that no site can read a
   meaningless number out of a labelled reference by accident. *)
type line_target = LineNumber of int | LabelName of string

type line_ref = { target : line_target; target_span : Span.t }

(* [ToScreen] and [ToPrinter] rather than [Screen] and [Printer]: the SCREEN
   statement below must keep the name of its keyword, and one function will
   match both types. *)
type print_dest = ToScreen | ToPrinter

type print_item =
  | PExpr of expr
  | PComma
  | PSemi
  | PTab of expr (* TAB(n) in a PRINT list *)
  | PSpc of expr (* SPC(n) in a PRINT list -- n literal spaces, never a
                    general string expression (spec/spec.md PRINT.SPC) *)

type stmt = { snode : stmt_node; sspan : Span.t }

and stmt_node =
  | Let of lvalue * expr
  (* MID$(<char-var>, <start>[, <len>]) = <replacement> — the statement form
     of MID$, which overwrites characters of an existing string variable in
     place rather than naming a new one. The target is always a plain
     variable in the manual's examples, never an array element, so it is
     carried as a bare name rather than an [lvalue]. *)
  | MidAssign of string * expr * expr option * expr
  | Print of print_dest * expr option * print_item list
      (* destination, USING format expression, items *)
  | Input of input_spec
  (* LINE INPUT [<prompt>;] <string var> (spec/spec.md IN.LINE-INPUT): unlike
     INPUT, the whole line typed is stored verbatim in one string variable --
     no comma-splitting, no numeric coercion, no "? " appended after the
     prompt. *)
  | LineInput of string option * lvalue
  (* WRITE <expr>[(,|;)<expr>...] (spec/spec.md PRINT.WRITE): like PRINT, but
     items are always comma-separated on output regardless of which of ","
     or ";" the source used, strings are quoted, and numbers carry none of
     PRINT's padding. At least one expression is required -- the manual's
     own syntax box does not bracket the first one, unlike PRINT's. *)
  | Write of expr list
  | For of string * expr * expr * expr (* var, from, to, step *)
  | Next of string option
  | If of expr * stmt list * stmt list (* condition, then-branch, else-branch *)
  | Goto of line_ref
  | Gosub of line_ref
  (* RETURN [<line number>] (ref-9801 printed p.136 / PDF p.147). [None]
     resumes at the statement after the calling GOSUB; [Some r] ends the
     subroutine but resumes at [r] instead. The manual requires the caller
     to pick a target at the same stack level when subroutines nest or the
     GOSUB sits inside a FOR loop, and advises against the form otherwise;
     it describes no check, so none is made here. *)
  | Return of line_ref option
  (* ON <expr> GOTO/GOSUB <line>[,<line>...]: the 1-based line_ref at
     position <expr> in the list is the target (spec/spec.md CTRL.ON-GOTO,
     CTRL.ON-GOSUB). *)
  | OnGoto of expr * line_ref list
  | OnGosub of expr * line_ref list
  (* WHILE <cond> ... WEND: [While] tests its condition and, if true, falls
     through into the loop body; [Wend] is the closing bracket that jumps
     back to its matching [While] to re-test. Nothing here records *which*
     WHILE a WEND closes -- that pairing is entirely a runtime stack
     (basic/interp.ml), the same way [For]/[Next] do not name their partner
     either. *)
  | While of expr
  | Wend
  | Swap of lvalue * lvalue
  (* ERASE <array name>[, <array name>...] -- bare names, no subscripts
     (spec/spec.md PROG.ERASE). *)
  | Erase of string list
  (* CLEAR [<dummy>][,<memory limit>][,<stack size>][,<array area size>]:
     every slot is an optional numeric expression, parsed and evaluated (so
     a malformed one still reports its error) but otherwise ignored -- see
     the PROG.CLEAR clause for which parts this interpreter models. *)
  | Clear of expr option list
  (* OPTION BASE 0|1 -- the manual's own syntax box offers only the two
     literal digits, not a general expression, so the parser reads a bare
     0 or 1 rather than an [expr] (spec/spec.md PROG.OPTION-BASE). *)
  | OptionBase of int
  | Dim of (string * expr list) list
  | Data of expr list (* literals only *)
  | Read of lvalue list
  | Restore of line_ref option
  | DefFn of string * string list * expr
  (* DEFINT/DEFSNG/DEFDBL/DEFSTR <letter>['-'<letter>][, ...] (ref-9801
     printed p.60 / PDF p.71): declares the default type of every
     suffix-less name starting with a letter in one of the given ranges.
     Each pair is inclusive on both ends; a bare letter (no "-") is carried
     as [(c, c)], one range of a single letter. *)
  | DefType of def_kind * (char * char) list
  (* "*NAME" defining a label at this line, as in the manual's own
     "60 *PLUS : PRINT \"plus\"" (ref-9801 printed p.29 / PDF p.42). The page
     writes a definition only as the first statement of its line, and only
     ever colon-separated from the rest; this interpreter enforces that
     position rather than allowing one mid-line, because a label reached
     mid-line would have to name a statement rather than a line and the
     manual describes no such thing. That restriction is ours. *)
  | LabelDef of string
  | Rem of string
  | End
  | Stop
  (* Screen and graphics statements. The evaluator records these into a
     display list rather than drawing them. *)
  | Screen of screen_spec
  | Width of expr list (* WIDTH columns[, rows] *)
  | Cls of expr option (* CLS [<function>] — 1 text, 2 graphics, 3 both *)
  | Key of key_spec
  | Locate of locate_spec
  | Console of console_spec
  | Line of line_spec
  (* The POINT statement (ref-9801 printed p.122): sets the LP and draws
     nothing at all. Distinct from both POINT functions, which are calls in
     expression position; this one is only ever a statement. *)
  | PointLp of point_spec
  | Pset of point_spec * expr option (* point, colour *)
  | Preset of point_spec * expr option (* point, colour *)
  | Color of color_spec
  (* [2] COLOR=(<palette>,<code>) — recolours a palette entry itself, rather
     than choosing among the fixed 8, so it is parsed (a listing that uses
     it still loads) but refused at run time: out of scope per
     spec/spec.md §3, the same as COLOR@. *)
  | ColorPalette of expr option * expr option (* palette number, colour code *)
  | Circle of circle_spec
  | Paint of paint_spec
  (* ON ERROR GOTO <line number> (ref-9801 printed p.109 / PDF p.120):
     installs <line number> as the error-handling routine's entry point.
     Target 0 is the manual's own way to disable trapping again, carried
     here as an ordinary [line_ref] rather than an [int option] so a bad
     target still has a span to blame -- interp.ml is what gives 0 its
     special meaning, the same way it alone decides what a GOTO target
     means. *)
  | OnErrorGoto of line_ref
  | Resume of resume_target
  (* ERROR <n>: simulates error number <n> (0-255), or defines a program's
     own (ref-9801 printed p.71 / PDF p.82). *)
  | RaiseError of expr
  (* RANDOMIZE [<expr>] (spec/spec.md NUM.RANDOMIZE; ref-9801 printed p.133
     / PDF p.144): reseeds RND's sequence from <expr>. A bare RANDOMIZE is
     the manual's own way to prompt for a seed instead of taking one from
     the source -- see the Ast.Randomize case in interp.ml for what that
     means with no interactive terminal to prompt. *)
  | Randomize of expr option

(* RESUME's three forms (ref-9801 printed p.136 / PDF p.147): retry the
   statement that failed, continue with the one after it, or jump to a
   given line -- interp.ml is what remembers which statement failed, since
   nothing at parse time knows that yet. *)
and resume_target = ResumeSame | ResumeNext | ResumeLine of line_ref

and line_spec = {
  from_point : point_spec option; (* absent means "last point referenced" *)
  to_point : point_spec;
  colour : expr option;
  box : [ `None | `Frame | `Filled ]; (* the trailing ,B / ,BF forms *)
  (* The one slot after B or BF, which the manual gives three different
     meanings depending on what precedes it (ref-9801 printed p.94 / PDF
     p.105): a line style for a plain line or a ,B outline, or -- for ,BF
     alone -- a second palette number or a tile string to fill with. The
     manual states outright that a line style may not be given with BF, so
     the three readings never compete for the same statement and the
     evaluator can tell them apart from [box] without the parser
     committing. *)
  trailing : expr option;
}

(* PSET and PRESET's coordinate: absolute, or STEP(x,y) relative to the LP.
   [expr] rather than [float] because this is still parse-time syntax; the
   evaluator turns it into a Display.point once its expressions run. *)
and point_spec = PAbs of expr * expr | PStep of expr * expr

(* INPUT [<prompt>{;|,}] <var>[,<var>...] (ref-9801 printed p.82 / PDF p.93).
   The separator after a prompt is part of the syntax box's bracketed unit
   and decides what is shown: ";" adds a question mark and one space after
   the prompt text, "," adds nothing at all. [show_question] carries that
   choice, and is true for a statement with no prompt at all -- which the
   manual's box allows and its text never describes, so showing "? " there
   is this interpreter's reading, recorded in spec/clauses.json IN.INPUT. *)
and input_spec = { prompt : string option; show_question : bool; targets : lvalue list }

(* CONSOLE [<scroll start line>][,<scroll line count>][,<function key display
   switch>][,<colour/monochrome switch>] (ref-9801 printed p.54 / PDF p.65).
   Every slot is optional and an empty one is written as a bare comma, which
   the manual's own second example (CONSOLE ,,1,0) relies on. No slot has a
   constant default: an omitted one leaves that setting as it stands, so all
   four stay optional the whole way to the display list rather than being
   filled in with a guess here. *)
and console_spec = {
  scroll_start : expr option;
  scroll_lines : expr option;
  function_keys : expr option;
  colour_mode : expr option;
}

(* LOCATE [<X>][,<Y>][,<cursor switch>] (ref-9801 printed p.99 / PDF p.110).
   X is the HORIZONTAL coordinate and comes first — the field order here is
   the manual's, and reading the first argument as a row is the divergence
   this record was introduced to end. Every slot is genuinely optional, and
   the two defaults are not symmetric: an omitted X means column 0, while an
   omitted Y means "the line the cursor is already on", which is why both
   stay [expr option] this far in rather than being defaulted at parse
   time. *)
and locate_spec = { x : expr option; y : expr option; cursor : expr option }

(* SCREEN's four slots, every one of them optional and an omitted one written
   as a bare comma (ref-9801 printed p.140 / PDF p.151). [mode] is the basic
   colour/resolution mode 0-3; [switch] shows the graphics screen at 0 or 1
   and blanks it temporarily at 2 or 3; [active] and [display] choose the page
   graphics are written to and the page shown. *)
and screen_spec = {
  mode : expr option;
  switch : expr option;
  active : expr option;
  display : expr option;
}

(* KEY[(<key number>)] ON|OFF|STOP (ref-9801 printed p.87 / PDF p.98). The
   number is absent when the listing wrote none -- parentheses included --
   which the manual makes mean every function key rather than any particular
   one, so [None] here is "all ten", not "unspecified". *)
and key_spec = { key_number : expr option; key_action : key_action }
and key_action = Key_on | Key_off | Key_stop

and color_spec = {
  function_code : expr option;
  background : expr option;
  border : expr option;
  foreground : expr option;
  palette_mode : expr option;
      (* [1] COLOR's fifth slot: DISK-mode palette-count switch. Out of
         scope for the same reason as [2] COLOR — parsed, refused at run
         time if given. *)
}

(* CIRCLE (Wx,Wy)|STEP(x,y), <radius> [,<palette 1>] [,<start angle>]
   [,<end angle>] [,<aspect>] [,F [,<palette 2>|<tile string>]] (ref-9801
   printed p.45). [fill] is parsed in full so a listing that uses F still
   loads, but F itself is refused at run time -- see the Ast.Circle case in
   interp.ml -- since filling correctly (respecting a sector's radius lines
   as part of the boundary) is materially more work than drawing the arc,
   and a silently-unfilled circle would be exactly the "looks plausible but
   isn't" rendering design SS11 warns against. *)
and circle_spec = {
  center : point_spec;
  radius : expr;
  palette : expr option; (* <palette 1>: not [colour], which line_spec
                             already uses -- see the module-level note on
                             duplicate record labels *)
  start_angle : expr option;
  end_angle : expr option;
  aspect : expr option;
  fill : circle_fill;
}

and circle_fill =
  | No_fill
  | Fill_default (* trailing "F" alone *)
  | Fill_with of expr (* "F, <expr>" -- a palette number or a tile string;
                          eval decides which it turned out to be *)

(* PAINT (Wx,Wy)|STEP(x,y) [,<area>[,<border>]] (ref-9801 printed p.117).
   [area] is parsed as a plain expression rather than typed at parse time,
   because form [2] (tiling, ref-9801 printed p.118, out of scope per
   spec/spec.md SS3.3) shares this exact shape with a tile string in the same
   slot -- the two are indistinguishable until [area] is evaluated and found
   to be a Value.Str, at which point interp.ml refuses it, the same way
   Ast.ColorPalette is parsed but refused. *)
and paint_spec = {
  start : point_spec;
  area : expr option;
  boundary : expr option; (* <border colour>: not [border], which
                              color_spec already uses *)
}
