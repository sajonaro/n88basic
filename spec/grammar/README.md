# `spec/grammar/` — N88-BASIC(86)'s syntax, declaratively

`n88basic.mly` states the language's syntax as a grammar, with every rule
cited to the printed folio it was read from. It is a **spec artifact, not the
parser**. `basic/parser.ml` parses; nothing consumes a parser generated from
this file, and this file does not constrain it.

## Why a real `.mly` and not pseudo-BNF

Because menhir can then check it. A grammar that is only a document can be
quietly ambiguous and nobody finds out; one menhir accepts has been checked
against an actual LR construction.

That is not hypothetical — writing this file, menhir caught two mistakes that
were invisible by eye, and both would have survived into a hand-written BNF
document unnoticed:

- **`expr relop expr` carried no precedence at all.** Menhir takes a
  production's precedence from its last *terminal*, and that production ends
  in a nonterminal. The whole relational level (§10.6's level 9) was silently
  doing nothing. Fixed by writing the six comparisons out.
- **`separated_list(COMMA, option(expr))` derives a bare `SCREEN` two ways** —
  as a list of no slots, and as a list of one empty slot. A real ambiguity in
  the shape shared by `SCREEN`, `LOCATE`, `COLOR`, `CONSOLE` and `CLEAR`, not
  a menhir artefact. Fixed with an `arg_slots` rule that cannot be empty.

A third conflict was a genuine question about the language rather than a
slip: whether `IF A THEN B : C` runs `C` unconditionally. Printed p.80 makes
everything after `THEN` conditional, so an `IF` takes the whole rest of the
line and can only be the last statement on it. The grammar now says so
structurally, which is a better answer than resolving the conflict by
precedence would have been — that would have produced the right parse for the
wrong reason.

## Validating it

    dune build @spec/grammar/runtest

`--strict` turns every shift/reduce and reduce/reduce conflict into an error,
so an ambiguity fails the suite. To see *why* a conflict happened, run menhir
by hand with `--explain` and read the generated `n88basic.conflicts`:

    menhir --explain --strict --unused-tokens --no-code-generation \
      spec/grammar/n88basic.mly

`--no-code-generation` builds the automaton — which is what detects conflicts
— without emitting OCaml. That is why the grammar needs no `%type`
declarations and no semantic actions beyond `{}`.

**menhir is a build-time dependency of this artifact only.** It is invoked as
an ordinary program, not through dune's `(menhir)` stanza, so `dune-project`
needs no `(using menhir ...)` line and nothing else in the build acquires a
menhir dependency. In particular the VSCode extension's zero-runtime-dependency
property is untouched.

## What is deliberately *not* in the grammar

Three parts of the language are settled by the scanner, not by an LR grammar.
Forcing them in would produce something that looks right and is wrong:

| | Why it is lexical |
| --- | --- |
| `DATA`'s operands | Raw text scanned to the end of the statement (printed p.58-59). A datum may contain commas and spaces that are not separators, so it cannot be tokenised as an expression list. |
| `?` as `PRINT` | The scanner reads `?` as `PRINT` and `LIST` expands it back (printed p.125). It is not a distinct syntactic form. |
| Identifiers | Maximal munch against the reserved-word table, which is why `GO TOTAL` is `GO` followed by the variable `TOTAL` and not a two-word `GO TO` (printed p.78). Reserved-word membership is a lexical fact, not a production. |

The 255-byte physical line limit is likewise a lexical bound.

## Citations

Every rule names the printed folio it came from. Folios were **confirmed on
the rendered page** with `tools/folio.py`, never computed: `spec/sources.md`
records that the printed-to-PDF offset drifts from +14 in the front matter to
+8 in the appendices, so arithmetic on it is not evidence. A rule with no
cited syntax box is as ungrounded as a clause with no page and is marked
`UNCITED`.

## What writing it found

Writing the grammar against the manual rather than against `parser.ml` was
the point, and it paid: five places where the interpreter contradicted the
manual, none of which any test had caught, because the tests had been written
from the same misreading as the code.

All five were in the operator chapter, and all five are fixed. `^` binds
tighter than unary minus, so `-2^2` is −4. A run of exponentiations groups to
the left, so `2^3^2` is 64. `NOT` binds looser than the relational operators,
so `NOT 1 = 2` is −1. `AND`, `OR` and `NOT` are bitwise rather than boolean,
so `12 AND 10` is 8. And `MOD`, `XOR`, `IMP` and `EQV` are operators, not
ordinary variable names that silently read as zero.

Each now has a clause in `spec/clauses.json` under `OP.*` and a conformance
case. The reason they had all survived is recorded in `docs/design-notes.md`:
the operator chapter had no clauses at all, so nothing ever required anyone
to read the precedence table.

## If it ever becomes the parser

The grammar is real menhir rather than a sketch, partly to keep that path
open. Taking it would mean adding semantic actions and
`%type` declarations, building the token stream from `basic/lexer.ml`'s
`Token.kind` (keywords arrive as `Keyword "PRINT"`, not as distinct
constructors, so a mapping layer is needed), and handling the three lexical
concerns above outside the grammar as they already are. Nobody is committed
to any of that.
