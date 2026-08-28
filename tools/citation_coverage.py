#!/usr/bin/env python3
"""citation_coverage.py -- which pages of the manual's prose no clause cites.

WHY THIS EXISTS, AND WHY coverage.py CANNOT DO IT. coverage.py measures
clauses against clauses: how many are implemented, how many carry a
conformance case. That is blind to a rule with no clause at all. Until
2026-08-17 the entire operator chapter (chapter 2 section 10, printed
pp.19-25) was cited by exactly ONE clause, for one rule on p.20 -- and that
is *why* six silent arithmetic bugs survived: the evidence discipline binds a
clause to a page, so with no clause nothing ever required anyone to read the
precedence table, and no clause could be wrong about precedence because none
existed. "101 of 101 clauses have a conformance case" and "a whole chapter is
unspecified" were true at the same moment.

So this asks the complementary question, from the other direction: walk the
MANUAL and find the pages nothing points at.

SCOPE: chapters 1 and 2 only, printed pp.3-31 -- the prose and syntax
chapters. Chapter 3 is the alphabetical keyword reference, and coverage.py
already checks every in-scope keyword has an entry citing its page, so
sweeping it here would duplicate that. Chapters 1-2 are the part nothing
else looks at.

GRANULARITY, stated because it is a real limit rather than an oversight:
citations name pages, so pages are the finest this can resolve. Chapter 2's
sections 1, 2 and 3 all sit on printed p.9, and 8 and 9 share p.17 -- a
citation to either page cannot say which section it was about. Uncited PAGES
are therefore what this reports, annotated with whichever sections cover
them. A cited page is weak evidence that its sections are covered; an
uncited page is strong evidence that they are not.

The section map below was read off the manual's own table of contents at
PDF pp.4-6 -- the *real* one. Note it is not the functional index at PDF
pp.9-13, which lists keywords only: chapter 2's syntax sections appear in
neither the functional index nor anywhere else, which is exactly how section
13 (label names) went unfound until someone searched the wrong index.

Usage:
    python3 tools/citation_coverage.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (chapter, section label, title, first printed page, last printed page).
# End pages are derived from where the next section starts, so a section
# sharing a page with its neighbour is recorded as covering that one page.
SECTIONS: list[tuple[int, str, str, int, int]] = [
    (1, "1", "ROM mode and DISK mode BASIC", 3, 3),
    (1, "2", "the main features of N88-BASIC(86)", 3, 3),
    (1, "3", "BASIC's operating modes (direct and program)", 4, 6),
    (2, "1", "statements", 9, 9),
    (2, "2", "lines", 9, 9),
    (2, "3", "line numbers", 9, 9),
    (2, "4", "usable characters and special symbols", 10, 11),
    (2, "5", "constants (string, numeric, integer, real, single, double)", 12, 13),
    (2, "6", "variables and variable types", 14, 14),
    (2, "7", "array variables", 15, 16),
    (2, "8", "reserved words", 17, 17),
    (2, "9", "type conversion", 17, 18),
    (2, "10", "expressions and operators", 19, 25),
    (2, "11", "files, file descriptors, file numbers", 25, 27),
    (2, "12", "interrupts", 28, 28),
    (2, "13", "label names", 29, 29),
    (2, "14", "error messages", 30, 31),
]

# The pages the prose chapters actually occupy: the union of the ranges
# above, NOT a contiguous span. Chapter 2 ends on printed p.31 and chapter 3
# opens on p.35; the leaves between are the chapter divider and its blank
# backs, which carry no folio at all. An earlier version derived the end of
# SS14 from "chapter 3 starts at 35" and so reported pp.32-34 as three
# uncited pages that do not exist -- phantom gaps in a tool whose whole
# purpose is finding real ones.
#
# IT HAPPENED AGAIN, at the other end, and was found on 2026-08-28 only
# because someone went to read the pages: ch1 SS3 was recorded as ending at
# printed p.8 because chapter 2 starts at p.9. It ends at printed p.6. PDF
# p.20 carries folio 6, PDF p.21 is the chapter 2 divider with no folio at
# all, and PDF p.22 carries folio 9 -- so printed pp.7-8 do not exist, and
# this tool reported two uncited pages that are not pages. The end of a
# section CANNOT be derived from where the next one starts; it has to be
# read off the last page the section actually occupies.
PROSE_PAGES = sorted({p for (_, _, _, lo, hi) in SECTIONS for p in range(lo, hi + 1)})

# "ref-9801 printed p.51 / PDF p.62" and "ref-9801 printed p.122-123 / ..."
PRINTED_RE = re.compile(r"printed pp?\.\s*(\d+)(?:\s*-\s*(\d+))?")


def cited_pages(doc: dict, field: str = "source") -> dict[int, list[str]]:
    """Every printed page any clause cites, mapped to the clauses citing it."""
    pages: dict[int, list[str]] = {}
    for c in doc["clauses"]:
        src = c.get(field)
        if not isinstance(src, str):
            continue
        for m in PRINTED_RE.finditer(src):
            lo = int(m.group(1))
            hi = int(m.group(2)) if m.group(2) else lo
            for p in range(lo, hi + 1):
                pages.setdefault(p, []).append(str(c.get("id")))
    return pages


def sections_covering(page: int) -> list[str]:
    return [
        f"ch{ch} §{num} {title}"
        for (ch, num, title, lo, hi) in SECTIONS
        if lo <= page <= hi
    ]


def main() -> int:
    doc = json.loads((ROOT / "spec" / "clauses.json").read_text())
    pages = cited_pages(doc)

    uncited = [p for p in PROSE_PAGES if p not in pages]
    covered = len(PROSE_PAGES) - len(uncited)

    print(
        f"CITATION-COVERAGE chapters 1-2 (printed pp.{PROSE_PAGES[0]}-{PROSE_PAGES[-1]}): "
        f"{covered} of {len(PROSE_PAGES)} pages cited by at least one clause"
    )

    if not uncited:
        print("  every page of the manual's prose chapters is cited.")
        return 0

    print()
    print("Pages no clause cites, with the sections that cover them:")
    for p in uncited:
        secs = sections_covering(p) or ["(no section recorded)"]
        print(f"  printed p.{p:<3} {secs[0]}")
        for extra in secs[1:]:
            print(f"{'':16}{extra}")

    print()
    print("A hit is not a defect. Some of this prose is narrative, and some")
    print("describes features deliberately out of scope. It is a reading list:")
    print("read the page and ask whether it states a rule this interpreter")
    print("should obey and no clause records.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
