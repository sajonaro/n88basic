#!/usr/bin/env python3
"""spec_staleness.py — report clauses whose prose leans on a fact elsewhere.

This repo's most-repeated defect is a clause status that rests on a fact
about some OTHER part of the system. Nothing re-derives such a status when
that fact moves, and every instance so far was found by luck:

    GFX.PAINT      implemented because tiling was out of scope; scope moved.
    STR.VAL        partial blaming a lexer that had long since learned octal.
    SCREEN.WIDTH   partial for want of a WIDTH the writer did not track --
    PRINT.BASIC      one change freed three clauses and none announced it.
    PRINT.TAB
    SCREEN.COLOR   refusing behaviour "out of scope" against a boundary
    SCREEN.BASIC     spec.md never actually drew.
    OP.LOGICAL     partial because "XOR, IMP and EQV are not implemented
                   here", written before they were implemented.

docs/afk-runs/RESUME-HERE.md has carried the grep for this since the second
occurrence. Keeping it there, as a thing to remember to run, is what this
module fixes: a check nobody runs finds nothing. It runs on every
check_spec.py invocation instead.

ADVISORY, NEVER A GATE. A hit is not a defect: "no text screen" is a true
and stable fact about this interpreter, and a clause may recount an expired
excuse deliberately as history (SCREEN.BASIC does). The check cannot tell
those from a live stale excuse, because the difference is whether the fact
still holds, which only a reader knows. So it reports and never changes the
exit code -- the same contract as scope-coverage. A gate here would be
noise, and a noisy gate gets ignored, which would cost more than it saves.

ONE CONVENTION KEEPS IT SHARP: when a clause recounts an excuse that has
since expired -- and several usefully do, because the history is why the
status moved -- describe the old reason rather than quoting its wording. A
clause narrating "it said X was out of scope" trips this scan forever after,
and a scan whose hits are mostly history is one people stop reading.
OP.PRECEDENCE and SCREEN.BASIC were both reworded for exactly this, and the
four hits that remain are all live facts: three clauses rest on there being
no text screen, one on there being a single graphics page. If either ever
changes, this names what to re-read.

Usage: called from check_spec.py; see run_checks there.
"""

from __future__ import annotations

import re
from typing import Any

# Phrasings that mark a justification pointing at a DIFFERENT part of the
# system. Each earns its place by having actually hidden a defect here; this
# is not a general "suspicious words" list, and it should not grow into one.
#
#   out of scope / not implemented here  - GFX.PAINT, SCREEN.COLOR, OP.LOGICAL
#   does not track|support|read          - SCREEN.WIDTH and the two it froze
#   does not enforce|check|validate      - DATA.BASIC, whose partial opened
#                                          "does not enforce the 255-byte line
#                                          limit" for a day after PROG.LINE-
#                                          LENGTH began enforcing exactly that.
#                                          The verb was outside this pattern's
#                                          vocabulary, so the scan stayed quiet
#                                          on the one clause it existed to
#                                          catch. Widened rather than left to
#                                          luck: the shape is "we do not do X",
#                                          and the verb is incidental.
#   cannot yet / the lexer               - STR.VAL
#   no text screen / one page            - the SCREEN family's standing facts
#   known to diverge                     - OP.PRECEDENCE, whose partial cited
#                                          divergences in other clauses that
#                                          were fixed without it noticing
#   is|are deferred                      - GFX.POINT, whose [1] POINT returns
#                                          the same numbers for world and
#                                          screen coordinates BECAUSE WINDOW
#                                          is deferred. Correct today and
#                                          cited (printed p.161), and wrong
#                                          the moment WINDOW lands. Note it
#                                          is an *implemented* clause resting
#                                          on a fact elsewhere -- the same
#                                          shape as GFX.PAINT, which is the
#                                          most dangerous kind, since nothing
#                                          about its status looks unfinished.
EXCUSE_RE = re.compile(
    r"out of scope"
    r"|not implemented here"
    r"|does not (?:track|support|read|enforce|check|validate)"
    r"|cannot yet"
    r"|the lexer"
    r"|no text screen"
    r"|one page"
    r"|known to diverge"
    r"|(?:is|are) deferred",
    re.I,
)


def check_stale_excuses(clauses: list[Any]) -> list[str]:
    """Check 11 (advisory, never fails): clauses justified by a fact elsewhere.

    Returns report lines. The caller must not let these affect the exit code.
    """
    hits: list[tuple[str, str, str]] = []
    for c in clauses:
        if not isinstance(c, dict):
            continue  # already reported by check_parses
        text = c.get("text")
        if not isinstance(text, str):
            continue
        m = EXCUSE_RE.search(text)
        if m:
            hits.append((str(c.get("status")), str(c.get("id")), m.group(0)))

    if not hits:
        return ["STALE-EXCUSE stale-excuse-scan: no clause leans on a fact elsewhere"]

    lines = [
        f"STALE-EXCUSE stale-excuse-scan: {len(hits)} clause(s) justified by a fact "
        "about another part of the system — re-read each and ask whether that fact "
        "still holds (a hit is not itself a defect):"
    ]
    for status, cid, phrase in sorted(hits, key=lambda h: (h[1])):
        lines.append(f"  {status:12} {cid:22} ← {phrase!r}")
    return lines
