#!/usr/bin/env python3
"""folio.py — stack the folio band of several pages into one image.

The printed folio and the PDF page number in these scans are not a constant
offset apart (spec/sources.md), so every citation has to be confirmed by
reading the page number printed on the page itself. Rendering a whole page to
check one number is slow and burns an image per page; this crops just the
horizontal band the folio sits in, from each of several pages, and stacks those
strips into a single tall image -- so a run of pages can be confirmed at once.

Earlier sessions kept this in a session scratchpad, where it did not survive a
restart. It lives here now.

Requires PyMuPDF (`import fitz`). Standard library otherwise.

Usage:
    python3 tools/folio.py <pdf> <pages> [-o OUT.png] [--band bottom|top|both]

Example:
    python3 tools/folio.py "docs/N88-BASIC(86)_Manual.pdf" 104-110 -o /tmp/folios.png

The strips are labelled in reading order in the printed output, so the nth
strip is the nth requested page. Read the folio off the strip; if it is not the
printed page you meant to cite, adjust and re-check -- never record a citation
from a page whose folio you have not seen.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover - environment-dependent
    sys.exit("folio.py needs PyMuPDF: pip install --break-system-packages pymupdf")

from render import parse_pages  # noqa: E402  (same directory)

# Fraction of page height taken as the folio band. The reference manual prints
# its folio in the bottom margin, but well clear of the paper edge -- on PDF
# p.60 it sits at about 91% of the page height, so a tighter band than this
# crops it off and every strip comes back blank. The 解析マニュアル puts some
# folios in the top margin instead; --band top or both reaches those.
BAND = 0.14


def _clip(rect: fitz.Rect, where: str) -> list[fitz.Rect]:
    height = rect.height
    bottom = fitz.Rect(rect.x0, rect.y1 - height * BAND, rect.x1, rect.y1)
    top = fitz.Rect(rect.x0, rect.y0, rect.x1, rect.y0 + height * BAND)
    return {"bottom": [bottom], "top": [top], "both": [top, bottom]}[where]


def stack(pdf: Path, pages: list[int], out: Path, where: str, dpi: int) -> Path:
    strips: list[fitz.Pixmap] = []
    with fitz.open(pdf) as doc:
        for page_no in pages:
            if not 1 <= page_no <= doc.page_count:
                raise ValueError(
                    f"PDF page {page_no} out of range (scan has {doc.page_count} pages)"
                )
            page = doc[page_no - 1]
            for clip in _clip(page.rect, where):
                strips.append(page.get_pixmap(dpi=dpi, clip=clip))

    width = max(s.width for s in strips)
    height = sum(s.height for s in strips)
    canvas = fitz.Pixmap(fitz.csRGB, fitz.IRect(0, 0, width, height), False)
    canvas.clear_with(255)
    y = 0
    for strip in strips:
        strip.set_origin(0, y)
        canvas.copy(strip, strip.irect)
        y += strip.height
    canvas.save(out)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pdf", type=Path)
    ap.add_argument("pages", help="PDF page numbers, 1-based: 104, 104-108")
    ap.add_argument("-o", "--out", type=Path, default=Path("folios.png"))
    ap.add_argument("--band", choices=("bottom", "top", "both"), default="bottom")
    ap.add_argument("--dpi", type=int, default=170)
    args = ap.parse_args(argv)

    pages = parse_pages(args.pages)
    path = stack(args.pdf, pages, args.out, args.band, args.dpi)
    order = ", ".join(str(p) for p in pages)
    print(f"{path}  (strips top-to-bottom = PDF pages {order}, band={args.band})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
