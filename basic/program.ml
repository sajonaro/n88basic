(* The line table: a source file split into its numbered BASIC lines, sorted
   ascending by line number, with every parse failure recovered from rather
   than aborting the whole load. A physical line is this dialect's natural
   synchronisation point — a line that fails to parse is skipped, its error
   recorded, and parsing resumes at the next line — so a caller sees every
   broken line in one pass instead of one per attempt. *)

(* [number_span] covers just the line-number token, not the whole line — see
   basic/span.ml for the physical-line-vs-BASIC-line-number distinction. *)
type line = { number : int; stmts : Ast.stmt list; number_span : Span.t }

(* [labels] maps each label name to the index in [lines] of the line defining
   it, so a labelled jump costs the same as a numbered one. Built once at load
   from the [Ast.LabelDef] that opens a line (ref-9801 printed p.29 / PDF
   p.42). Names are compared in upper case: the manual's §13 gives no rule
   about label spelling at all -- no case rule, no length limit, no character
   set -- so labels are matched the way this dialect matches every other name
   (PROG.VARIABLE-NAMES, printed p.14), which is a reading of that silence and
   is recorded as ours in spec/clauses.json. *)
type t = { lines : line array; labels : (string * int) list }

(* Source files may arrive with CRLF line endings. Splitting on '\n' alone
   would leave a trailing '\r' on every line, which the lexer has no case
   for and would reject as an unexpected character. *)
let strip_trailing_cr (s : string) : string =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s

let is_blank (s : string) : bool =
  String.for_all (fun c -> c = ' ' || c = '\t') s

let full_line_span (file_line : int) (raw : string) : Span.t =
  Span.make ~line:file_line ~start_col:0 ~end_col:(String.length raw)

(* The BASIC line number a raw physical line opens with, read directly off
   the text rather than off a token — used as a fallback for failures that
   happen *inside* the lexer, before it has produced the [Token.Number] that
   would otherwise carry this. A line the lexer chokes on still plainly
   starts "30 …"; reporting that as BASIC line 0 would be a fabrication.
   [None] both when the line genuinely has no leading digits and when the
   digit run is too long for [int]: this runs inside the recovery path
   itself, so it must never raise (an out-of-range literal falls back to
   the same "no line number known" case as no digits at all, rather than
   letting `int_of_string`'s [Failure] escape past the fold in [of_source]
   that is supposed to catch everything). *)
(* ref-9801 printed p.9, SS2 and SS3. Both limits are the manual's own, stated
   in as many words, and both went unenforced until the citation sweep
   (tools/citation_coverage.py) reported that no clause cited that page. *)
let min_line_number = 1
let max_line_number = 65529
let max_line_bytes = 255

let leading_line_number (raw : string) : int option =
  let n = String.length raw in
  let i = ref 0 in
  while !i < n && (raw.[!i] = ' ' || raw.[!i] = '\t') do incr i done;
  let start = !i in
  while !i < n && raw.[!i] >= '0' && raw.[!i] <= '9' do incr i done;
  if !i = start then None
  else int_of_string_opt (String.sub raw start (!i - start))

let fallback_line_number (raw : string) : int =
  Option.value (leading_line_number raw) ~default:0

(* Parse one non-blank physical line. Tokenizing the whole raw line — rather
   than hand-splitting off the line number first — means every token's span,
   including the line number's own [number_span], lands at its true column
   in the file. Raises [Error.Basic_error] on failure; the caller recovers.

   The lexer and parser each raise [Error.Basic_error] themselves at the
   points where they still have a token-precise span in scope, with the
   BASIC line number left as 0 — they only ever see a token stream, never
   the BASIC line number a line opens with. This is the one place that
   knows both, so it re-raises with that number filled in, keeping the
   token-precise span. [Failure] is kept as a fallback for the rare failure
   neither raises a span for, in which case the whole physical line is the
   best position available. *)
let parse_physical_line (file_line : int) (raw : string) : line =
  let span = full_line_span file_line raw in
  (* ref-9801 printed p.9 SS2: "1行(行番号も含めて)には255バイトの範囲で文の記述が
     可能です" -- a line, its line number included, holds statements within 255
     BYTES. Bytes and not characters, which is why this measures the raw
     string: a line of Japanese REM text reaches the limit in far fewer
     characters. Checked before tokenizing, so an over-long line is reported
     as the one thing wrong with it rather than as whatever its tail happens
     to lex into. *)
  if String.length raw > max_line_bytes then
    Error.raise_at ~span (fallback_line_number raw)
      (Printf.sprintf "Line is longer than %d bytes" max_line_bytes);
  let toks =
    try Lexer.tokenize ~line:file_line raw with
    | Error.Basic_error e ->
        Error.raise_at ?span:e.Error.span (fallback_line_number raw) e.Error.message
    | Failure msg -> Error.raise_at ~span (fallback_line_number raw) msg
  in
  match toks with
  | { Token.kind = Token.Number (_, n); span = number_span } :: rest ->
      let number = int_of_float n in
      (* ref-9801 printed p.9 SS3: "行番号は1から65529までの整数で指定します" --
         line numbers are integers from 1 to 65529. The manual states the range
         outright, so refusing one outside it enforces its rule rather than
         inventing ours, unlike the SCREEN/WIDTH/KEY refusals elsewhere. Note
         the floor is 1, not 0: line 0 is not a line number. *)
      if number < min_line_number || number > max_line_number then
        Error.raise_at ~span:number_span number
          (Printf.sprintf "Line number must be between %d and %d" min_line_number
             max_line_number);
      let stmts =
        try Parser.parse_statements rest with
        | Error.Basic_error e ->
            Error.raise_at ?span:e.Error.span number e.Error.message
        | Failure msg -> Error.raise_at ~span number msg
      in
      { number; stmts; number_span }
  | _ ->
      Error.raise_at ~span 0
        (Printf.sprintf "Missing line number: %S" (String.trim raw))

let of_source (source : string) : t * Error.t list =
  let physical_lines =
    String.split_on_char '\n' source
    |> List.map strip_trailing_cr
    |> List.mapi (fun i raw -> (i, raw))
    |> List.filter (fun (_, raw) -> not (is_blank raw))
  in
  let lines_rev, errors_rev =
    List.fold_left
      (fun (lines_acc, errors_acc) (file_line, raw) ->
        try (parse_physical_line file_line raw :: lines_acc, errors_acc)
        with Error.Basic_error e -> (lines_acc, e :: errors_acc))
      ([], []) physical_lines
  in
  let lines =
    lines_rev
    |> List.sort (fun (a : line) (b : line) -> compare a.number b.number)
    |> Array.of_list
  in
  (* A label is defined by the [LabelDef] opening its line. A name that opens
     more than one line is "Duplicate label" -- ref-9801 printed p.30, which
     names that error in as many words and says it is detected when RUN
     begins, BEFORE any line executes, so a listing carrying one does not run
     at all.

     This clause used to read "the manual does not address it either way" and
     kept the first definition. The manual does address it; section 13 runs
     onto p.30 and the reading stopped at the page break. Nothing cited p.30
     until tools/citation_coverage.py reported it.

     The error carries no BASIC line number, which is also the page's rule:
     "この場合のエラーメッセージはエラー箇所を示す〈行番号〉はともないません".
     Line 0 is this codebase's existing spelling of "no line number known", so
     the span is kept for the editor while the message names no line. *)
  let defs =
    Array.to_list lines
    |> List.mapi (fun i (l : line) ->
           match l.stmts with
           | Ast.{ snode = LabelDef name; sspan } :: _ -> [ (name, i, sspan) ]
           | _ -> [])
    |> List.concat
  in
  let labels, duplicate_errors =
    List.fold_left
      (fun (acc, errs) (name, i, sspan) ->
        if List.mem_assoc name acc then
          (acc, { Error.line = 0; message = "Duplicate label"; span = Some sspan; code = None } :: errs)
        else ((name, i) :: acc, errs))
      ([], []) defs
  in
  let labels = List.rev labels in
  ({ lines; labels }, List.rev errors_rev @ List.rev duplicate_errors)

let index_of_label (p : t) (name : string) : int option =
  List.assoc_opt (String.uppercase_ascii name) p.labels

let index_of_line (p : t) (number : int) : int option =
  let rec search i =
    if i >= Array.length p.lines then None
    else if p.lines.(i).number = number then Some i
    else search (i + 1)
  in
  search 0
