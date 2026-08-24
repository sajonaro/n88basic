# Sources

Provenance record for `spec/spec.md` §5. Local scans are read to verify facts;
they are gitignored, not committed, and not redistributed. Citations in
the companion data name the source's key and a page number, never a local path.

Retrieval date for all four sources below: **2026-08-16**.

## The four sources

| Key | Source | Link | Machine / dialect | Pages | Good for |
| --- | --- | --- | --- | --- | --- |
| `ref-9801` | N88-BASIC(86) Reference Manual, NEC, 1982 | [archive.org/details/N88BASIC86Manual](https://archive.org/details/N88BASIC86Manual) | PC-9801, N88-BASIC(86) — our target | 207 | Primary source. Syntax, semantics, error messages for the target dialect. |
| `index-9801` | PC-9801 N88(86)BASIC command index | [openspc2.org](http://www.openspc2.org/BASIC/HTML/PC-9801%5BN88(86)BASIC%5D.html) | PC-9801, N88-BASIC(86) | — (HTML list) | Checklist of identifiers, used only to check the §3.1 inventory for gaps. Not cited for behaviour. |
| `intro-8801` | PC-8801 N88-BASIC入門 | [archive.org/details/PC8801N88BASIC](https://archive.org/details/PC8801N88BASIC) | PC-8801, N88-BASIC — a different machine | 173 | Secondary. Used only where the PC-9801 manual is silent; anything resting on it is graded `inferred`. |
| `analysis-8801` | PC‐8801 N88‐BASIC解析マニュアル 川村清 | [archive.org/details/PC-8801N88-BASIC](https://archive.org/details/PC-8801N88-BASIC) | PC-8801, N88-BASIC — a different machine | 312 | Secondary, third-party analysis of interpreter internals. Documents runtime behaviour the reference manuals omit; graded `inferred`. |

The **key** names the document, and is what a `source` field in
`clauses.json`, `keywords.json`, or `errors.json` cites. A citation gives the
key and both page numbers — the printed folio, which is what a reader of the
book sees, and the PDF page, which is what a reader of the scan turns to.
Because the two are not a constant offset apart (see the page map below), one
cannot be recovered from the other, so both are recorded:

    ref-9801 printed p.187 / PDF p.196

## Page map — Reference Manual (207pp scan)

**The printed folio and the PDF page are not a constant offset apart.**
Unnumbered plates shift the offset as the book progresses: it drifts from
+14 in the front matter down to +8 by the appendices. Do not add a fixed
constant to convert between them.

Verified anchors (each read directly off the printed folio on the page):

| PDF page | 20 | 40 | 60 | 100 | 140 | 170 | 185 | 192 | 200 | 207 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| printed folio | 6 | 27 | 49 | 89 | 129 | 159 | 175 | 183 | 191 | 199 |
| offset (PDF − printed) | +14 | +13 | +11 | +11 | +11 | +11 | +10 | +9 | +9 | +8 |

**How to cite a page:**

1. Find the two anchors straddling the printed page you want.
2. Interpolate an offset and derive a candidate PDF page.
3. Render that candidate page and read the printed folio on arrival.
4. If it doesn't match, adjust and re-check — do not record the citation
   until the folio you see matches the printed page you meant to cite.

A citation recorded from an unconfirmed page is worse than no citation.

`tools/check_spec.py`'s `citation-page-map` check enforces the one part of
this that is machine-checkable: because the offset only ever falls as the
book progresses, no citation may carry a larger offset than one on an
earlier printed page of the same source. A mistyped PDF page breaks that
ordering as soon as the surrounding citations bracket it, from either
side. The check cannot tell you a citation points at the *right* page —
these scans carry no text layer, so only step 3 above can — but it will
catch a citation that contradicts its neighbours.

Every one of the ten anchors above has been verified this way — each PDF page
rendered and its printed folio read off the page — both when the map was built
and again on review. None is interpolated or inferred.

## Page map — 解析マニュアル (312pp scan)

One anchor is measured: **PDF page 40 shows printed page 26** (offset +14).

That is one anchor, and nothing more. The drift across the rest of the 312 pages
has not been characterised, and there is no evidence the offset holds anywhere
else in the book. Do not extrapolate it into a constant; confirm the folio on
arrival for every citation, as above.

## 入門 (173pp scan)

No page map established yet. No OCR available. Confirm the folio on arrival
for any citation, as with the other two scans.
