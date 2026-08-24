# The VS Code extension

`editor/vscode/` is the extension; `editor/lsp/` is the checker it runs.

## What it provides

Syntax highlighting, live diagnostics, hover documentation, completion, quick
fixes, automatic line numbering and renumbering, go-to-definition and
find-references over line numbers and labels, and a Run command.

Two of these are worth explaining because they are not what an extension
usually does:

**Diagnostics come from the interpreter's own parser.** `editor/lsp/checker.ml`
depends on `basic/` and nothing else, and is compiled to JavaScript with
js_of_ocaml. The editor and the interpreter therefore cannot disagree about
what parses — there is no second grammar to drift.

**Hover and completion are generated from the specification.** The extension
reads `spec/keywords.json` and `spec/clauses.json` at run time, so the
documentation shown while typing is the same cited text the specification
carries, and updating a clause updates the editor.

## The generated bundle, and the one hazard in it

```
editor/lsp/checker.ml          OCaml, depends only on basic/
editor/lsp/js_main.ml          the only file touching js_of_ocaml
editor/vscode/media/n88basic-check.js   the committed bundle, ~100 KB
```

`dune build` regenerates that bundle as a side effect, because it is a
`(mode promote)` target. Two consequences:

- **A change to `basic/` shows the bundle as modified.** That is expected and
  the change should be committed with it, so the checker the editor runs
  matches the interpreter. A stale bundle means the editor reports diagnostics
  the interpreter no longer produces.
- The calling convention is `require('…/n88basic-check.js').n88basicCheck(source)`.
  It is not installed on `globalThis`.

The bundle is pinned to `whole_program` compilation with sourcemaps off so
its bytes do not shift with the dune profile; changing that makes every build
show it modified.

## Installing

```sh
scripts/package-extension.sh     # produces n88basic.vsix (needs @vscode/vsce)
code --install-extension n88basic.vsix
```

`scripts/install-extension.sh` copies the directory in instead, for machines
without `vsce`. Prefer the `.vsix`: a copied directory carries no version
metadata, so the editor cannot tell an updated copy from a stale one, and a
stale copy is invisible from inside the repository.

Note that the extension installs on the machine running the VS Code UI. Over
a remote connection, that is the local side, not the host where the OCaml
builds — which is why the checker ships as a JavaScript bundle rather than a
native binary.

## Why there is no language server

Every feature above works in-process against the bundle. A client/server
split would add cross-file analysis, incremental sync and cancellation, none
of which a single-file program of a few hundred lines needs, and would cost a
packaging step on an extension that currently has no build of its own.

If one is ever added, it should be a Node server calling the existing bundle
rather than a native binary, for the remote-host reason above, and it must
preserve every feature listed here.
