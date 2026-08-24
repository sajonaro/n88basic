#!/usr/bin/env python3
"""spec_citations.py — the citation page-map check.

Every substantive row in the companion data cites both page numbers: the
printed folio a reader of the book sees, and the page a reader of the scan
turns to. spec/sources.md explains why both are recorded — "the printed
folio and the PDF page are not a constant offset apart... it drifts from
+14 in the front matter down to +8 by the appendices" — and warns against
converting between them with a fixed constant.

That prose states a rule nothing enforced. This module enforces it. Within
one source document the offset (PDF - printed) may fall as the book
progresses, because unnumbered plates only ever push the scan further
ahead of the folio; it may never *rise*. So for any two citations of the
same document, the one on the later printed page must not carry a larger
offset. A citation whose PDF page was mistyped breaks that ordering as soon
as the surrounding corpus brackets its printed page, in either direction:
too large an offset contradicts the earlier pages, too small contradicts
the later ones.

Deliberately self-calibrating: the bands are read off the data rather than
hardcoded, so citing a page in a range nothing has cited yet is not an
error, and the check never has to be edited when a new band is reached.

Scope: a source satisfies the schema by being a non-empty string, so this
check governs only sources written in the page-map form (or visibly
reaching for it). A source citing something with no folio at all -- an
index, a web page -- is not its business and passes untouched.

What this CANNOT do is confirm a citation points at the right page. Only
the folio printed on the page says that, and these scans carry no text
layer to read it from -- use tools/folio.py and read it. This check catches
a citation that contradicts its neighbours, which is a different and
smaller claim.
"""

from __future__ import annotations

import re
from typing import Any

# A source opens with the source key from spec/sources.md, which scopes the
# ordering -- two different books have unrelated pagination -- and is
# followed by one or more page references separated by semicolons. All four
# shapes the data uses today are covered:
#
#   ref-9801 printed p.47 / PDF p.58
#   ref-9801 printed p.12-14 / PDF p.25-27          (a run of pages)
#   ref-9801 printed p.12,14 / PDF p.25,27          (two separate pages)
#   ref-9801 printed p.14 / PDF p.27 (§6.1 変数名); printed p.17 / PDF p.30 (§8 予約語)
#
# so a page list is one or more numbers joined by hyphens or commas, and a
# reference may carry a parenthetical note naming the section it points at.
SOURCE_RE = re.compile(r"^(?P<key>[A-Za-z0-9\-]+)\s+(?P<refs>printed\s+p\..*)$", re.S)
# A source only has to be a non-empty string to satisfy the schema (see
# check_error_entries and check_keyword_syntax_source_invariant); citing both
# page numbers is this project's convention for the scanned books, not a rule
# every source must obey. So a free-form source is left alone, and only one
# that reaches for the page-map form is held to it -- which still catches the
# citation half-written or mistyped on its way to that form.
LOOKS_LIKE_PAGE_MAP = re.compile(r"printed\s+p\.|PDF\s+p\.", re.I)
REFERENCE_RE = re.compile(
    r"^printed\s+p\.(?P<printed>\d+(?:[-,]\d+)*)"
    r"\s*/\s*PDF\s+p\.(?P<pdf>\d+(?:[-,]\d+)*)"
    r"\s*(?:\([^)]*\))?$",
    re.S,
)


def _pages(spec: str) -> list[int]:
    return [int(n) for n in re.split(r"[-,]", spec)]


def _signed(offset: int) -> str:
    """Render an offset with its sign. A transposed PDF page can put the scan
    *behind* the folio, so the negative case is reachable and must not print
    as "+-16"."""
    return f"{offset:+d}"


def _cited_rows(docs: dict[str, Any]) -> list[tuple[str, str, str]]:
    """(where, source, label) for every row carrying a non-empty source.

    keywords.json leaves "source" empty for rows not yet read off a page,
    which check_keyword_syntax_source_invariant governs; an empty source is
    that check's business, not this one's.
    """
    rows: list[tuple[str, str, str]] = []
    for name, key, label_field in (
        ("clauses", "clauses", "id"),
        ("errors", "errors", "number"),
        ("keywords", "keywords", "name"),
    ):
        for i, entry in enumerate(docs.get(key) or []):
            if not isinstance(entry, dict):
                continue  # already reported by check_parses
            source = entry.get("source")
            if not isinstance(source, str) or not source.strip():
                continue
            label = entry.get(label_field)
            where = f"{name}.json: {label}" if label is not None else f"{name}.json[{i}]"
            rows.append((where, source.strip(), str(label)))
    return rows


def check_citation_page_map(docs: dict[str, Any]) -> tuple[bool, list[str]]:
    """Check 10: every citation parses, is internally consistent, and its
    printed-to-PDF offset never rises as the printed page advances.
    """
    issues: list[str] = []
    # source key -> list of (printed page, offset, where)
    by_key: dict[str, list[tuple[int, int, str]]] = {}

    for where, source, _ in _cited_rows(docs):
        if not LOOKS_LIKE_PAGE_MAP.search(source):
            continue
        outer = SOURCE_RE.match(source)
        if not outer:
            issues.append(
                f"{where}: source does not open with a source key and a page reference "
                f"(\"<key> printed p.<pages> / PDF p.<pages>\"), got {source!r}"
            )
            continue
        for ref in outer.group("refs").split(";"):
            m = REFERENCE_RE.match(ref.strip())
            if not m:
                issues.append(
                    f"{where}: page reference does not match "
                    f"\"printed p.<pages> / PDF p.<pages>\", got {ref.strip()!r}"
                )
                continue
            printed, pdf = _pages(m.group("printed")), _pages(m.group("pdf"))
            if len(printed) != len(pdf):
                issues.append(
                    f"{where}: cites {len(printed)} printed page(s) but {len(pdf)} PDF page(s); "
                    "the two lists pair up one-to-one"
                )
                continue
            offsets = {d - p for p, d in zip(printed, pdf)}
            if len(offsets) > 1:
                issues.append(
                    f"{where}: inconsistent offset within one page reference "
                    f"({', '.join(f'p.{p}->PDF p.{d} = {_signed(d - p)}' for p, d in zip(printed, pdf))})"
                )
                continue
            by_key.setdefault(outer.group("key"), []).append(
                (printed[0], offsets.pop(), where)
            )

    for key, rows in sorted(by_key.items()):
        # Walking printed pages upward, the smallest offset seen so far is a
        # ceiling for everything after it: a later page may match it or fall
        # below it, never climb back above.
        ceiling: tuple[int, int, str] | None = None
        for page, offset, where in sorted(rows):
            if ceiling is not None and offset > ceiling[1]:
                issues.append(
                    f"{where}: offset {_signed(offset)} on printed p.{page} rises above "
                    f"{_signed(ceiling[1])} on the earlier printed p.{ceiling[0]} ({ceiling[2]}); "
                    f"within {key} the offset only ever falls (spec/sources.md). "
                    "One of the two PDF page numbers is wrong."
                )
                continue
            if ceiling is None or offset < ceiling[1]:
                ceiling = (page, offset, where)

    return (not issues, issues)
