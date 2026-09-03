#!/usr/bin/env python3
"""check_version_bump.py -- every release bumps the MINOR component.

THE RULE: the next tag after vX.Y.Z is vX.(Y+1).0. Not a patch bump, not a
skip. v0.1.4 is followed by v0.2.0.

WHY IT IS ENFORCED RATHER THAN WRITTEN DOWN. This project's own notes say an
automated signal nobody reads is not a check; a convention nobody checks is
weaker still. Five releases were tagged by hand as patch bumps because that is
what felt natural at the time, and nothing objected. So this objects, in the
release workflow, before anything is published.

WHAT IT DELIBERATELY DOES NOT DO: allow an exception. There is no hotfix
escape hatch, because a rule with one becomes the exception's rule. If a
genuine hotfix ever needs vX.Y.(Z+1), change this file in the same commit that
tags it -- that way the decision is visible in the diff rather than hidden in
a flag nobody sees.

Usage:
    python3 tools/check_version_bump.py <new tag> [previous tag]

With one argument it reads the previous tag from git.
"""

from __future__ import annotations

import re
import subprocess
import sys

TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def parse(tag: str) -> tuple[int, int, int]:
    m = TAG.match(tag.strip())
    if not m:
        raise ValueError(f"not a release tag: {tag!r} (expected vX.Y.Z)")
    return tuple(int(g) for g in m.groups())  # type: ignore[return-value]


def previous_tag(new: str) -> str | None:
    """The highest existing release tag below `new`."""
    out = subprocess.run(
        ["git", "tag", "--list", "v*"], capture_output=True, text=True, check=True
    ).stdout.split()
    tags = []
    for t in out:
        try:
            tags.append((parse(t), t))
        except ValueError:
            continue
    target = parse(new)
    below = [t for t in tags if t[0] < target]
    return max(below)[1] if below else None


def check(new: str, prev: str | None) -> list[str]:
    try:
        nx, ny, nz = parse(new)
    except ValueError as e:
        return [str(e)]
    if prev is None:
        # Nothing to bump from. Only a .0 makes sense as a first release.
        return [] if nz == 0 else [f"{new} is the first release, so it must end in .0"]
    px, py, _pz = parse(prev)
    want = f"v{px}.{py + 1}.0"
    if (nx, ny, nz) != (px, py + 1, 0):
        return [
            f"{new} does not follow {prev}. Every release bumps the minor "
            f"component, so the next tag is {want}."
        ]
    return []


def main() -> int:
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    new = sys.argv[1]
    prev = sys.argv[2] if len(sys.argv) == 3 else previous_tag(new)
    problems = check(new, prev)
    for p in problems:
        print(f"  {p}")
    if problems:
        print()
        print("  The rule is in tools/check_version_bump.py, which is the only")
        print("  place it lives. Changing it means changing that file.")
        return 1
    print(f"  {new} correctly follows {prev or '(no earlier release)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
