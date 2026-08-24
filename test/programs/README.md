# Example programs

Whole programs, run by `python3 tools/run_programs.py`. They serve two
purposes at once: they are worked examples of the language for anyone picking
up the interpreter, and they are the only thing that exercises it end to end
rather than one rule at a time.

They are **not** conformance cases and this is **not** a gate.
`test/conformance/` asserts exact output and fails the build. That works
because what it asserts is a string. Several of these draw, and what a
drawing program asserts is a picture — no string comparison decides that.

## How they check themselves

Where the language can read back what it just did, they use it. `POINT`
returns the palette number at a screen coordinate, so a program that draws a
circle and fills it can state what the centre, the rim and the outside should
be and print the answers. That is worth more than a digest: a hash only ever
says "unchanged", while a readback says "correct".

What a readback cannot see, a human must. Open the PNG.

## Running one

    dune build
    ./_build/default/bin/main.exe test/programs/05-circles-and-paint.bas

A program that draws leaves a PNG beside its source. One that draws nothing
does not, and that is deliberate.

## Interactive programs

A program that reads input carries a `<name>.stdin` beside it, holding the
keystrokes to feed it. `tools/run_programs.py` supplies it automatically.
Such a program usually ends by running out of input, which the runner reports
as `ran to input exhaustion` rather than as a failure — on the real machine
the reader would have pressed STOP.

## What each one covers

| | |
| --- | --- |
| `01-points-and-colour` | `CONSOLE`, `[1] COLOR`'s four slots, `PSET`, `[2] COLOR` |
| `02-erase-with-preset` | `PRESET` against the background colour |
| `03-lines-and-styles` | `LINE`, and the sixteen-bit style mask |
| `04-boxes` | `,B` and `,BF`, and a styled outline |
| `05-circles-and-paint` | `CIRCLE`, `PAINT` bounded by a colour |
| `06-palette-recolour` | reassigning a palette recolours what is already drawn |
| `07-string-toolkit` | `LEN` `LEFT$` `RIGHT$` `MID$` `INSTR` `ASC` `CHR$` `STRING$` `SPACE$` |
| `08-numbers-and-formats` | print zones, fixed vs exponent form, `STR$`/`VAL`, `HEX$`/`OCT$`, `\`, `MOD`, bitwise operators |
| `09-data-and-read` | `DATA` in all three integer forms, `READ`, `RESTORE` |
| `10-input-driven` | `INPUT` field splitting, `LINE INPUT` |
| `11-print-using` | the `PRINT USING` format language |
| `12-bar-chart` | a whole program: `DIM`, `DATA`, scaling, and a drawn chart |

## Where the rules come from

Every behaviour these programs rely on is specified in `spec/`, and every
clause there cites a page of the NEC reference manual. When a program here
and the manual disagree, **the manual is right** — see `spec/sources.md` for
what each source is and how far it is trusted. A secondary source describing
a different machine in the same family is useful for orientation and is not
evidence about this dialect.
