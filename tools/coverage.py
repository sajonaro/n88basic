#!/usr/bin/env python3
"""coverage.py — the conformance coverage report (design doc §9, "the
coverage report... how complete are we").

Standard library only, consistent with tools/check_spec.py. Cross-references
spec/clauses.json's own status field against which clause ids the
conformance suite (test/conformance/*.clauses) actually exercises, and
prints the shape design §9 asks for:

    spec 0.1.0 — 40/99 clauses implemented, 16 partial, 1 divergent, 42 absent
    conformance: 36 of 57 non-absent clauses have at least one case

followed by the worklist that is this report's real value: every
"implemented" clause with no conformance case at all.

This tool only measures. It never edits clauses.json's statuses and never
changes conformance/*.clauses — a report that can adjust what it measures
would be worthless as a report. If clauses.json looks wrong (a status that
does not match what the interpreter demonstrably does), that is worth a
human decision, not a rewrite from here.

A clause counts as "non-absent" when its status is "implemented",
"partial", or "divergent" — status "absent" means clauses.json only holds
a stub for it (no clause text has been written yet), which is a gap in the
spec itself, not something a conformance test can be grounded in yet
(spec/spec.md §3.4: a conformance test backs a *stated* rule). A case may
still tag an absent clause's id (several conformance cases here do, for
keywords like PRINT USING and GOTO whose behaviour is implemented well
ahead of their clause prose); such tags are reported separately, as a
bonus, and do not count toward the non-absent coverage fraction.

Usage:
    python3 tools/coverage.py [repo_root]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

STATUS_ORDER = ["implemented", "partial", "divergent", "absent"]


def load_clauses(spec_dir: Path) -> list[dict]:
    with (spec_dir / "clauses.json").open("r", encoding="utf-8") as f:
        doc = json.load(f)
    return [c for c in doc.get("clauses", []) if isinstance(c, dict)]


def load_spec_version(spec_dir: Path) -> str:
    text = (spec_dir / "spec.md").read_text(encoding="utf-8")
    m = re.search(r"\*\*Version ([0-9]+(?:\.[0-9]+)*)\*\*", text)
    return m.group(1) if m else "unknown"


def load_conformance_tags(conformance_dir: Path) -> dict[str, list[str]]:
    """clause id -> list of conformance case names that tag it.

    Reads every `*.clauses` sidecar directly rather than trusting a `.bas`
    file exists to match it — an orphaned sidecar is this report's problem
    to notice, not to hide.
    """
    tags: dict[str, list[str]] = {}
    if not conformance_dir.is_dir():
        return tags
    for path in sorted(conformance_dir.glob("*.clauses")):
        case_name = path.stem
        for line in path.read_text(encoding="utf-8").splitlines():
            cid = line.strip()
            if not cid or cid.startswith("#"):
                continue
            tags.setdefault(cid, []).append(case_name)
    return tags


def build_report(repo_root: Path) -> tuple[str, bool]:
    spec_dir = repo_root / "spec"
    conformance_dir = repo_root / "test" / "conformance"

    clauses = load_clauses(spec_dir)
    version = load_spec_version(spec_dir)
    tags = load_conformance_tags(conformance_dir)

    counts = {status: 0 for status in STATUS_ORDER}
    for c in clauses:
        status = c.get("status")
        if status in counts:
            counts[status] += 1

    non_absent = [c for c in clauses if c.get("status") != "absent"]
    covered_non_absent = [c for c in non_absent if c["id"] in tags]

    lines: list[str] = []
    lines.append(
        f"spec {version} — {counts['implemented']}/{len(clauses)} clauses implemented, "
        f"{counts['partial']} partial, {counts['divergent']} divergent, {counts['absent']} absent"
    )
    lines.append(f"conformance: {len(covered_non_absent)} of {len(non_absent)} non-absent clauses have at least one case")
    lines.append("")

    uncovered_implemented = sorted(c["id"] for c in clauses if c.get("status") == "implemented" and c["id"] not in tags)
    if uncovered_implemented:
        lines.append(f"implemented clauses with NO conformance case ({len(uncovered_implemented)}) — the worklist:")
        lines.extend(f"  {cid}" for cid in uncovered_implemented)
    else:
        lines.append("every \"implemented\" clause has at least one conformance case.")

    uncovered_partial = sorted(c["id"] for c in clauses if c.get("status") == "partial" and c["id"] not in tags)
    if uncovered_partial:
        lines.append("")
        lines.append(f"partial clauses with no conformance case ({len(uncovered_partial)}):")
        lines.extend(f"  {cid}" for cid in uncovered_partial)

    uncovered_divergent = sorted(c["id"] for c in clauses if c.get("status") == "divergent" and c["id"] not in tags)
    if uncovered_divergent:
        lines.append("")
        lines.append(f"divergent clauses with no conformance case ({len(uncovered_divergent)}):")
        lines.extend(f"  {cid}" for cid in uncovered_divergent)

    known_ids = {c["id"] for c in clauses}
    absent_with_cases = sorted(cid for cid in tags if cid in known_ids and cid not in {c["id"] for c in non_absent})
    if absent_with_cases:
        lines.append("")
        lines.append(
            f"bonus: {len(absent_with_cases)} \"absent\"-status clause id(s) already have a conformance case "
            "(evidence ready for whoever writes that clause's prose next):"
        )
        lines.extend(f"  {cid}" for cid in absent_with_cases)

    unknown_tags = sorted(cid for cid in tags if cid not in known_ids)
    if unknown_tags:
        lines.append("")
        lines.append(f"WARNING: {len(unknown_tags)} conformance tag(s) reference a clause id not in clauses.json:")
        for cid in unknown_tags:
            lines.append(f"  {cid} (tagged by: {', '.join(tags[cid])})")

    ok = not unknown_tags
    return "\n".join(lines), ok


def main(argv: list[str]) -> int:
    repo_root = Path(argv[1]).resolve() if len(argv) > 1 else Path(__file__).resolve().parent.parent
    report, ok = build_report(repo_root)
    print(report)
    # This is a measurement, not a gate (see module docstring): the only
    # thing that fails the exit code is data actually being broken --
    # a conformance case tagging a clause id that does not exist at all.
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
