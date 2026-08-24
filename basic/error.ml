(* [line] is the BASIC line number (230, 240 …) — what the dialect's own error
   messages name, and what a user reading a listing looks for. [span] carries
   the physical file position, whose own [line] field is the 0-based file line.
   The two are different numbers with the same field name; see basic/span.ml.

   [code] is the error's N88-BASIC(86) number (spec/errors.json), when the
   raise site already knows it -- currently only the ERROR statement, which
   is *given* a number by the program rather than discovering one. Every
   other raise site leaves it [None]; ON ERROR GOTO's handler recovers a
   number from [message] instead, via Error_catalog, when it needs one for
   ERR (basic/interp.ml). *)
type t = { line : int; message : string; span : Span.t option; code : int option }

exception Basic_error of t

let raise_at ?span ?code (line : int) (message : string) : 'a =
  raise (Basic_error { line; message; span; code })

(* [line = 0] means there is no BASIC line number to report — a missing
   line number, or a lex/parse failure on a line with no leading digits —
   not a program that genuinely has a line 0. Naming it anyway would read
   as a real line number instead of the absence of one. *)
let to_string (e : t) : string =
  let line_clause = if e.line = 0 then "" else Printf.sprintf " in line %d" e.line in
  match e.span with
  | Some s -> Printf.sprintf "%s%s (%s)" e.message line_clause (Span.to_string s)
  | None -> Printf.sprintf "%s%s" e.message line_clause
