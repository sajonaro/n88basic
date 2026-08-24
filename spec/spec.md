# N88-BASIC(86) — specification

**Version 0.1.0** · 2026-08-16

The language implemented by `n88basic`: N88-BASIC(86), the ROM BASIC of the NEC
PC-9801.

This version fixes **scope** and **sources**. The clause bodies — the rules
themselves — are written subsystem by subsystem in later versions, in the order
given in §6.

---

## 1. What this document is

A statement of what N88-BASIC(86) does, written from the reference manuals listed
in §5, in our own words.

It describes one dialect on one machine. PC-8801 N88-BASIC and the MS-DOS
N88-日本語BASIC(86) are different languages for this purpose; where a source
about either is used, §5 says what that is worth.

It is a specification, not a notebook. It states rules. It does not record how
we came to know them, argue with itself, or track what has been built —
provenance lives in `clauses.json`, implementation status lives there too, and
neither belongs in the prose.

## 2. Conventions

**Clause identifiers.** Every rule has a stable dotted identifier —
`PRINT.USING.OVERFLOW`, `NUM.DIV-BY-ZERO`. Identifiers do not change when the
document is reorganised, and are never reused for a different rule. Tests and
the editor bind to them.

**Clause families.** A clause id's first segment names the family it belongs to.
Most are keyword-shaped — `NUM`, `STR`, `CTRL`, `GFX`, `PRINT`, `SCREEN`, `DATA`,
`ERR`, `IN`, `PROG` — because most rules are about one keyword. `OP` is not: it
holds the operator chapter (§10, printed pp.19-25), whose rules are about how
expressions combine rather than about any keyword. That chapter went unmodelled
precisely because no keyword-shaped family could hold it, and nothing therefore
required anyone to read its precedence table — two silent wrong answers in
ordinary arithmetic survived there until 2026-08-17. A rule that fits no family
is a rule nothing will check.

**Companion data.** Three files carry the same content in machine-readable form:

| File | Contents |
| --- | --- |
| `keywords.json` | each keyword: kind, syntax, one-line summary, governing clauses |
| `clauses.json` | each clause: evidence grade, source and page, implementation status |
| `errors.json` | each error: number, message, meaning, governing clause, source and page |

**Evidence grades**, recorded per clause in `clauses.json`:

| Grade | Meaning |
| --- | --- |
| `manual` | stated by a PC-9801 source |
| `inferred` | our conclusion, from a PC-8801 source or from reasoning |
| `unspecified` | no source states it; the choice made here is recorded as ours |

`unspecified` is used rather than avoided. A recorded gap is worth more than an
invented certainty.

**Status lags the code, deliberately.** A clause may not leave `absent` without
naming its evidence and the page it was read from. So a keyword the interpreter
implements and tests can still sit at `absent` while nobody has read its page —
the status describes what has been *established*, not what happens to run.
Reading `absent` as "not implemented" understates the interpreter;
`tools/coverage.py` lists such clauses separately for that reason.

## 3. Scope

### 3.1 In scope

The interpreter executes these. Everything listed here is specified in this
document and covered by conformance tests.

**Program structure and declaration**
`LET` · `REM` and `'` · `END` · `STOP` · `CLEAR` · `OPTION BASE` · `DIM` ·
`ERASE` · `SWAP` · `DEF FN` · `DEFINT` · `DEFSNG` · `DEFDBL` · `DEFSTR`

**Control flow**
`GOTO` · `GOSUB` · `RETURN` · `IF` / `THEN` / `ELSE` · `FOR` / `NEXT` ·
`WHILE` / `WEND` · `ON…GOTO` · `ON…GOSUB`

**Error handling**
`ON ERROR GOTO` · `RESUME` in all three forms · `ERROR` · `ERR` · `ERL`

**Data**
`DATA` · `READ` · `RESTORE`

**Input**
`INPUT` · `LINE INPUT`

**Output**
`PRINT` · `PRINT USING` · `WRITE` · `TAB` · `SPC` · `POS` · `CSRLIN` ·
`LPRINT` · `LPRINT USING`

`LPRINT` and `LPRINT USING` format exactly as their screen counterparts and are
directed to a printer stream the caller supplies. No printer device is driven.

**Numeric functions**
`ABS` · `SGN` · `INT` · `FIX` · `SQR` · `SIN` · `COS` · `TAN` · `ATN` · `LOG` ·
`EXP` · `RND` · `RANDOMIZE` · `CINT` · `CSNG` · `CDBL`

**String functions**
`LEFT$` · `RIGHT$` · `MID$` as function and as statement · `LEN` · `INSTR` ·
`STRING$` · `SPACE$` · `CHR$` · `ASC` · `VAL` · `STR$` · `HEX$` · `OCT$`

**Types and arithmetic**
Integer, single precision, and double precision; the suffixes `%`, `!`, `#`;
coercion between them; overflow; division by zero; and the rules governing how a
number is displayed — significant digits, exponent form, and the spacing `PRINT`
places around a numeric value.

**Text screen**
`SCREEN` · `WIDTH` · `CLS` · `LOCATE` · `COLOR` · `CONSOLE` · `KEY OFF`

**Graphics**, on the 640×400 display
`PSET` · `PRESET` · `LINE`, including its `,B` and `,BF` forms · `CIRCLE` ·
`PAINT` · `POINT`

Graphics are in scope because programs of this era plot their results. A
numerical program whose chart cannot be drawn is only half run.

### 3.2 Deferred

Part of the language and intended eventually, but not specified or implemented
until something needs them.

| | Reason |
| --- | --- |
| `VIEW` · `WINDOW` | coordinate transformation, meaningful only once plotting is exercised |
| `GET` · `PUT` (graphics) | sprite capture and replay |
| `DRAW` | a macro language of its own, worth its own treatment |
| `INKEY$` | interactive keyboard polling, a different input model from `INPUT` |
| `DATE$` · `TIME$` | ambient state, which makes a program's output irreproducible |
| the text screen | a character grid for `LOCATE` to move a cursor on — see below |

**The text screen is deferred as of 2026-08-18, by decision rather than by
omission.** Five clauses were partial for want of it: `SCREEN.LOCATE` entirely,
`SCREEN.CONSOLE` entirely, `SCREEN.WIDTH`'s row count, `SCREEN.COLOR`'s
function code, and the whole of what `CLS 1` means. Each parses, records its
arguments, and states what it does not do, so nothing is silently wrong — a
listing that positions text is told, not quietly mis-drawn.

It is deferred for a reason worth writing down, because "no text screen"
otherwise reads as an oversight, which is exactly how `\` integer division
came to be missing. **This interpreter's output is a stream and a text screen
is a grid, and those are different objects.** `PRINT` writes to stdout in
order, which is a transcript of everything the program ever emitted; a screen
is what is left showing at the end, after a `LOCATE` has moved the cursor
backwards and later text has overwritten earlier text. Eighty-four conformance
cases assert on the transcript. Building the grid means either keeping both —
two answers where the machine had one — or replacing the transcript, and
rewriting every expectation at once produces a suite nobody can review.

**What would justify paying that:** a listing the user actually wants to run
that positions text. None of the book's portable material does. Its one such
program, the animation at book printed p.125, does not port for unrelated
reasons — it reads the PC-8801's text VRAM through `PEEK` (see
`test/programs/README.md`). Revisit this if a real listing needs it; do not
revisit it to make a count go up.

### 3.3 Out of scope

Not specified and not executed. These **parse**, and the interpreter reports
precisely which unsupported feature a program asked for, so a program using them
still loads and still lints rather than failing at a syntax error.

| Area | Keywords |
| --- | --- |
| Sound | `BEEP` |
| File and device I/O | `OPEN` · `CLOSE` · `PRINT#` · `PRINT# USING` · `INPUT#` · `LINE INPUT#` · `WRITE#` · `INPUT$` · `FIELD` · `GET` · `PUT` · `LSET` · `RSET` · `EOF` · `LOC` · `LOF` · `FPOS` · `KILL` · `NAME` · `FILES` · `LFILES` · `ATTR$` · `DSKF` · `DSKI$` · `DSKO$` · `MKI$` · `MKS$` · `MKD$` · `CVI` · `CVS` · `CVD` |
| Program loading | `LOAD` · `SAVE` · `MERGE` · `CHAIN` · `COMMON` · `BLOAD` · `BSAVE` |
| Machine level | `CALL` · `USR` · `DEF USR` · `DEF SEG` · `PEEK` · `POKE` · `VARPTR` · `INP` · `OUT` · `WAIT` · `FRE` · `MON` |
| Communications | `TERM` · the `COM:` device |
| Kanji handling | `KINPUT` · `KLEN` · `KMID$` · `KINSTR` · `KTYPE` · `KNJ$` · `KEXT$` · `KPLOAD` · `JIS$` · `AKCONV$` · `KACNV$` |
| Hardware and peripherals | `MOTOR` · `PEN` · `COPY` · `LCOPY` · `LPOS` · `KEY <n>,<string>` (function-key definition) · `KEY LIST` · `SET` · `SEARCH` · `MAP` · `ROLL` |
| Advanced graphics | `PICTURE` · `GETPICT` · `MOVETO` · `LINETO` |

**Tile patterns are in scope as of 2026-08-17** and were out of it before. The
tile-string forms of `PAINT`, `CIRCLE`'s `F` and `LINE ,BF` are therefore live
work rather than deliberate omissions: each parses and is refused at run time
today, and each clause records that refusal as unimplemented rather than as a
boundary of this specification.

**Palette mode is in scope as of 2026-08-17**, and was never out of it in
writing. Two clauses — `SCREEN.COLOR` and `SCREEN.BASIC` — refused behaviour by
citing a palette-mode boundary this document did not draw anywhere: the word
appeared nowhere in it, and §3.3's table never named `COLOR`. An unwritten
boundary is not a scope decision, it is an assumption wearing one's clothes, and
it had already excused a missing range check on `SCREEN`'s page numbers. So
`[1] COLOR`'s palette-mode slot, the `[2] COLOR` form that reassigns what RGB a
palette number displays, and the mode-dependent argument ranges are live work.

Elsewhere "palette number" is simply the manual's term for a colour index, and
those clauses are unaffected.

**`\` integer division is in scope as of 2026-08-18**, completing the ruling
below. It sits at level 6 of the same §10.6 table and is described in the very
same paragraph of printed p.20 as `MOD`, with the same rounding rule, so
excluding it while including its table-mates was no more defensible than
excluding them had been. It was left out of the 2026-08-17 ruling by oversight
rather than decision. Unlike the four below it failed *loudly* meanwhile — the
backslash did not lex at all, so a listing using it was refused rather than
quietly computing something else, which is why nothing was ever silently
wrong. See `OP.INTDIV`; the manual prints the operator as `¥` because on a
PC-9801 the byte `0x5C` is drawn that way, and it is the same byte an ASCII
backslash occupies in a file today.

**`MOD`, `XOR`, `IMP` and `EQV` are in scope as of 2026-08-17**, and were never
out of it in writing either. All four sit in the manual's own operator
precedence table (printed p.25 / PDF p.38, §10.6) at levels 7, 13, 14 and 15,
alongside `AND`, `OR` and `NOT` at 11, 12 and 10 — which this document has
always specified. Excluding four table-mates while including the other three
was never a decision anyone recorded; the four simply went unimplemented and
unmentioned.

What made that a defect rather than a gap is §3.3's own contract above: an
unsupported feature must **parse**, and the interpreter must report precisely
which unsupported feature the program asked for. These did neither. The lexer
does not reserve the words, so each one silently became an ordinary variable
worth zero — `PRINT 7 MOD 3` printed ` 7  0  3`, three items rather than one
remainder, and `MOD = 9` assigned to a variable named `MOD`. A program using
them produced wrong numbers with no diagnostic pointing anywhere near the
cause.

The fifth member of that table, `¥` (integer division, level 6 — the character
a Japanese keyboard prints where a `\` is typed), is also unimplemented and
stays out of scope for now. It is the one member of the family that does not
violate the contract: the lexer has no such token at all, so it fails loudly
with `Unexpected character` rather than quietly becoming a variable. It is a
gap, not a defect.

**Editing and direct-mode commands** — `AUTO` · `LIST` · `LLIST` · `DELETE` ·
`RENUM` · `NEW` · `RUN` · `CONT` · `EDIT` · `TRON` · `TROFF` · `HELP` — are not
interpreter features. They belong to the environment that hosts a program, and
the ones worth having are provided by the VSCode extension instead: renumbering
as a refactor, listing as the buffer itself.

### 3.4 What "in scope" commits to

For every keyword in §3.1: a clause stating its syntax and its behaviour, an
entry in `keywords.json`, at least one conformance test where the behaviour is
testable, and an evidence grade naming what the claim rests on.

The inventory above is drawn from the reference manual's contents, cross-checked
against the command index listed in §5. A keyword appearing in neither is a gap
in our sources, not evidence that the language lacks it.

## 4. Reproduction

Written in our own words from the sources in §5. No manual text is reproduced or
translated, and no example programs, figures, or tables are copied.

Keywords, syntax, error numbers and messages, and numeric constants are facts
about a programming language and are stated directly.

## 5. Sources

Referenced by name and link. Nothing from them is reproduced here.

**Primary — PC-9801, N88-BASIC(86)**

- [N88-BASIC(86) Reference Manual](https://archive.org/details/N88BASIC86Manual)
  — NEC, 1982
- [PC-9801 N88(86)BASIC command index](http://www.openspc2.org/BASIC/HTML/PC-9801%5BN88(86)BASIC%5D.html)
  — openspc2.org. A list of identifiers, used to check the inventory for gaps

**Secondary — PC-8801, a different machine**

Used only where a PC-9801 source is silent, and any clause resting on one is
graded `inferred`.

- [PC 8801 N 88 BASIC入門](https://archive.org/details/PC8801N88BASIC)
- [PC‐8801 N88‐BASIC解析マニュアル 川村清](https://archive.org/details/PC-8801N88-BASIC)
  — a third-party analysis of the interpreter's internals, which documents
  runtime behaviour reference manuals omit

`sources.md` gives each source a citation key, records what it is worth, its
page maps and the limits of those maps, and retrieval dates, so any citation in
the companion data can be checked against the page it came from. It records no
local paths: the scans are read locally but are neither committed nor
redistributed, and a citation names the archive.org item, never a file.

## 6. Order of work

Clause bodies are written in this order, because each rests on the one before.

1. **Types and arithmetic**, then number display. Nothing else can be verified
   until a program's output can be compared byte for byte.
2. **Control flow.**
3. **Errors**, with the error-number table.
4. **String and numeric function libraries.**
5. **Output**, including `PRINT USING` in full.
6. **Text screen**, then **graphics.**

Each raises the minor version. The version stands at 0.x until coverage is broad
enough to claim otherwise.
