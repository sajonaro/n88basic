(* A span locates source text for error messages and for tooling that links
   this library directly. Statements in this dialect never cross a physical
   line, so a span needs only one line number and a column range.

   [line] is the PHYSICAL FILE LINE, 0-based — the nth line of the source
   text. It is NOT the BASIC line number: in a file whose first line reads
   "230 PRINT X", that statement's span has line = 0, while the error type
   reports it as BASIC line 230. Keep the two straight; they share a field
   name and mean different things. Columns are 0-based too; rendering adds 1
   to both. *)
type t = { line : int; start_col : int; end_col : int }

let make ~line ~start_col ~end_col = { line; start_col; end_col }
let to_string s = Printf.sprintf "line %d, column %d" (s.line + 1) (s.start_col + 1)
