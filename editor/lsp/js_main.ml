(* The only file in editor/lsp/ that touches js_of_ocaml. It wires
   Checker.check up as a JavaScript function so editor/vscode/extension.js
   can call it in-process, with no language server and no npm dependency
   (see docs/superpowers/specs/2026-08-16-n88basic-design.md §8).

   Calling convention: loading the compiled bundle sets a global function
   named "n88basicCheck" (globalThis.n88basicCheck under node, or
   window.n88basicCheck in the extension host). It takes the BASIC source as
   a single string and returns a plain JS array of diagnostic objects,
   each `{ line, startCol, endCol, severity, message, code }` where `line`
   is 0-based and `severity` is the string "error" or "warning". *)

open Js_of_ocaml
open N88lsp

let severity_to_string = function Checker.Error -> "error" | Checker.Warning -> "warning"

let diagnostic_to_js (d : Checker.diagnostic) : Js.Unsafe.any =
  Js.Unsafe.obj
    [|
      ("line", Js.Unsafe.inject d.line);
      ("startCol", Js.Unsafe.inject d.start_col);
      ("endCol", Js.Unsafe.inject d.end_col);
      ("severity", Js.Unsafe.inject (Js.string (severity_to_string d.severity)));
      ("message", Js.Unsafe.inject (Js.string d.message));
      ("code", (match d.code with Some c -> Js.Unsafe.inject (Js.string c) | None -> Js.Unsafe.inject Js.null));
    |]

let check_js (source : Js.js_string Js.t) : Js.Unsafe.any Js.js_array Js.t =
  Checker.check (Js.to_string source) |> List.map diagnostic_to_js |> Array.of_list |> Js.array

(* ---- tokens, for syntax highlighting -----------------------------------

   The console paints its editor from the interpreter's OWN lexer rather than
   from a regular-expression mode maintained alongside it. A second, separate
   description of the language is a second thing to keep in step, and it
   drifts silently: the colours go on looking plausible while disagreeing with
   what actually parses. Here the colours cannot disagree, because the thing
   drawing them is the thing that reads the program.

   Calling convention: loading the bundle also sets a global function named
   "n88basicTokens". It takes the source as one string and returns a plain JS
   array of `{ line, startCol, endCol, scope }`, `line` 0-based, `scope` one
   of "comment", "string", "number", "linenumber", "keyword", "function",
   "invalid", "name", "punct". Tokens are in source order and never overlap;
   the gaps between them are whitespace the caller emits verbatim.

   A line the lexer refuses is marked invalid at the position it complained
   about, or left uncoloured when it named none -- never propagated. Half a
   program is coloured while you are still typing the other half. *)

let scope_of_kind (k : N88basic.Token.kind) : string =
  match k with
  | N88basic.Token.Keyword "REM" -> "comment"
  | N88basic.Token.Keyword w ->
      if List.mem w N88basic.Parser.intrinsics then "function" else "keyword"
  | N88basic.Token.Number _ -> "number"
  | N88basic.Token.Str _ -> "string"
  | N88basic.Token.Punct _ -> "punct"
  | N88basic.Token.Ident name ->
      (* A word this dialect reserves but this interpreter does not implement.
         The checker already reports it; colouring it as invalid says the same
         thing at a glance, and says it before the report arrives. *)
      if List.mem (String.uppercase_ascii name) N88basic.Token.reserved_unimplemented
      then "invalid"
      else "name"

(* One physical line. Two things depend on position rather than on the token
   itself: everything after REM is comment however it lexes, and a leading
   number is the BASIC line number rather than a numeric literal. *)
let scopes_of_line (toks : N88basic.Token.t list) : (N88basic.Span.t * string) list =
  let rec go first in_comment = function
    | [] -> []
    | (t : N88basic.Token.t) :: rest ->
        let scope =
          if in_comment then "comment"
          else
            match t.kind with
            | N88basic.Token.Number _ when first -> "linenumber"
            | k -> scope_of_kind k
        in
        let in_comment = in_comment || scope = "comment" in
        (t.span, scope) :: go false in_comment rest
  in
  go true false toks

let tokens_of_source (src : string) : (N88basic.Span.t * string) list =
  String.split_on_char '\n' src
  |> List.mapi (fun i line ->
         (* A CRLF file would otherwise put \r inside the last token of every
            line and shift its end column by one. *)
         let len = String.length line in
         let line =
           if len > 0 && line.[len - 1] = '\r' then String.sub line 0 (len - 1) else line
         in
         match N88basic.Lexer.tokenize ~line:i line with
         | toks -> scopes_of_line toks
         (* The lexer refuses some lines outright, and raising loses every
            token it had already scanned -- so `OPEN "x" FOR INPUT AS #1`
            would go entirely uncoloured over one bad character at the end.
            When the failure names a position, re-scan the part BEFORE it,
            which by construction is the part that lexed cleanly, and mark
            the position itself invalid. Only one retry: the prefix cannot
            fail at the same column twice. *)
         | exception N88basic.Error.Basic_error { span = Some s; _ } ->
             let prefix =
               match N88basic.Lexer.tokenize ~line:i (String.sub line 0 s.start_col) with
               | toks -> scopes_of_line toks
               | exception _ -> []
             in
             prefix @ [ (s, "invalid") ]
         | exception _ -> [])
  |> List.concat

let token_to_js ((span : N88basic.Span.t), scope) : Js.Unsafe.any =
  Js.Unsafe.obj
    [|
      ("line", Js.Unsafe.inject span.line);
      ("startCol", Js.Unsafe.inject span.start_col);
      ("endCol", Js.Unsafe.inject span.end_col);
      ("scope", Js.Unsafe.inject (Js.string scope));
    |]

let tokens_js (source : Js.js_string Js.t) : Js.Unsafe.any Js.js_array Js.t =
  tokens_of_source (Js.to_string source)
  |> List.map token_to_js |> Array.of_list |> Js.array

let () = Js.export "n88basicCheck" (Js.wrap_callback check_js)
let () = Js.export "n88basicTokens" (Js.wrap_callback tokens_js)

