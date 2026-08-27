#!/usr/bin/env python3
"""check_deflate.py -- inflate raster/Zlib's output with a real inflater.

raster/Zlib writes zlib streams and has no decompressor, deliberately:
nothing in this project reads a PNG. So its correctness cannot be checked
from inside -- a compressor tested only against its own reader can agree
with itself and be wrong in the same direction twice.

test/deflate_samples.exe writes each sample twice, NAME.raw and NAME.z.
This inflates the second with Python's zlib and compares it to the first.
That is a round-trip through an implementation this project did not write.

The bit order is what this is really guarding. Deflate packs Huffman codes
most-significant bit first and the extra bits after a length or distance
code least-significant bit first, and getting that backwards produces a
stream that inflates correctly for a while and then fails -- so a check
that only compared sizes, or only looked at the first few bytes, would pass
a broken compressor.

Usage:
    python3 tools/check_deflate.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "_build" / "default" / "test" / "deflate_samples.exe"


def main() -> int:
    if not GEN.exists():
        sys.exit(f"no sample generator at {GEN} -- run `dune build` first")

    with tempfile.TemporaryDirectory() as td:
        subprocess.run([str(GEN), td], check=True)
        samples = sorted(Path(td).glob("*.raw"))
        if not samples:
            sys.exit("the generator produced no samples")

        bad = []
        total_raw = total_z = 0
        for raw_path in samples:
            name = raw_path.stem
            raw = raw_path.read_bytes()
            z = (Path(td) / f"{name}.z").read_bytes()
            total_raw += len(raw)
            total_z += len(z)
            try:
                back = zlib.decompress(z)
            except Exception as e:                      # noqa: BLE001
                bad.append(f"{name}: does not inflate at all -- {e}")
                continue
            if back != raw:
                bad.append(
                    f"{name}: inflated to {len(back)} bytes, expected {len(raw)}"
                )
                continue
            ratio = f"{len(raw) / len(z):.0f}x" if len(z) else "-"
            print(f"  ok  {name:<16} {len(raw):>8} -> {len(z):>7}  {ratio}")

        for b in bad:
            print(f"  FAIL {b}")

    print()
    if total_z:
        print(f"{len(samples) - len(bad)} of {len(samples)} samples round-trip; "
              f"{total_raw} bytes -> {total_z} overall.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
