type kind =
  | Number of Numtype.t * float
  | Str of string
  | Ident of string
  | Keyword of string
  | Punct of string

type t = { kind : kind; span : Span.t }

(* The reserved-word table: every word the scanner recognises as a keyword
   when a whole identifier run (basic/lexer.ml's maximal-munch scan) matches
   it exactly. Order does not matter -- membership is checked, not prefix.

   MAX is not a reserved word in N88-BASIC and is used as an ordinary
   variable name, so it must never appear in this table. *)
let keywords =
  [ "RESTORE"; "RETURN"; "LOCATE"; "SCREEN"; "LPRINT"; "STRING$"; "WIDTH"; "GOSUB";
    "PRINT"; "RIGHT$"; "INSTR"; "INPUT"; "USING"; "LEFT$"; "PRESET"; "GOTO"; "STEP";
    "WRITE";
    "THEN"; "DATA"; "READ"; "STOP"; "NEXT"; "ELSE"; "CHR$"; "HEX$"; "OCT$"; "MID$";
    "STR$"; "LINE"; "COLOR"; "POINT"; "PSET"; "DEF"; "DIM"; "REM"; "END"; "LET";
    "FOR"; "AND"; "NOT"; "TAB"; "CLS"; "KEY"; "OFF"; "ABS"; "INT"; "SQR"; "SGN";
    "SIN"; "VAL"; "LEN"; "ASC"; "TO"; "IF"; "OR"; "FN";
    (* The 16 numeric/output functions closed off from being usable as array
       names (spec/spec.md §3.1's numeric functions, PRINT.SPC, PRINT.POS,
       PRINT.CSRLIN, ERR.FN, ERR.ERL): before these were reserved words,
       spelling one of them with a following "(" parsed as an ordinary array
       reference, which basic/env.ml auto-creates and answers with element 0
       -- computing a silent, wrong 0 instead of failing. See
       basic/parser.ml's [intrinsics] and the special-cased
       RND/CSRLIN/ERR/ERL/SPC handling for how each is actually parsed. *)
    "CSRLIN"; "SPACE$"; "CDBL"; "CINT"; "CSNG"; "ATN"; "COS"; "ERL"; "ERR"; "EXP";
    "FIX"; "LOG"; "POS"; "RND"; "SPC"; "TAN";
    (* The control-flow and program-structure statements closed off the same
       way (spec/spec.md CTRL.WHILE, CTRL.WEND, CTRL.ON-GOTO, CTRL.ON-GOSUB,
       PROG.SWAP, PROG.ERASE, PROG.CLEAR, PROG.OPTION-BASE): each of these
       words, spelled with a following "(", used to parse as an ordinary
       array reference the same way an unimplemented numeric function did,
       for the same reason -- nothing had told the lexer they were reserved. *)
    "WHILE"; "WEND"; "ON"; "SWAP"; "ERASE"; "CLEAR"; "OPTION"; "BASE";
    "CIRCLE"; "PAINT";
    (* Error handling (spec/spec.md ERR.ON-ERROR-GOTO, ERR.RESUME,
       ERR.ERROR): closed off the same way, for the same reason. "ON" and
       "ERR"/"ERL" above are already reserved; these two complete the set. *)
    "RESUME"; "ERROR";
    (* Type declaration (spec/spec.md PROG.DEFINT, PROG.DEFSNG, PROG.DEFDBL,
       PROG.DEFSTR): closed off the same way -- before these were reserved
       words, e.g. "DEFINT(" parsed as a reference to an ordinary array named
       DEFINT. *)
    "DEFINT"; "DEFSNG"; "DEFDBL"; "DEFSTR";
    (* RANDOMIZE (spec/spec.md NUM.RANDOMIZE): closed off the same way --
       before this was a reserved word, "RANDOMIZE(" parsed as a reference
       to an ordinary array named RANDOMIZE. *)
    "RANDOMIZE";
    (* The four operators of the manual's precedence table (printed p.25 /
       PDF p.38, section 10.6) that this interpreter did not have: MOD at
       level 7, XOR at 13, IMP at 14, EQV at 15. Until they were reserved
       each one silently lexed as an ordinary variable, so "PRINT 7 MOD 3"
       printed " 7  0  3" -- three items and a variable worth zero, rather
       than a remainder. That is the same silent-wrong-answer failure this
       table's earlier entries were added to stop, and it broke spec.md
       section 3.3's promise that an unsupported feature at least parses
       and names itself. *)
    "MOD"; "XOR"; "IMP"; "EQV";
    (* CONSOLE (spec/spec.md SCREEN.CONSOLE): in scope from the start and
       missing from this table until the page was read, so "CONSOLE 0,24,0,1"
       scanned CONSOLE as an ordinary identifier and the statement failed
       asking for the "=" of an assignment. *)
    "CONSOLE" ]
