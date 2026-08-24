# n88basic

A small interpreter for N88-BASIC(86), written in OCaml with no dependencies.

## Use

    dune exec bin/main.exe -- program.bas

(`n88basic program.bas` once the interpreter is packaged for opam — see
`bin/dune` for why the executable is not yet named `n88basic` on disk.)

Exit codes: 0 success, 1 a BASIC error (every parse error is reported, one per
line, on stderr; a runtime error stops the program and is reported the same
way), 2 a usage or file error.

## What it supports

Statements: `LET` (explicit or implicit), `PRINT`/`LPRINT` (with `,` and `;`
separators and `TAB(n)`), `PRINT USING`/`LPRINT USING`, `INPUT`, `FOR`/`NEXT`
with `STEP`, `IF`/`THEN`/`ELSE`, `GOTO`, `GOSUB`/`RETURN`, `DIM`,
`DATA`/`READ`/`RESTORE`, `DEF FN`, `REM` (or `'`), `END`, `STOP`, and the
screen/graphics statements `SCREEN`, `WIDTH`, `CLS`, `KEY OFF`, `LOCATE`, and
`LINE`. Functions: `ABS`, `INT`, `SQR`, `SGN`, `SIN`, `VAL`, `LEFT$`, `CHR$`,
plus user-defined functions via `DEF FN`. Operators: `+ - * / ^`, the
relational operators (both character orders — `>=`/`=>`, `<=`/`=<` — are
accepted), and the logical operators `AND`, `OR`, `NOT`. Statements are
separated by `:`; every line needs a line number.

The target dialect is N88-BASIC(86), the ROM BASIC of the NEC PC-9801. See
`../spec/spec.md` for the specification this interpreter implements, and
`../spec/clauses.json` for the coverage and evidence grade behind each rule.

Deliberately faithful behaviours: a variable name may be up to 40 characters
(letters, digits, periods, letter-first), is case-insensitive, and may contain
a reserved word (`TOTAL`, `LINEAR`, `FORM`, `ANDY`, `IFS` are all ordinary
names) as long as it is not *exactly* one -- see `spec/spec.md`
PROG.VARIABLE-NAMES. A reserved word is recognised only where a delimiter
(space, quote, `#`, colon, or other punctuation) sets it off on both sides, so
`FORI=1TO10` is the single identifier `FORI`, `=`, `1`, and the identifier
`TO10` -- not, as classic Microsoft BASICs read it, `FOR I = 1 TO 10`; unspaced
keyword runs are consequently not supported. Comparisons yield -1 for true and
0 for false; `DIM A(3)` allocates subscripts 0 through 3; `PRINT` puts a
leading space on non-negative numbers and a trailing space on every number, and
a comma advances to the next 14-column zone.

The screen and graphics statements are recorded into a display list rather
than drawn — a renderer is a separate project.

## Use as a library

    (libraries n88basic)

    let () =
      match N88basic.Interp.run_source ~write:print_string "10 PRINT 1\n" with
      | Ok () -> ()
      | Error e -> prerr_endline (N88basic.Error.to_string e)

The interpreter performs no I/O of its own: `~write` receives output, and the
optional `~input` supplies `INPUT` responses, `~printer` gives `LPRINT` a
sink separate from `PRINT` (they share `~write` by default), and `~on_draw`
receives the screen and graphics statements as they run. That is what makes
it testable.

`Program.of_source` parses a whole source string up front and always returns a
program together with the list of every line that failed to parse — a broken
line is skipped rather than aborting the load, so a caller sees every error
in one pass. `Interp.run` takes an already-parsed `Program.t` and always runs
it; `Interp.run_source` parses first and, if parsing produced any error,
reports the first one without running anything.

## Licence

MIT.
