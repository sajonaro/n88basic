# n88basic

An interpreter for **N88-BASIC(86)**, the BASIC that shipped in ROM on NEC's
PC-9801, together with a specification written from NEC's own reference
manual and a VS Code extension for editing programs.

```basic
10 CLS 3
20 FOR I = 7 TO 1 STEP -1
30   CIRCLE (320, 100), I * 12, I
40   PAINT (320, 100), I, I
50 NEXT I
```

```
$ n88 rings.bas
wrote rings.png
```

Programs that draw leave a PNG beside the source. Programs that only print
behave like any other command-line tool.

## Why it exists

Vintage BASIC listings are easy to find and hard to run. Emulating the whole
machine is one answer; this is the other — run the *language*, faithfully
enough that a listing from the period produces the output it was written to
produce, on a modern desktop, with no ROM image and no emulator.

"Faithfully" is the hard part, and it is why this repository contains a
specification as well as an interpreter.

## Quick start

Requires OCaml 5 and dune.

```sh
scripts/build.sh                 # interpreter + the editor's checker bundle
scripts/test.sh                  # 622 tests, the spec gates, the example programs
./_build/default/bin/main.exe test/programs/12-bar-chart.bas
```

To put it on your PATH as `n88`:

```sh
scripts/install.sh               # to ~/.local, or pass a prefix
n88 rings.bas
```

`test/programs/` holds twelve worked example programs — graphics, strings,
number formatting, `DATA`/`READ`, `INPUT`, `PRINT USING`, and one complete
bar-chart program. They double as the end-to-end test:

```sh
python3 tools/run_programs.py
```

## Using it as a container

The interpreter is published as an image, so it can be run with nothing
installed but Docker. A program that draws writes its PNG beside the source,
so mount the directory holding your programs:

```sh
docker run --rm -v "$PWD:/work" ghcr.io/sajonaro/n88basic rings.bas
```

```
wrote rings.png
```

Programs that read input work the same way:

```sh
echo "Ada,36" | docker run --rm -i -v "$PWD:/work" ghcr.io/sajonaro/n88basic ask.bas
```

Tags follow the releases: `:0.1.0` and `:0.1` pin a version, `:latest`
follows the newest. The image carries the interpreter alone — the
specification tooling and the tests are not in it.

## What works

93 keywords, and the whole expression language: the numeric type tower
(integer, single, double, with the manual's own coercion rules), string
functions, control flow including labels, `DATA`/`READ`/`RESTORE`, error
handling with `ON ERROR`/`RESUME`/`ERR`/`ERL`, `PRINT USING`'s full format
language, and graphics — `PSET`, `PRESET`, `LINE` with box and style-mask
forms, `CIRCLE`, `PAINT` with tile patterns, and the colour palette,
rendered to a 640×400 framebuffer and written out as PNG with no image
library.

## What it deliberately does not do

Being explicit about this is part of the design, not an apology for it.

- **No text screen.** `LOCATE`, `CONSOLE` and `CLS 1` parse and record their
  arguments but have no character grid to act on. Output is a stream, not a
  screen.
- **No files, sound, or machine-level access.** `OPEN`/`CLOSE`, `BEEP`,
  `PEEK`/`POKE`/`CALL`, `INP`/`OUT` and the interrupt statements are out of
  scope. A program using one is told so by name rather than misbehaving.
- **One screen mode and one graphics page**, in the default eight-colour
  palette mode.

Every one of these is recorded in `spec/spec.md` §3 with its reason, so the
boundary is a decision on the record rather than a gap someone forgot.

## The specification

`spec/` is the interesting part. It is a machine-checked description of the
dialect, and its central rule is:

> **No clause without a citation.** Every rule names the page of NEC's manual
> it came from, and `tools/check_spec.py` fails if one does not.

That rule exists because the alternative — writing down what the interpreter
happens to do — produces a document that cannot disagree with the code, and
so cannot find a bug in it. Several real defects here were found by reading a
page and discovering the interpreter contradicted it.

| | |
| --- | --- |
| `spec/spec.md` | scope, sources, and what is deliberately excluded |
| `spec/clauses.json` | 113 clauses, each cited, each with a status |
| `spec/keywords.json` | the keyword inventory and its syntax |
| `spec/errors.json` | the error catalogue with numbers and messages |
| `spec/sources.md` | the four sources, and how far each is trusted |

Where the manual is silent, the interpreter still has to do *something*, and
those choices are marked as the project's own rather than presented as the
dialect's. `PAINT`'s behaviour on an unclosed region and the error raised for
an out-of-range `SCREEN` mode are ours; the operator precedence table is the
manual's.

Four tools keep it honest:

```sh
python3 tools/coverage.py            # clause completeness
python3 tools/check_spec.py          # structural gate, and a scan for stale reasoning
python3 tools/citation_coverage.py   # pages of the manual no clause cites
python3 tools/run_programs.py        # the example programs
```

## The VS Code extension

`editor/vscode/` provides syntax highlighting, live diagnostics, hover
documentation drawn from the spec data, completion, quick fixes, automatic
line numbering and renumbering, and a Run command. Diagnostics come from the
interpreter's own parser compiled to JavaScript, so the editor and the
interpreter cannot disagree about what parses.

Every tagged release attaches a packaged `n88basic.vsix`, so the usual route
is to download it from the [releases
page](https://github.com/sajonaro/n88basic/releases) and:

```sh
code --install-extension n88basic.vsix
```

To build one from a checkout instead:

```sh
scripts/package-extension.sh     # produces n88basic.vsix (needs @vscode/vsce)
code --install-extension n88basic.vsix
```

`scripts/install-extension.sh` installs by copying the directory instead,
for machines without `vsce`. Prefer the `.vsix`: a copied directory carries
no version metadata, so the editor cannot tell an updated copy from a stale
one.

## Licence

MIT — see [`LICENSE`](LICENSE).

## Sources

The dialect is specified from primary documentation. All four sources are
listed with links and per-page provenance in [`spec/sources.md`](spec/sources.md).

- **N88-BASIC(86) Reference Manual**, NEC, 1982 — the primary source
  ([archive.org](https://archive.org/details/N88BASIC86Manual))
- **PC-9801 N88(86)BASIC command index**
  ([openspc2.org](http://www.openspc2.org/BASIC/HTML/PC-9801%5BN88\(86\)BASIC%5D.html))
- **PC-8801 N88-BASIC入門** — a different machine in the same family, used
  only for orientation ([archive.org](https://archive.org/details/PC8801N88BASIC))
- **PC-8801 N88-BASIC解析マニュアル**, 川村清 — third-party analysis of
  interpreter internals ([archive.org](https://archive.org/details/PC-8801N88-BASIC))

The manuals themselves are not redistributed here. Citations name the printed
page so a reader can follow them in their own copy.

N88-BASIC is a trademark of NEC Corporation. This project is not affiliated
with or endorsed by NEC.

## Layout

```
basic/    the interpreter: lexer, parser, evaluator
raster/   display list to framebuffer to PNG, no dependencies
bin/      the n88 command-line runner
editor/   the VS Code extension and its checker
spec/     the cited specification and its data
test/     unit tests, conformance cases, example programs
tools/    the spec and example-program checkers
```
