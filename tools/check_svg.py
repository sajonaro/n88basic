#!/usr/bin/env python3
"""check_svg.py -- the vector rendering must draw what the raster one draws.

raster/svg.ml is a SECOND RENDERER over the same display list, and two
renderers are two chances to be wrong. Nothing else compares them: the
conformance corpus hashes PNG bytes, and an SVG is not those bytes.

IT CANNOT BE A BYTE COMPARISON. Rasterising the SVG gives anti-aliased edges
where the framebuffer has hard ones, so every sloped line and every circle
differs on half its own pixels by construction. What must agree is the
GEOMETRY, so this compares the bounding box of the ink -- which catches a
shape in the wrong place, at the wrong size, or missing, and tolerates the
edge treatment it should tolerate.

That is a weaker check than the corpus gets, and deliberately so: a half-pixel
convention error is exactly what it is for. Circles were half a pixel up and
to the left when this was first written, invisible by eye and visible here as
a bounding box one short on each far edge.

Needs rsvg-convert and Pillow. Usage:  python3 tools/check_svg.py
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "_build/default/web/main.bc.js"
CASES = ROOT / "test/conformance"


def ink_bbox(path: pathlib.Path):
    from PIL import Image

    im = Image.open(path).convert("RGB")
    px = im.load()
    w, h = im.size
    pts = [(x, y) for y in range(h) for x in range(w) if px[x, y] != (0, 0, 0)]
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def main() -> int:
    if not BUNDLE.exists():
        sys.exit("no browser build -- run `dune build @web/web` first")

    names = sorted(p.stem for p in CASES.glob("*.pnghash"))
    script = (
        "const m=require(%s).n88;const fs=require('fs');"
        "const out={};for (const n of %s){"
        "const r=m.run(fs.readFileSync(%s+'/'+n+'.bas','utf8'),'');"
        "out[n]={svg:r.svg,kind:r.svgKind,png:Buffer.from(r.png,'binary').toString('base64')};}"
        "console.log(JSON.stringify(out));"
        % (json.dumps(str(BUNDLE)), json.dumps(names), json.dumps(str(CASES)))
    )
    data = json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)

    ok, raster, bad = 0, [], []
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        for name, r in data.items():
            if r["kind"] != "vector":
                # PAINT and tiles take the raster path by design; there is no
                # vector rendering to check against.
                raster.append(name)
                continue
            (tmp / "a.svg").write_text(r["svg"])
            import base64

            (tmp / "a.png").write_bytes(base64.b64decode(r["png"]))
            subprocess.run(
                ["rsvg-convert", "-w", "640", "-h", "400", str(tmp / "a.svg"), "-o", str(tmp / "b.png")],
                check=True, capture_output=True,
            )
            want, got = ink_bbox(tmp / "a.png"), ink_bbox(tmp / "b.png")
            if want == got:
                ok += 1
            else:
                bad.append(f"{name}: raster ink {want}, vector ink {got}")

    for b in bad:
        print(f"  FAIL {b}")
    print()
    print(f"{ok} of {ok + len(bad)} vector renderings place their ink exactly where the raster one does.")
    if raster:
        print(f"{len(raster)} case(s) render as an embedded raster by design (PAINT or a tile): "
              + ", ".join(sorted(raster)))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
