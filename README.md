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
n88 --version                    # prints just the version, for pinning
```

`test/programs/` holds twelve worked example programs — graphics, strings,
number formatting, `DATA`/`READ`, `INPUT`, `PRINT USING`, and one complete
bar-chart program. They double as the end-to-end test:

```sh
python3 tools/run_programs.py
```

## Installing

Three ways, in rough order of convenience.

**One command, first time and every time.** It installs to `~/.local/bin`,
and running it again upgrades — printing what it replaced, so a version that
moved does not move silently:

```sh
curl -fsSL https://raw.githubusercontent.com/sajonaro/n88basic/main/install.sh | sh
#  n88 0.1.3 -> 0.1.4 (/home/you/.local/bin/n88)
```

`PREFIX=/usr/local` to install elsewhere, `VERSION=v0.1.3` to pin one. Or take
the asset directly — every release attaches `n88-linux-x86_64`, a native glibc
build:

```sh
curl -LO https://github.com/sajonaro/n88basic/releases/latest/download/n88-linux-x86_64
chmod +x n88-linux-x86_64 && ./n88-linux-x86_64 --version
```

**The container**, if you would rather install nothing — see below.

**From source**, with OCaml and dune: `scripts/install.sh` puts `n88` on your
PATH. The project is also a valid opam package, so it can be pinned directly —
**pin a release tag, not the branch**, or you get whatever `main` happens to be
that day:

```sh
opam pin add n88basic 'git+https://github.com/sajonaro/n88basic.git#v0.1.1'
```

This is the only route that gives you the *library* as well as the `n88`
command: `N88basic.Interp` and `Raster` become linkable modules. If all you
want is to run programs, the binary or the container is less work. The package
is pinnable from git and is not published to the opam repository, so
`opam install n88basic` on its own will not find it.

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

## Faithful behaviour that looks like a bug

`PRINT 1000000` gives `1E+06`, while the *larger* `PRINT 10000000` gives
`10000000` in full. This has been reported as an inconsistency twice, and it
is the manual's rule rather than a defect.

A written constant takes its type from its notation. Printed p.13 §5.5 makes
a real of **seven digits or fewer** single precision; printed p.14 §5.6 makes
a real of **eight digits or more** double precision. Single precision has a
six-digit display budget and so overflows to exponent form; double precision
has sixteen and does not. The display rule is applied identically to both —
what differs is the type the constant was written into.

Spelling the type settles it either way:

```basic
10 PRINT 1000000#     : REM prints 1000000 -- forced double, full form
20 PRINT 10000000!    : REM prints 1E+07   -- forced single, overflows
```

**The half that will actually bite you.** Those rules type a *constant* by
its notation. A **variable** with no suffix and no `DEFxxx` in effect is
single precision (printed p.14 §6.2), so the same value prints differently
depending on how it got there:

```basic
10 PRINT 10000000     : REM prints 10000000 -- an 8-digit constant is double
20 A = 10000000
30 PRINT A            : REM prints 1E+07    -- but A is single
```

So a program totalling a column into a plain variable gets exponent form
once the total passes six digits, whatever the constants looked like. That
is the machine's behaviour, not a limitation of this interpreter. Declare
the type when you want the full form — `T#`, or `DEFDBL T` at the top.

`test/conformance/num_literal_typing.bas` pins the constant path and
`num_variable_default_type.bas` the variable one; `NUM.TYPES`,
`NUM.DISPLAY` and `PROG.DEFDBL` in `spec/clauses.json` carry the pages.

## Scripting around it

Program output goes to **stdout**; diagnostics and the `wrote <file>.png`
notice go to **stderr**. Keep them separate. Merging them with `2>&1` is
order-unstable as soon as a program draws: natively the notice appears before
the program's own output, and through the container it appears after, because
the daemon multiplexes the two streams and does not preserve terminal order.
A harness that merges them will capture different byte orders from the same
program depending on how it was invoked — this cost one earlier effort seven
fabricated test failures before the cause was found.

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

## Removing it

```sh
sh install.sh --uninstall          # or: n88 --uninstall
```

Either removes the binary and then **lists what it did not install** — the VS
Code extension, any container images, an editor setting — with the exact
command for each. Neither touches those itself: a tool that removed one of
several artifacts and reported "uninstalled" would leave an extension driving a
missing interpreter.

The script detects them; the binary can only list them, since it did not place
them and cannot know. Both refuse to remove an `n88` inside an opam switch,
where `opam remove n88basic` is the right command.

**n88 writes no config file, no cache and no state directory.** Removing the
binary removes the program; there is nothing hidden to clean up afterwards.

## Versions

**Every release bumps the minor component.** `v0.1.4` is followed by `v0.2.0`,
never `v0.1.5`. The rule is enforced by `tools/check_version_bump.py` in the
release workflow, before anything is built or published, because five releases
were tagged as patch bumps by hand and nothing objected. There is no hotfix
exception: changing the scheme means editing that file, in the same commit that
tags the exception, so the decision shows up in the diff.


**The interpreter and the extension are released under one tag and carry the
same version**, so extension X.Y.Z expects `n88` X.Y.Z. An interpreter *newer*
than the extension is fine; an older one is what causes trouble, and the
extension checks at startup and tells you rather than failing obscurely later.
`n88 --version` answers the question directly.

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

**Installing it, in one place people get wrong.** The extension runs where your
files are (`extensionKind: ["workspace"]`), so in a remote window — WSL, SSH, a
dev container, Codespaces — `n88` must be installed **on the remote**, not on
the machine showing the UI.

**Upgrading from a pre-v0.1.1 `.vsix`: uninstall it first.** Those builds
declared no publisher and registered as `undefined_publisher.n88basic`, which
VS Code treats as an unrelated extension from the current
`n88basic.n88basic` — it will not upgrade one to the other, and the stale copy
can shadow the new one.

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
