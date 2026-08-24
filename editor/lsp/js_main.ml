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

let () = Js.export "n88basicCheck" (Js.wrap_callback check_js)
