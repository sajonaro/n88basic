#!/usr/bin/env python3
"""png_hashes.py -- maintain the .pnghash sidecars conform.sh checks.

WHY A SECOND REPRESENTATION EXISTS. A `.digest` case asserts a hash of the
in-process DISPLAY LIST, which is the right thing to assert in
test_conformance.ml and is invisible from outside the process: a binary
emits a PNG, not a display list. So the nine drawing cases were the one
part of the corpus scripts/conform.sh could not decide, and a released
binary or a container could have drifted in its rendering without anything
noticing.

A `.pnghash` is the sha256 of the PNG that case produces. It is a WEAKER
assertion than the digest -- it says "unchanged", never "correct" -- and it
is checkable from outside, which is exactly the trade that closes the gap.

WHAT EACH ONE ACTUALLY COVERS, measured rather than assumed. The digest is
Digest.bytes of Framebuffer.to_rgb_bytes -- the resolved RGB of the frame,
not the display list -- so it covers rasterisation and palette resolution
and stops there. The PNG hash covers all of that AND png.ml and zlib.ml,
which nothing else in the suite touches. Demonstrated by mutating
Framebuffer.rgb_at's use inside png.ml's raw_scanlines: the whole digest
suite passes, and all nine PNG hashes move. The two are not redundant, and
the encoder had no coverage at all before this.

(The first mutation attempted for that demonstration edited to_rgb_bytes,
which png.ml does not call -- the digest failed and the PNGs did not move,
the exact opposite of the claim being tested. A mutation in dead code for
the path under test proves nothing; check which function the path actually
calls.)

Regenerating is explicit, never automatic: if a rendering change is
intended, the .digest cases fail first and say so, and these are refreshed
in the same commit. A tool that silently rewrote them would turn a gate
into a rubber stamp.

Usage:
    python3 tools/png_hashes.py --check [INTERPRETER]
    python3 tools/png_hashes.py --write [INTERPRETER]
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = ROOT / "test" / "conformance"
DEFAULT = ROOT / "_build" / "default" / "bin" / "main.exe"


def cases() -> list[Path]:
    return sorted(CASES.glob("*.digest"))


def png_hash(interp: Path, name: str, work: Path) -> str | None:
    """Run one case in a scratch dir and hash the PNG it leaves behind."""
    shutil.copy(CASES / f"{name}.bas", work / f"{name}.bas")
    subprocess.run(
        [str(interp), str(work / f"{name}.bas")],
        capture_output=True, timeout=120,
    )
    png = work / f"{name}.png"
    if not png.exists():
        return None
    return hashlib.sha256(png.read_bytes()).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--write", action="store_true")
    ap.add_argument("interpreter", nargs="?", default=str(DEFAULT))
    a = ap.parse_args()

    interp = Path(a.interpreter)
    if not interp.exists():
        sys.exit(f"no interpreter at {interp} -- run `dune build` first")

    bad, wrote = [], 0
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        for d in cases():
            name = d.stem
            got = png_hash(interp, name, work)
            side = CASES / f"{name}.pnghash"
            if got is None:
                bad.append(f"{name}: drew no PNG")
                continue
            if a.write:
                side.write_text(got + "\n")
                wrote += 1
                continue
            if not side.exists():
                bad.append(f"{name}: no .pnghash sidecar -- run --write")
            elif side.read_text().strip() != got:
                bad.append(f"{name}: {side.read_text().strip()[:16]} expected, got {got[:16]}")

    if a.write:
        print(f"wrote {wrote} .pnghash sidecar(s)")
        return 0

    print(f"PNG-HASH: {len(cases()) - len(bad)} of {len(cases())} drawing cases match")
    for b in bad:
        print(f"  FAIL {b}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
