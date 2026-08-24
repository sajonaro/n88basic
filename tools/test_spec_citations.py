"""Tests for the citation page-map check (tools/spec_citations.py).

Two kinds of check, mirroring test_check_spec.py's approach: the rule is
exercised directly against small in-memory documents, and the real
spec/ data is run through it once end to end.

The bad-data cases are the point. A check that only ever passes proves
nothing, so each way a citation can contradict the page map -- a PDF page
mistyped high or low, digits transposed, a range whose ends disagree,
page lists that do not pair up, a half-written reference -- gets a test
that fails without the check.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from spec_citations import check_citation_page_map

REPO_ROOT = Path(__file__).resolve().parent.parent


def docs(*sources: str) -> dict:
    """A clauses-only document citing each source in turn."""
    return {
        "clauses": [{"id": f"C{i}", "source": s} for i, s in enumerate(sources)],
        "errors": [],
        "keywords": [],
    }


class CitationPageMapTests(unittest.TestCase):
    def assertAccepts(self, *sources: str) -> None:
        ok, issues = check_citation_page_map(docs(*sources))
        self.assertTrue(ok, f"expected acceptance, got: {issues}")

    def assertRejects(self, *sources: str) -> list[str]:
        ok, issues = check_citation_page_map(docs(*sources))
        self.assertFalse(ok, "expected rejection, but the citations were accepted")
        return issues

    # -- the shapes the real data uses ---------------------------------

    def test_accepts_every_shape_in_the_data(self) -> None:
        self.assertAccepts(
            "ref-9801 printed p.47 / PDF p.58",
            "ref-9801 printed p.12-14 / PDF p.25-27",
            "ref-9801 printed p.12,14 / PDF p.25,27",
            "ref-9801 printed p.14 / PDF p.27 (§6.1 変数名); "
            "printed p.17 / PDF p.30 (§8 予約語)",
        )

    def test_real_spec_data_passes(self) -> None:
        loaded = {}
        for name in ("clauses", "errors", "keywords"):
            with (REPO_ROOT / "spec" / f"{name}.json").open(encoding="utf-8") as f:
                loaded[name] = json.load(f)[name]
        ok, issues = check_citation_page_map(loaded)
        self.assertTrue(ok, f"real spec data should satisfy the page map: {issues}")

    # -- the offset may fall as the book progresses, never rise --------

    def test_accepts_a_falling_offset(self) -> None:
        self.assertAccepts(
            "ref-9801 printed p.12 / PDF p.25",   # +13, front matter
            "ref-9801 printed p.100 / PDF p.111",  # +11, body
            "ref-9801 printed p.185 / PDF p.194",  # +9,  appendices
        )

    def test_rejects_a_pdf_page_typed_too_high(self) -> None:
        issues = self.assertRejects(
            "ref-9801 printed p.38 / PDF p.49",
            "ref-9801 printed p.100 / PDF p.121",  # +21: should be +11
        )
        self.assertIn("rises above", issues[0])

    def test_rejects_a_pdf_page_typed_too_low(self) -> None:
        # The mistyped row itself looks fine until a later page contradicts
        # it, so the check must compare across rows, not row by row.
        self.assertRejects(
            "ref-9801 printed p.100 / PDF p.105",  # +5: should be +11
            "ref-9801 printed p.140 / PDF p.151",
        )

    def test_reports_a_negative_offset_with_its_sign(self) -> None:
        issues = self.assertRejects(
            "ref-9801 printed p.85 / PDF p.69",  # transposed: scan behind folio
            "ref-9801 printed p.100 / PDF p.111",
        )
        self.assertIn("-16", issues[0])
        self.assertNotIn("+-16", issues[0])

    def test_source_keys_are_independent(self) -> None:
        # A second book has its own pagination; its offsets must not be
        # ordered against the first book's.
        self.assertAccepts(
            "ref-9801 printed p.185 / PDF p.194",
            "intro-8801 printed p.3 / PDF p.99",
        )

    # -- a single citation must be internally consistent ---------------

    def test_rejects_a_range_whose_ends_disagree(self) -> None:
        issues = self.assertRejects("ref-9801 printed p.100-102 / PDF p.111-115")
        self.assertIn("inconsistent offset", issues[0])

    def test_rejects_page_lists_that_do_not_pair_up(self) -> None:
        issues = self.assertRejects("ref-9801 printed p.100,101 / PDF p.111")
        self.assertIn("pair up one-to-one", issues[0])

    # -- scope: only sources reaching for the page-map form ------------

    def test_rejects_a_half_written_page_map_citation(self) -> None:
        for source in (
            "ref-9801 printed p.100 / PDF",
            "ref-9801 printed p.100",
            "ref-9801 PDF p.111",
            "printed p.100 / PDF p.111",  # no source key
        ):
            with self.subTest(source=source):
                self.assertRejects(source)

    def test_ignores_a_source_with_no_folio(self) -> None:
        # index-9801 is an HTML list with no pages at all (spec/sources.md).
        # The schema asks only for a non-empty string, so this is not the
        # page map's business.
        self.assertAccepts(
            "index-9801 PC-9801 N88(86)BASIC command index",
            "N88-BASIC(86) Reference Manual p.1",
        )

    def test_ignores_an_empty_or_missing_source(self) -> None:
        ok, issues = check_citation_page_map(
            {"clauses": [{"id": "A", "source": ""}, {"id": "B"}], "errors": [], "keywords": []}
        )
        self.assertTrue(ok, f"empty sources belong to other checks: {issues}")


if __name__ == "__main__":
    unittest.main()
