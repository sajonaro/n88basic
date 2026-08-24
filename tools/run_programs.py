#!/usr/bin/env python3
"""run_programs.py -- run the example programs under test/programs and report.

These are not conformance cases and this is not a gate. A conformance case
asserts exact output and fails the build; that works because what it asserts
is a string. Several of these draw, and what a drawing program asserts is a
picture, which no string comparison decides.

So what this reports is the one thing decidable mechanically -- whether each
program runs at all -- and it reports failures loudly rather than skipping
them. A program the interpreter cannot run stays here and shows up as BLOCKED
on every run: a set that quietly dropped what it fails would report success it
had not earned.

Where the language can read back what it did, the programs say what they
expect and print the answer (POINT gives the palette number at a coordinate).
What a readback cannot see, a human must: open the PNG.

Usage:
    python3 tools/run_programs.py [--png-dir DIR]

Exit status is 0 whether or not a program is blocked -- again, not a gate.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROGRAMS = ROOT / "test" / "programs"
INTERP = ROOT / "_build" / "default" / "bin" / "main.exe"

WROTE_PNG = re.compile(r"^wrote .*\.png$")


def first_line(text: str) -> str:
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line
    return ""


def diagnostic(text: str) -> str:
    """The first line that is a complaint rather than a progress notice.

    The interpreter writes "wrote <path>.png" to stderr alongside its errors,
    and a listing that draws and *then* fails emits the notice first -- so
    taking stderr's first line reports a success where there was a failure.
    """
    for line in text.splitlines():
        line = line.strip()
        if line and not WROTE_PNG.match(line):
            return line
    return ""


def run_one(path: Path) -> tuple[bool, str]:
    """Run one listing. Returns (ran_clean, one-line summary).

    A program may carry a `<name>.stdin` sidecar holding the keystrokes to
    feed it. An interactive program driven from a file usually finishes by
    running out of input rather than by reaching an END -- on the real
    machine the reader would have pressed STOP -- so that is reported as a
    normal ending and not as a gap.
    """
    stdin_path = path.with_suffix(".stdin")
    stdin_bytes = stdin_path.read_bytes() if stdin_path.exists() else None
    # Binary, and decoded leniently below. A BASIC program emits BYTES, not
    # text: a program printing CHR$ of every code up to 255 emits bytes that
    # are not valid UTF-8, and a text-mode version of this runner crashed on
    # them rather than reporting anything.
    proc = subprocess.run(
        [str(INTERP), str(path)],
        capture_output=True,
        timeout=120,
        input=stdin_bytes,
    )
    out = proc.stdout.decode("utf-8", errors="replace")
    err = proc.stderr.decode("utf-8", errors="replace")
    if proc.returncode != 0 and stdin_bytes is not None:
        if (diagnostic(err) or diagnostic(out)).startswith("Out of input"):
            return True, "ran to input exhaustion"
    if proc.returncode == 0:
        merged = out + err
        drew = "wrote" in merged and ".png" in merged
        note = "ran, drew a PNG" if drew else "ran, no PNG"
        return True, note
    # On failure report the diagnostic, not the output. A program can draw a
    # partial picture and *then* hit the error, so
    # the "wrote ...png" line would otherwise mask the reason it stopped.
    reason = diagnostic(err) or diagnostic(out)
    return False, reason or f"exit {proc.returncode}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--png-dir", help="unused today; PNGs land beside the source")
    parser.parse_args()

    if not INTERP.exists():
        sys.exit(f"no interpreter at {INTERP} -- run `dune build` first")

    listings = sorted(PROGRAMS.glob("*.bas"))
    if not listings:
        sys.exit(f"no programs under {PROGRAMS}")

    blocked: list[tuple[str, str]] = []
    width = max(len(p.name) for p in listings)

    for path in listings:
        ok, note = run_one(path)
        mark = "ok     " if ok else "BLOCKED"
        print(f"{mark}  {path.name.ljust(width)}  {note}")
        if not ok:
            blocked.append((path.name, note))

    print()
    print(f"{len(listings) - len(blocked)} of {len(listings)} programs run.")
    if blocked:
        print()
        print("Blocked, and why:")
        for name, note in blocked:
            print(f"  {name}: {note}")
    print()
    print("Running is the weak half. The programs check what they can with")
    print("POINT; for the rest, open the PNGs and look at them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
