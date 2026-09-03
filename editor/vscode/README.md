# N88-BASIC(86) for VSCode

Syntax highlighting and snippets for N88-BASIC(86), the ROM BASIC of the NEC
PC-9801.

## Running and executing

**Run** (`N88-BASIC: Run`) opens a terminal and runs the saved file, which is
what you want when you are watching a program work.

Three further commands execute without leaving the editor, writing to the
**N88-BASIC** output channel:

| Command | What it does |
| --- | --- |
| `Execute Buffer` | pipes the whole document into `n88 -` |
| `Execute Selection as a Program` | pipes just the selected lines; with nothing selected, the whole buffer |
| `Immediate Statement…` | sends one unnumbered statement to a live `n88 --immediate` |

**Why three commands and not "run the current line".** That request means
something in Python it does not mean in BASIC: line 30 of a numbered program
has no `DIM`, no `DATA` and none of the assignments above it, so running it
alone is almost never useful. The manual draws the same line — printed pp.4–6
separate direct mode, where a statement stands alone, from program mode, where
numbered lines are stored and `RUN` executes them in order.

**The immediate session is a real session.** `Immediate Statement…` talks to
one long-lived `n88 --immediate` process, so `A=7` and then `PRINT A*2` prints
14 — variables, `DIM` arrays and `DEF FN` definitions persist, and `RUN`, `LIST`
and `NEW` work at that prompt. It is not a replay of earlier assignments, which
would diverge the moment a statement had a side effect. `End Immediate Session`
closes it; the next statement starts a fresh one.

## Which interpreter it uses

`n88basic.interpreterPath`, or `n88` from your `PATH` — where both the prebuilt
release binary and `opam install n88basic` put it. Point it at a wrapper script
to use the container image instead.

### Using the container instead of a binary

`interpreterPath` is a **path**, not a "use Docker" switch, so anything on disk
that speaks the CLI's interface — a file argument, `-`, `--immediate`,
`--version` — can stand in for the binary. `scripts/n88-docker` in the
interpreter's repository is that shim for the published image:

```json
"n88basic.interpreterPath": "/path/to/n88-docker"
```

It mounts the **file's** directory rather than the working directory, so a
drawing program's PNG lands beside its source where `Run` looks for it. Set
`N88_IMAGE` to pin a tag; `latest` will move, and PNG bytes changed once
already in v0.1.2.

**Why this is a script and not a feature.** Teaching the editor about
containers would mean it owning host-path translation on three platforms
(Windows drive letters, WSL paths, macOS bind mounts), container lifecycle for
the long-lived immediate session, and a choice between docker, podman, nerdctl
and whatever a corporate environment wraps them in. A path in a setting is
backend-agnostic; a boolean picks a winner. The shim is eight lines and the
editor stays ignorant of containers.

Verified through the extension's own code paths — `test-session.js` passes
end to end with the shim as the interpreter, and the command `run.js` builds
executes with the PNG landing where `Run` polls for it. **Not** verified inside
a running VS Code instance, which is the one gap.

Inside a checkout of the interpreter's own repository, with nothing configured,
`Run` builds from source instead (`dune exec`), which is what a contributor
wants. **That used to be the only thing it did**, unconditionally, so the
published extension could not run anything for anyone who had merely installed
it — the command was written when this repository was the only place the
interpreter existed.

## What works today

- **Syntax highlighting** for all 192 keywords the specification records —
  statements, functions, type suffixes, line numbers, string and numeric
  literals, `&H`/`&O` radix forms, `REM` and `'` comments, and operators.
- **Out-of-scope keywords are coloured differently.** `OPEN`, `PEEK`, `KINPUT`
  and the rest are real N88-BASIC, but this project's interpreter does not run
  them (see `spec/spec.md` §3.3). They are scoped `invalid.deprecated.*` so a
  theme distinguishes them from keywords that will actually execute — you can
  see at a glance that a listing depends on something unsupported.
- **Snippets** for `FOR`/`NEXT`, `WHILE`/`WEND`, `IF`, `ON…GOSUB`, `DEF FN`,
  `ON ERROR GOTO`, `PRINT USING`, and a graphics skeleton.
- **Editor behaviour** — comment toggling, bracket matching, and a word pattern
  that understands identifiers ending in `$`, `%`, `!` or `#`.
- **Diagnostics.** Lexical and syntax errors are reported at their real span,
  not just "line 1". A `GOTO`, `GOSUB`, `THEN <line>`, `ELSE <line>`,
  `RESTORE`, or `ON…GOTO`/`ON…GOSUB` naming a line that does not exist in the
  program is underlined at exactly the offending line number. Duplicate line
  numbers and line numbers out of ascending order are flagged too. The check
  re-runs on open, on save, and on change (debounced), and clears when a
  document closes. This is not a language server — see "How diagnostics
  work" below for why, and for what that does and does not buy you.
- **Quick fixes**, for the diagnostics that have an unambiguous repair. A
  `GOTO`/`GOSUB`/`THEN`/`ELSE`/`RESTORE`/`ON…GOTO`/`ON…GOSUB` naming a line
  that does not exist (`undefined-line`) offers to point it at the nearest
  existing line instead — one action per nearby candidate (the closest
  defined line before the target and the closest one after it), each
  spelling out exactly which number it would change to; it never guesses
  silently. Lines out of ascending order (`line-order`) offer to renumber
  the whole program, reusing the renumber machinery below — withheld
  whenever that renumbering would not actually fix the order (see "How
  quick fixes work"). Duplicate line numbers (`duplicate-line`) and syntax
  errors (`syntax-error`) get no quick fix: there is no unambiguous repair
  for either, and a wrong guess would silently corrupt the program, which is
  worse than no quick fix.
- **Hover.** Hovering a keyword shows its name, its recorded syntax (or an
  honest "syntax not yet recorded" when there is none), its summary, and —
  for a clause grounded in the manual — the clause text and source citation,
  so you can go to the manual page. Deferred and out-of-scope keywords carry
  an unmistakable banner: this is real N88-BASIC(86), but this interpreter
  will not run it (or does not yet). The text comes straight from
  `spec/keywords.json` and `spec/clauses.json` — see "Hover, completion, and
  the spec" below.
- **Completion.** Keyword completion from the same spec data, with the
  summary as detail and the syntax in the documentation; in-scope keywords
  rank above deferred and out-of-scope ones. Typing `GOTO`, `GOSUB`, `THEN`,
  `ELSE`, or `RESTORE` (or continuing a comma-separated `ON…GOTO`/`ON…GOSUB`
  list) offers the line numbers actually defined in the document as
  completions.
- **Go to definition and find references**, over line numbers — the only
  names this language has. On a `GOTO`/`GOSUB`/`THEN`/`ELSE`/`RESTORE`/
  `RESUME` target, go-to-definition jumps to the line that begins with
  that number; find-references lists every jump that names it, from
  either the target or the line's own number. Both reuse
  `renumber-scan.js`, so a number inside a string literal or after `REM`
  is not a reference here either, and the editor cannot come to disagree
  with renumbering about what a jump is.
- **Run** (`n88basic.run`, also on the editor title bar for `.bas`/`.n88`
  files). Runs the buffer through the CLI in a terminal — text output the
  way the user would see it, not a captured subprocess. If the program
  draws, it offers to open the PNG the CLI writes beside the source file.
  With no OCaml switch on `PATH`, the terminal shows the shell's own "command
  not found", not a stack trace.
- **Renumber** (`n88basic.renumber`, command palette). Prompts for a
  starting line number and an increment (default 10 and 10) and rewrites
  every line's own number together with every jump that names it — `GOTO`,
  `GOSUB`, `THEN <line>`, `ELSE <line>`, `RESTORE <line>`, and each entry in
  an `ON…GOTO`/`ON…GOSUB` list — as one `WorkspaceEdit`, so a single undo
  reverses the whole renumbering. It refuses rather than guessing wrong when
  the program has a duplicate line number, a syntax error, or a jump to a
  line that does not exist — see "How renumbering works" below for exactly
  what it checks and why.
- **Automatic line numbering** (`n88basic.insertNextLine`, command palette,
  suggested keybinding <kbd>Ctrl+K Ctrl+N</kbd> / <kbd>Cmd+K Cmd+N</kbd> —
  see "Keybindings" below). Inserts a new line after the cursor, numbered by
  continuing the file's own increment (inferred from its existing lines,
  falling back to 10). If the next number would collide with a line that
  already exists, it splits the gap instead of creating a duplicate; if
  there is no integer room left, it says so rather than duplicating a line
  number.

## What does not work yet

Nothing in this list is implemented; it is recorded so the extension does not
imply more than it does.

- No semantic tokens; only the generated TextMate grammar.

The design for these is in `docs/superpowers/specs/2026-08-16-n88basic-design.md`
§8.

## The extension's modules

`extension.js` is thin glue: it `require()`s each feature from its own file
under `src/` and wires it up in `activate()`. Every file has one job:

| File | Job |
| --- | --- |
| `src/spec-data.js` | loads `spec/keywords.json` and `spec/clauses.json`, and builds the lookup structures hover and completion share |
| `src/hover.js` | matches the cursor position to a keyword and renders its hover markdown |
| `src/completion.js` | keyword completion items, and line-number completion for jump targets |
| `src/run.js` | the `n88basic.run` command |
| `src/diagnostics.js` | wires the compiled checker bundle to a `DiagnosticCollection` |
| `src/renumber-scan.js` | finds a line's own number and every jump target it names, in document text |
| `src/renumber.js` | increment inference and the renumber plan (mapping, edits, the parser self-check) |
| `src/renumber-commands.js` | the `n88basic.renumber` and `n88basic.insertNextLine` commands |
| `src/navigation.js` | go-to-definition and find-references over line numbers |
| `src/quickfix.js` | quick-fix actions for `undefined-line` and `line-order` diagnostics, and the `CodeActionProvider` that offers them |

Within each file, the logic that doesn't need an editor — matching text,
building markdown, ranking completion items, computing a PNG's path, finding
the repository root — is a plain function with no `require('vscode')`
anywhere in the file at load time. The one function per file that does need
VSCode (`registerHoverProvider`, `registerCompletionProvider`,
`registerRunCommand`, `registerDiagnostics`, `registerRenumberCommand`,
`registerInsertNextLineCommand`, `registerCodeActionProvider`) `require()`s
`vscode` lazily, inside itself, so the rest of the file still loads under
plain node. That is what `tools/test-features.js` exercises:

```sh
node editor/vscode/tools/test-features.js
```

It calls `renderHoverMarkdown`, `matchKeywordAtPosition`,
`buildKeywordCompletionItems`, `extractLineNumbers`,
`lineNumberTriggerWord`, `pngPathFor`, `findRepoRoot`, and `buildRunCommand`
directly, against real keyword and clause fixtures, without a VSCode host.

## Hover, completion, and the spec

Hover and completion both read `spec/keywords.json` (and, for hover,
`spec/clauses.json`) rather than carrying their own copy of what a keyword
means — "editor help and the specification are the same text and cannot
drift" (design §8). A keyword whose governing clause has `"evidence":
"manual"` and a `"source"` citation is *grounded*; hover quotes its clause
text and source. A clause without that — most of them, at this stage of the
specification — is a stub ("The syntax and behaviour of X."), and hover
says nothing rather than making something up. `syntax: null` in the spec
becomes "*syntax not yet recorded*" in the hover popup, never an invented
signature.

## How diagnostics work

There is no language server here — LSP needs `vscode-languageclient` from
npm, which this project cannot install (no network access at build or install
time). Instead, `editor/lsp/checker.ml` runs the interpreter's own lexer,
parser, and line table (`basic/`) over the document text and turns the result
into a list of diagnostics. `editor/lsp/js_main.ml` compiles that to a single
dependency-free JavaScript bundle with `js_of_ocaml`, committed at
`editor/vscode/media/n88basic-check.js` (rebuilt by `dune build`, via a
`(mode promote)` rule in `editor/lsp/dune` — see that file). `src/diagnostics.js`
`require()`s the bundle directly and calls it in-process; no subprocess, no
socket, no npm package. The editor and the interpreter can never disagree
about what parses, because they share the same parser.

`editor/vscode/tools/test-diagnostics.js` exercises the bundle as a pure
function, without VSCode:

```sh
node editor/vscode/tools/test-diagnostics.js
```

LSP can replace this in-process call later behind the same `Checker.check`
entry point, if `vscode-languageclient` ever becomes available.

## How renumbering works

Renumbering happens in JavaScript over the document text (`src/renumber-scan.js`,
`src/renumber.js`), not in OCaml — the same "no OCaml toolchain required"
reasoning as diagnostics (design §8). `src/renumber-scan.js` reads each
physical line's own number, then scans every line for `GOTO`, `GOSUB`,
`THEN <n>`, `ELSE <n>`, `RESTORE <n>`, and the comma-separated lists after
`ON…GOTO`/`ON…GOSUB`, skipping anything inside a string literal or a `REM`/`'`
comment so `PRINT "GOTO 100"` is never mistaken for a jump.

New numbers are assigned in the order lines physically appear in the
document, not sorted by their old value — the two coincide for an
already-in-order program (the common case), but only assigning by physical
position also fixes a program whose physical and numeric order disagree,
which is what the `line-order` quick fix (below) depends on.

Because that duplicates knowledge the real parser already has, every computed
rewrite is checked against the real parser before it is offered: `computeRenumberPlan`
in `src/renumber.js`

1. runs the committed `n88basic-check.js` bundle (§"How diagnostics work"
   above) on the *original* text, and **refuses** — makes no edit at all — if
   it reports a syntax error, a duplicate line number, or a jump to a line
   that doesn't exist yet;
2. refuses if its own reference scan finds a jump number with no mapping
   (this catches forms the checker doesn't validate for undefined-line, such
   as `ON ERROR GOTO`, which is parsed with the same `GOTO` keyword and so is
   renumbered as a side effect of the `GOTO`/`GOSUB` handling — but is not a
   codepath the checker's `line_refs_of_stmt` walks);
3. computes the new text and runs the checker bundle on the *result*; if that
   introduces any `undefined-line` diagnostic the original didn't have, it
   **aborts and leaves the buffer untouched** rather than applying a rewrite
   it can't prove correct.

What that self-check catches: any reference form this module's regex-based
scan missed or mis-scoped — the exact failure mode of duplicating the
parser's knowledge by hand. What it cannot catch: `RESUME <line>` (inside
`ON ERROR`/`RESUME` handling). `RESUME` is a distinct keyword from `RESTORE`
and this module does not scan for it, and — separately — the checker's own
`undefined-line` diagnostic does not validate `RESUME` targets either
(`editor/lsp/checker.ml`'s `line_refs_of_stmt` does not include
`Ast.Resume`), so a `RESUME` target is neither renumbered nor guarded by the
self-check. This is a known, deliberate gap, not an oversight: it did not
ship silently broken, it shipped absent, and `tools/test-renumber.js`
documents it.

`n88basic.renumber` applies the resulting edits as a single `WorkspaceEdit`,
so one undo reverses the whole renumbering.

`editor/vscode/tools/test-renumber.js` exercises all of this as pure
functions, without VSCode, including a round-trip of every renumbered
fixture back through the checker bundle:

```sh
node editor/vscode/tools/test-renumber.js
```

## How quick fixes work

`src/quickfix.js` attaches one-click repairs to diagnostics via a
`CodeActionProvider`. It touches no source of truth of its own: the pure
function at its core, `computeActionsForDiagnostic(diagnostic, documentText)`,
takes a diagnostic shaped exactly like the ones `n88basicCheck` produces
(`{line, startCol, endCol, code, message}`) and returns `{title, edits}`
objects computed from that diagnostic's own span and (where needed)
`renumber-scan.js`'s existing `collectDefinitions` — never a new regex scan
of the text. `registerCodeActionProvider` rebuilds that plain-object shape
from the `vscode.Diagnostic`s VSCode hands back (the same ones
`src/diagnostics.js` published), so the checker's output is the only thing
ever consulted about what's wrong.

Only two codes get an action:

- **`undefined-line`** — a jump naming a line that doesn't exist. The fix
  offers to repoint it at the nearest *other* existing line: the closest
  defined line before the target and the closest one after it, each as its
  own action, each spelling out the exact number it changes to (never a
  silent guess). "Other" matters here — the jump's own line is excluded from
  candidates, or a jump far past the end of the program would routinely
  offer to point itself at itself, a silent infinite loop dressed up as a
  fix.
- **`line-order`** — lines out of ascending order. The fix reuses
  `computeRenumberPlan` (`src/renumber.js`) rather than reimplementing
  anything, and is offered only when that plan both succeeds *and* — checked
  against the real parser, same as renumbering's own self-check — actually
  leaves no `line-order` diagnostic behind. (Before the `buildMapping` fix
  described above, a plan could report success while leaving physical and
  numeric order exactly as broken as it found them, because a mapping built
  from *value-sorted* numbers can never invert the physical/value mismatch a
  `line-order` diagnostic reports — this second check exists so that gap can
  never surface as a quick fix that does nothing.)

`duplicate-line` and `syntax-error` get no action, deliberately. For a
duplicate line number, deciding which of the two physical lines keeps the
number and what the other one becomes is not recoverable from the text —
any jump naming that number was written to mean one specific physical line,
and guessing which would silently retarget it. For a syntax error, no case
was found where the repair is unambiguous. A wrong quick fix corrupts a
program silently, which is worse than no quick fix, so both are left
without one.

Every action applies as a single `WorkspaceEdit`, so one undo reverses it.
`editor/vscode/tools/test-quickfix.js` exercises all of this as pure
functions, without VSCode, including round-tripping applied edits back
through the checker bundle to confirm they actually clear the diagnostic:

```sh
node editor/vscode/tools/test-quickfix.js
```

## Keybindings

`n88basic.insertNextLine` ships a suggested keybinding,
<kbd>Ctrl+K Ctrl+N</kbd> (<kbd>Cmd+K Cmd+N</kbd> on macOS), active only in an
`n88basic` document. It is a two-key chord specifically so it doesn't
collide with a single-modifier shortcut another extension or VSCode itself
already uses. `n88basic.renumber` has no default keybinding — bind one
yourself in `keybindings.json` if you want one:

```json
{ "key": "ctrl+k ctrl+r", "command": "n88basic.renumber", "when": "editorTextFocus && resourceLangId == n88basic" }
```

## The grammar is generated, not written

`syntaxes/n88basic.tmLanguage.json` is **generated** from `spec/keywords.json`
by `tools/generate-grammar.js`. Do not edit it by hand.

A hand-maintained keyword list inside a grammar file is a second source of truth,
and it falls out of step with the specification the moment a keyword is added or
its scope changes. Generating it means the highlighting and the spec are the same
data.

```sh
node tools/generate-grammar.js   # regenerate after spec/keywords.json changes
node tools/check-grammar.js      # fails if the grammar is stale or malformed
```

`check-grammar.js` regenerates in memory and compares, so drift is caught
mechanically rather than trusted. It also verifies every pattern compiles as a
regular expression and that the manifest and language configuration are valid
JSON.

## Running it

There is no build step — the extension is declarative, with no dependencies to
install.

1. Open this repository in VSCode.
2. Press <kbd>F5</kbd> to launch an Extension Development Host, or copy
   `editor/vscode/` into `~/.vscode/extensions/n88basic/` and restart VSCode.
3. Open any `.bas` file.
