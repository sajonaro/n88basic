#!/usr/bin/env python3
"""render.py — render a page range of a reference scan to PNG, so it can be read.

The scans named in spec/sources.md are gitignored image-only PDFs with no text
layer; the only way to read one is to look at it. This turns a PDF page range
into PNGs an agent (or a human) can open.

Earlier sessions kept this in a session scratchpad, where it did not survive a
restart and had to be rewritten from memory each time. It lives here now.

Requires PyMuPDF (`import fitz`). Standard library otherwise.

Usage:
    python3 tools/render.py <pdf> <pages> [-o OUTDIR] [--dpi N]

    <pages> is a page list in PDF page numbers, 1-based, the numbers you would
    type into a viewer: "104", "104-108", "20,40,60".

Example:
    python3 tools/render.py "docs/N88-BASIC(86)_Manual.pdf" 104-106 -o /tmp/pages

Remember that the PDF page is not the printed folio (spec/sources.md): render
the page, then read the folio off it -- tools/folio.py crops just that band --
before recording any citation.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover - environment-dependent
    sys.exit("render.py needs PyMuPDF: pip install --break-system-packages pymupdf")


def parse_pages(spec: str) -> list[int]:
    """Expand "20,40-42" into [20, 40, 41, 42], in 1-based PDF page numbers."""
    pages: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part[1:]:
            lo_s, hi_s = part.split("-", 1)
            lo, hi = int(lo_s), int(hi_s)
            if lo > hi:
                raise ValueError(f"descending page range: {part}")
            pages.extend(range(lo, hi + 1))
        else:
            pages.append(int(part))
    if not pages:
        raise ValueError("no pages requested")
    return pages


def render(pdf: Path, pages: list[int], outdir: Path, dpi: int) -> list[Path]:
    written: list[Path] = []
    outdir.mkdir(parents=True, exist_ok=True)
    with fitz.open(pdf) as doc:
        for page_no in pages:
            if not 1 <= page_no <= doc.page_count:
                raise ValueError(
                    f"PDF page {page_no} out of range (scan has {doc.page_count} pages)"
                )
            pix = doc[page_no - 1].get_pixmap(dpi=dpi)
            out = outdir / f"{pdf.stem[:20].replace(' ', '_')}-p{page_no:03d}.png"
            pix.save(out)
            written.append(out)
    return written


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pdf", type=Path)
    ap.add_argument("pages", help="PDF page numbers, 1-based: 104, 104-108, 20,40,60")
    ap.add_argument("-o", "--outdir", type=Path, default=Path("."))
    ap.add_argument("--dpi", type=int, default=170)
    args = ap.parse_args(argv)

    for path in render(args.pdf, parse_pages(args.pages), args.outdir, args.dpi):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
