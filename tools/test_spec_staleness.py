"""Tests for the stale-excuse scan (tools/spec_staleness.py).

The scan is advisory, so the thing worth testing is not an exit code but
that it *notices* — and that it stays quiet where it should, because a scan
that flags everything is one nobody reads.

Each detected phrasing gets a case built from the incident that earned it,
so a future edit to EXCUSE_RE that drops one fails here with the name of
the defect it would stop catching.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from spec_staleness import check_stale_excuses

REPO_ROOT = Path(__file__).resolve().parent.parent


def clause(text: str, status: str = "partial", cid: str = "X.Y") -> list[dict]:
    return [{"id": cid, "status": status, "text": text}]


def flagged(clauses: list[dict]) -> bool:
    lines = check_stale_excuses(clauses)
    return not lines[0].endswith("no clause leans on a fact elsewhere")


class StaleExcuseScanTests(unittest.TestCase):
    # -- the phrasings, each named for the incident that earned it ----

    def test_catches_each_phrasing_that_hid_a_real_defect(self) -> None:
        cases = {
            "GFX.PAINT: implemented because tiling was out of scope":
                "PARTIAL: tile filling is out of scope per spec.md.",
            "OP.LOGICAL: partial for operators that had since landed":
                "PARTIAL: XOR, IMP and EQV are not implemented here.",
            "SCREEN.WIDTH: the writer does not track WIDTH":
                "PARTIAL: the output writer does not track WIDTH.",
            "STR.VAL: blaming the lexer":
                "matching the lexer's own inability to read octal literals.",
            "STR.VAL again: cannot yet":
                "PARTIAL: the evaluator cannot yet produce output mid-expression.",
            "SCREEN.LOCATE: no text screen":
                "PARTIAL: this interpreter has no text screen to move a cursor on.",
            "SCREEN.BASIC: one page":
                "This interpreter has one page, so neither number selects anything.",
            "OP.PRECEDENCE: pointing at divergences in other clauses":
                "The fuller order is known to diverge; see those clauses.",
        }
        for incident, text in cases.items():
            with self.subTest(incident=incident):
                self.assertTrue(flagged(clause(text)), f"missed: {incident}")

    # -- quiet where it should be -------------------------------------

    def test_ignores_a_clause_that_stands_on_its_own_page(self) -> None:
        self.assertFalse(flagged(clause(
            "ASC(s) returns the character code of the first character of s. "
            "The manual does not say what the null string does; this "
            "interpreter raises Illegal function call, a decision of ours."
        )))

    def test_ignores_a_deliberate_divergence_stated_plainly(self) -> None:
        # NUM.DIV-BY-ZERO's shape: a divergence owned outright, resting on
        # nothing elsewhere. It must not be nagged about on every run.
        self.assertFalse(flagged(clause(
            "DIVERGENT: this interpreter raises Division by zero as an "
            "ordinary halting error instead, which is a choice, not a defect.",
            status="divergent",
        )))

    def test_reports_status_and_id_so_a_reader_can_triage(self) -> None:
        lines = check_stale_excuses(clause(
            "PARTIAL: the output writer does not track WIDTH.",
            status="partial", cid="SCREEN.WIDTH"))
        body = "\n".join(lines)
        self.assertIn("SCREEN.WIDTH", body)
        self.assertIn("partial", body)
        self.assertIn("does not track", body)

    # -- shape ---------------------------------------------------------

    def test_survives_a_malformed_entry(self) -> None:
        # check_parses owns reporting these; this must not crash on them.
        check_stale_excuses(["not a dict", {"id": "A"}, {"id": "B", "text": None}])

    def test_real_spec_data_hits_only_live_facts(self) -> None:
        """Every current hit must be a fact that is still true.

        Not a freeze on the count -- it should move as clauses change. It
        pins that no hit is mere narration of an expired excuse, which is
        what the "describe, do not quote" convention in spec_staleness.py's
        docstring exists to prevent.
        """
        with (REPO_ROOT / "spec" / "clauses.json").open(encoding="utf-8") as f:
            clauses = json.load(f)["clauses"]
        lines = check_stale_excuses(clauses)
        hits = [l for l in lines if l.startswith("  ")]
        for line in hits:
            self.assertTrue(
                "no text screen" in line or "one page" in line,
                f"unexpected stale-excuse hit, triage it: {line.strip()}",
            )


if __name__ == "__main__":
    unittest.main()
