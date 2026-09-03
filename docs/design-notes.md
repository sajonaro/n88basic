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

PNG encoding is written here — deflate with fixed Huffman codes and LZ77, CRC-32 and
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

**A fixture that captures stdout cannot see an interactivity bug.** For five
releases `n88` did not flush stdout before blocking on `INPUT`, so a prompt
appeared only after the user had typed — they were typing blind into something
that looked hung. Every check here passed, and correctly: the bytes were never
wrong, and redirecting stdout to a file produced a perfect file. Capturing
stdout is *precisely* the case where full buffering is right, so no fixture
this project owns could have caught it. The defect was in *when* the bytes
arrived, and the only observer who can see that is a person at a terminal.
`tools/check_interactive_flush.sh` therefore measures rather than compares:
it supplies input three seconds late and asserts the prompt is already there.
When a property is temporal, a byte comparison is not a weak test of it — it
is not a test of it at all.

**Behaviour that is correct by accident is what the next improvement removes.**
Every other case in these notes is about finding something wrong. This one is
about something *right* whose rightness nobody has recorded, which is a latent
regression waiting for a plausible refactor. A downstream consumer's prompt
isolated variables across `RUN` exactly as printed p.138 requires — not because
anyone had read the page, but because each `RUN` spawned a fresh process and
the isolation fell out of the architecture. Sharing state between the prompt
and `RUN` is precisely the change a later reader would make as an obvious
enhancement, and it would have been a regression against a rule nobody knew
existed. The fix is not a test, which pins the behaviour without the reason;
it is writing down that the behaviour is load-bearing and which page requires
it. Ask it of code that works and you don't know why: **is this correct, or is
it correct by accident and undefended?**

**A test can pin an assumption about the ENVIRONMENT as firmly as behaviour.**
The extension's Run command shelled `eval $(opam env --switch=.) && dune exec
bin/main.exe` — it built the interpreter from source in the current directory,
so it worked in a checkout of this repository and nowhere else. The published
extension's primary action could not run anything for anyone who had merely
installed it. Its test asserted that exact command line and passed, because the
assertion was true: the command *was* what the code produced. What the test
never asked was whether the machine it described was the user's. Blast radius
is the thing to weigh here — this was correct behaviour on one machine, in the
one place a reader would never think to check, for as long as nobody outside
had the extension. When a test pins a command, a path or a toolchain, ask
whether it also pins a machine.

**An automated signal that nobody reads is not a check.** `citation_coverage.py`
had been reporting printed pp.4–8 as uncited on every run for eleven days.
Direct mode — a whole documented operating mode of the language — was in there,
and was implemented only when someone went and read the pages the tool had been
naming. Every other failure in these notes is a question that was never asked;
this one is a question that was asked, answered, printed, and skipped. A tool
that reports into a void is a tool nobody has to disagree with. Read what the
tools already say before adding one that says something new.

**A grep hit is not a citation.** This whole project rests on clauses that
name a page, and `tools/check_spec.py` can verify that a page is named but
never that anyone read it. A hollow citation is indistinguishable from a real
one by any mechanical check, so the discipline has to hold at the point of
writing: open the page, and quote the line rather than summarising what a
search result appeared to say. A reader once reported a feature missing here
on the strength of a grep hit in a spec file that, read in full, said the
opposite — the correcting evidence was on their own disk, unopened.

**When the diagnosis is "feature missing", check the SPELLING first.** A
wrong syntax and an absent feature are indistinguishable from outside: both
give you no output and no error worth the name. `PRINT USING`'s string fields
were reported unimplemented when they were only being written `\...\`, the
Microsoft form, rather than the `&...&` this dialect uses — `\` being taken
here as integer division. Confirm the construct exists under the name the
manual gives it before reading any implementation.

**A difference from a secondary source is a question, not a defect.** Where
a source describing a different machine in the same family disagrees with the
PC-9801 manual, the manual is right. Changing correct code to match the other
machine is a regression wearing the clothes of a fix.
