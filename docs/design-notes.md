# Design notes

Decisions that still constrain the code, and the reasoning behind them. Kept
because re-deriving any of these costs more than reading them.

## The specification is the primary artifact

The interpreter is checked against a written, cited description of the
dialect rather than against itself. The rule that makes this work is that no
clause may exist without naming the manual page it came from, enforced by
`tools/check_spec.py`.

The reason is specific. A specification written by describing what the code
does cannot disagree with the code, so it can never find a bug in it. Several
defects here were found by reading a page and noticing the interpreter said
otherwise, and would not have been found any other way. The same applies to
tests: a conformance case written from observed output proves the interpreter
does what it did yesterday, never that yesterday was right.

Where the manual is silent the interpreter still has to do something, and
those choices are marked in the clause as the project's own. Keeping that
line visible matters: an out-of-range `SCREEN` mode raising `Illegal function
call` is a decision, while the operator precedence table is a fact.

## Coverage measures two different things, and needs two tools

`tools/coverage.py` measures clauses against clauses — how many are
implemented, how many carry a conformance case. It is structurally blind to a
rule that has no clause at all.

That blindness had a cost. The manual's operator chapter was once cited by a
single clause, so nothing ever required anyone to read the precedence table,
and six arithmetic operators were silently wrong: `-2^2` gave 4, `12 AND 10`
gave -1, and every integer base with a negative exponent gave 0. "Every
clause has a conformance case" and "a whole chapter is unspecified" were true
at the same moment.

`tools/citation_coverage.py` asks the complementary question from the other
side — which pages of the manual no clause cites — and reading its output has
since found unenforced line-number and line-length limits, label rules that a
clause claimed did not exist, and a variable-aliasing bug.

## The graphics pipeline is a pure function

`basic/` never touches a pixel. The interpreter appends to a display list;
`raster/` turns that list into a framebuffer and then into PNG bytes. Same
list in, identical bytes out.

`POINT` is the one place that reads state back, and it does so through a
handler the caller supplies, so `basic/` still never sees a framebuffer. The
same shape serves `PAINT`'s "is this point inside the window" question and
the LP that `POINT(n)` reports.

PNG encoding is written here — deflate with stored blocks, CRC-32 and
Adler-32 — so the interpreter has no image-library dependency.

## The framebuffer stores palette numbers, not colours

Every colour given to the graphics screen is given *through* the palette, so
what a drawing operation writes is a palette number and the colour it shows
is a display-time lookup. Reassigning a palette therefore recolours what is
already on screen, without redrawing it.

An RGB framebuffer cannot express that, because the pixel no longer knows
which palette drew it. Storing the index is also the faithful model of the
hardware, whose graphics screen is bit planes.

This is why `POINT` is a direct read rather than a reverse lookup from a
colour, and why `PAINT`'s border test compares palette numbers: two palettes
showing the same colour are still distinct borders.

## One reader for text-to-number, and one for number-to-text

Three separate defects came from having more than one piece of code that
turns text into a number, each written to its own idea of what a numeric
constant looks like:

- `VAL` read decimal and hexadecimal but not octal or exponent forms.
- `DATA` had its own item scanner that knew no radix forms at all, so
  `DATA &HFF` became the string `"&HFF"` and failed at the `READ` that
  consumed it — blaming the wrong line.
- `INPUT` parsed typed fields with OCaml's `float_of_string`, which is not a
  BASIC reader: it accepted `1_000`, `0x10`, `nan` and `inf`, and rejected
  `1D3`, a constant the manual defines.

They now share one whole-field reader. If a fourth site ever needs to parse a
number, it should use that one rather than grow another.

The same caution applies in the other direction. `PRINT`, `STR$` and
`PRINT USING` all render numbers; the first two share a formatter and agree
exactly, which is what makes `STR$` definable as "what `PRINT` would write".

## Deciding on rendered digits, not on stored floats

`PRINT` falls back to exponent form for very small magnitudes. That floor is
the project's own — the manual names none — but where the question was asked
mattered: comparing the stored float against `0.01` misfired exactly at its
own boundary, because a listing writing `.01` produces the single-precision
value `0.00999999977`, which is not `>= 0.01`. `PRINT .01` printed `1E-02`.

The test now reads the digits about to be printed rather than a float that
rounds just below a literal written in decimal. Any threshold expressed as a
comparison against a decimal literal has this hazard.

## Text output is a stream, and a text screen would be a grid

`LOCATE`, `CONSOLE`, `CLS 1` and `WIDTH`'s row count parse and record their
arguments but act on nothing, because there is no character grid.

Building one is not a small addition, and the reason is worth keeping.
`PRINT` writes to standard output in order, which is a transcript of
everything a program emitted. A screen is what is left showing after a
`LOCATE` moved the cursor back and later text overwrote earlier text. Those
are different objects, and most of the conformance suite asserts on the
transcript. Building the grid means either keeping both — two answers where
the machine had one — or replacing the transcript and rewriting every
expectation at once.

Worth doing when a program someone actually wants to run needs it. Not worth
doing to make a count go up.

## Practices that repeatedly paid for themselves

**Break a check before trusting it.** A test that has never been watched
failing is not yet evidence. Removing the behaviour and confirming the check
goes red has caught bad checks repeatedly here, including tests that passed
under a deliberately broken implementation because the value they asserted
was one the broken version also produced. Confirm the broken build actually
compiled: a build error looks like a passing run.

**Name the distinguishing input before changing a semantics.** A correct,
thorough, green suite says nothing about a rule whose distinguishing input it
never supplies. Making the logical operators bitwise broke no test, because
relational operators yield only 0 and -1, and on exactly those two values
bitwise and boolean agree. Prefer an input the manual itself supplies.

Then **check that the distinguishing input actually distinguishes** — an
input asserted to separate two readings, and never verified to, is the same
failure one level up. `221.875` and `2.675` were both offered as separating
half-up from half-to-even and neither does: the first is a tie whose
preceding digit is odd, so both rules round it up, and the second is not a
tie at all. The ties that separate them have an EVEN preceding digit
(`0.125`, `0.625`, `2.5`).

**Test the input a real program produces, not the convenient one.** The
sharper form of the practice above, and the one that has actually recurred.
A suite tends to be written from the value that is easiest to type, and the
easiest value is often the one that does not exercise the rule. Every numeric
display case here printed a *constant*, so the corpus was green and silent on
what happens when a value arrives in a *variable* — which is single precision
by default, prints in exponent form past six digits, and is the only path a
real listing takes. The same shape appeared in `PRINT USING`: the rounding
cases used values that were not ties, so the half-up rule went unpinned by
anything that could tell it from half-to-even. Both were found by asking one
question of an existing green suite: *what value does a real program actually
hand this code, and does any case supply it?*

**A conclusion outlives its grounds.** A status resting on a fact about some
other part of the system does not re-derive itself when that fact moves.
`tools/check_spec.py` scans clause prose for that shape and lists what to
re-read. It cannot catch everything — it once stayed silent on the clause it
existed to catch, because the clause used a verb the pattern did not know.

**A difference from a secondary source is a question, not a defect.** Where
a source describing a different machine in the same family disagrees with the
PC-9801 manual, the manual is right. Changing correct code to match the other
machine is a regression wearing the clothes of a fix.
