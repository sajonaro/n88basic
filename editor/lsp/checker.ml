(* Static diagnostics for the editor. Pure computation over basic/'s own
   lexer, parser and line table -- no I/O here either, matching basic/'s own
   rule (see basic/README.md). editor/lsp/js_main.ml is the only place that
   touches js_of_ocaml; this module stays plain OCaml so it is testable under
   the normal `dune test` suite as well as from the compiled bundle. *)

open N88basic

type severity = Error | Warning

type diagnostic = {
  line : int; (* 0-based file line -- matches Span.t, not the BASIC line number *)
  start_col : int;
  end_col : int;
  severity : severity;
  message : string;
  code : string option;
}

(* [span] is an option because [Error.t.span] is one, even though every
   raise site in basic/ happens to supply one today (see basic/error.ml) --
   a diagnostic still needs to exist for the case where that ever changes,
   rather than crashing the whole check. *)
let of_span ~severity ~message ~code (span : Span.t option) : diagnostic =
  match span with
  | Some s -> { line = s.line; start_col = s.start_col; end_col = s.end_col; severity; message; code }
  | None -> { line = 0; start_col = 0; end_col = 0; severity; message; code }

let syntax_diagnostics (errors : Error.t list) : diagnostic list =
  List.map
    (fun (e : Error.t) ->
      of_span ~severity:Error ~message:e.Error.message ~code:(Some "syntax-error") e.Error.span)
    errors

(* Every line_ref a statement names, including ones desugared from THEN/ELSE
   line targets -- the parser turns "THEN 100" / "ELSE 100" into a bare
   [Ast.Goto] inside the branch (basic/parser.ml), so descending into IF's
   branches picks those up for free without a separate case. *)
let rec line_refs_of_stmt (s : Ast.stmt) : Ast.line_ref list =
  match s.Ast.snode with
  | Ast.Goto r | Ast.Gosub r -> [ r ]
  | Ast.OnGoto (_, rs) | Ast.OnGosub (_, rs) -> rs
  | Ast.Restore (Some r) -> [ r ]
  | Ast.Restore None -> []
  (* RESUME <line> names a jump target as much as GOTO does. It is easy to
     overlook because it belongs to error handling rather than control flow,
     and overlooking it is silent twice over: no diagnostic for a dangling
     target, and the editor's renumbering — which uses these diagnostics to
     check its own work — loses its guard on the one form it is most likely
     to miss. Bare RESUME and RESUME NEXT name no line. *)
  | Ast.Resume (Ast.ResumeLine r) -> [ r ]
  | Ast.Resume (Ast.ResumeSame | Ast.ResumeNext) -> []
  | Ast.If (_, then_branch, else_branch) -> List.concat_map line_refs_of_stmt (then_branch @ else_branch)
  | _ -> []

(* The headline diagnostic: a GOTO/GOSUB/RESTORE/ON...GOTO/ON...GOSUB (or a
   desugared THEN/ELSE) naming a line the program does not define. The line
   table already knows every defined line (basic/program.ml); [target_span]
   already covers just the digits (basic/ast.ml), so the squiggle lands
   exactly under the offending number without this module computing any
   column arithmetic of its own. *)
let undefined_target_diagnostics (prog : Program.t) : diagnostic list =
  Array.to_list prog.Program.lines
  |> List.concat_map (fun (l : Program.line) -> List.concat_map line_refs_of_stmt l.Program.stmts)
  |> List.filter_map (fun (r : Ast.line_ref) ->
         (* A label is resolved through the same table and reported the same
            way, but with its own wording and code: "*EXIT does not exist" is
            what the author wrote, and a quick fix keyed on "undefined-line"
            would offer to renumber something that has no number. *)
         let resolved, message, code =
           match r.Ast.target with
           | Ast.LineNumber n ->
               ( Program.index_of_line prog n,
                 Printf.sprintf "Line %d does not exist" n,
                 "undefined-line" )
           | Ast.LabelName name ->
               ( Program.index_of_label prog name,
                 Printf.sprintf "Label *%s is not defined" name,
                 "undefined-label" )
         in
         match resolved with
         | Some _ -> None
         | None ->
             Some
               (of_span ~severity:Error ~message ~code:(Some code) (Some r.Ast.target_span)))

(* basic/program.ml sorts by BASIC line number and keeps every physical line
   as-is -- it never rejects a duplicate or an out-of-order one, it just
   resorts around it. So both checks are done here, by re-deriving file
   order from [number_span.line] (the physical file line each BASIC line
   number was read from) and walking adjacent pairs in that order: equal
   BASIC numbers are a duplicate, a BASIC number lower than the one above it
   is out of ascending order. *)
let ordering_diagnostics (prog : Program.t) : diagnostic list =
  let by_file_order =
    Array.to_list prog.Program.lines
    |> List.sort (fun (a : Program.line) (b : Program.line) ->
           compare a.Program.number_span.Span.line b.Program.number_span.Span.line)
  in
  let rec walk = function
    | (a : Program.line) :: ((b : Program.line) :: _ as rest) ->
        let here =
          if b.Program.number = a.Program.number then
            [
              of_span ~severity:Error
                ~message:(Printf.sprintf "Duplicate line number %d" b.Program.number)
                ~code:(Some "duplicate-line") (Some b.Program.number_span);
            ]
          else if b.Program.number < a.Program.number then
            [
              of_span ~severity:Warning
                ~message:
                  (Printf.sprintf "Line %d comes after line %d, out of ascending order"
                     b.Program.number a.Program.number)
                ~code:(Some "line-order") (Some b.Program.number_span);
            ]
          else []
        in
        here @ walk rest
    | _ -> []
  in
  walk by_file_order

let check (source : string) : diagnostic list =
  let prog, parse_errors = Program.of_source source in
  syntax_diagnostics parse_errors @ undefined_target_diagnostics prog @ ordering_diagnostics prog
