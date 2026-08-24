"""Tests for coverage.py.

Two kinds of check, mirroring test_check_spec.py's own approach: fixture
repos built under a temp directory and run as a real subprocess (proving
the counting and cross-referencing logic against data whose right answer
is known by construction), and one test against the real repository's own
spec/clauses.json and test/conformance/ tree, so a change to either that
the report's printed numbers no longer match is caught here rather than
discovered by reading the report by eye — the "cannot rot" requirement.
"""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
COVERAGE = REPO_ROOT / "tools" / "coverage.py"

SPEC_MD = "# Spec\n\n**Version 9.9.9** · today\n\nBody text.\n"


def run_coverage(repo_root: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(COVERAGE), str(repo_root)], capture_output=True, text=True)


def write_fixture(tmp_path: Path, clauses: list[dict], conformance: dict[str, list[str]]) -> None:
    """[conformance] maps a case name to the clause ids its .clauses sidecar
    lists; a matching empty .bas is written too so the fixture looks like a
    real conformance directory, though coverage.py itself never reads it."""
    spec_dir = tmp_path / "spec"
    spec_dir.mkdir(parents=True, exist_ok=True)
    (spec_dir / "clauses.json").write_text(json.dumps({"clauses": clauses}))
    (spec_dir / "spec.md").write_text(SPEC_MD)
    conf_dir = tmp_path / "test" / "conformance"
    conf_dir.mkdir(parents=True, exist_ok=True)
    for name, ids in conformance.items():
        (conf_dir / f"{name}.bas").write_text("10 END\n")
        (conf_dir / f"{name}.clauses").write_text("\n".join(ids) + "\n")


def clause(id_: str, status: str) -> dict:
    return {"id": id_, "status": status, "evidence": "manual" if status != "absent" else None, "source": "x", "text": "x"}


class CoverageTests(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp_path = Path(self._tmp.name)

    def test_prints_the_designs_own_shape(self) -> None:
        clauses = [clause("A.ONE", "implemented"), clause("A.TWO", "partial"), clause("A.THREE", "absent")]
        write_fixture(self.tmp_path, clauses, {"case1": ["A.ONE"]})
        result = run_coverage(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("spec 9.9.9 — 1/3 clauses implemented, 1 partial, 0 divergent, 1 absent", result.stdout)
        self.assertIn("conformance: 1 of 2 non-absent clauses have at least one case", result.stdout)

    def test_uncovered_implemented_clause_is_listed_as_the_worklist(self) -> None:
        clauses = [clause("A.ONE", "implemented"), clause("A.TWO", "implemented")]
        write_fixture(self.tmp_path, clauses, {"case1": ["A.ONE"]})
        result = run_coverage(self.tmp_path)
        self.assertIn("implemented clauses with NO conformance case (1)", result.stdout)
        self.assertIn("A.TWO", result.stdout)
        self.assertNotIn("  A.ONE\n", result.stdout)

    def test_fully_covered_implemented_set_says_so(self) -> None:
        clauses = [clause("A.ONE", "implemented")]
        write_fixture(self.tmp_path, clauses, {"case1": ["A.ONE"]})
        result = run_coverage(self.tmp_path)
        self.assertIn('every "implemented" clause has at least one conformance case.', result.stdout)

    def test_absent_clause_with_a_case_is_reported_as_bonus_not_counted(self) -> None:
        clauses = [clause("A.ONE", "absent")]
        write_fixture(self.tmp_path, clauses, {"case1": ["A.ONE"]})
        result = run_coverage(self.tmp_path)
        self.assertIn("conformance: 0 of 0 non-absent clauses have at least one case", result.stdout)
        self.assertIn("bonus: 1", result.stdout)
        self.assertIn("A.ONE", result.stdout)

    def test_tag_referencing_unknown_clause_id_fails(self) -> None:
        clauses = [clause("A.ONE", "implemented")]
        write_fixture(self.tmp_path, clauses, {"case1": ["A.ONE", "NO.SUCH.CLAUSE"]})
        result = run_coverage(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NO.SUCH.CLAUSE", result.stdout)
        self.assertIn("case1", result.stdout)

    def test_no_conformance_directory_is_zero_coverage_not_a_crash(self) -> None:
        clauses = [clause("A.ONE", "implemented")]
        spec_dir = self.tmp_path / "spec"
        spec_dir.mkdir(parents=True)
        (spec_dir / "clauses.json").write_text(json.dumps({"clauses": clauses}))
        (spec_dir / "spec.md").write_text(SPEC_MD)
        result = run_coverage(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("conformance: 0 of 1 non-absent clauses have at least one case", result.stdout)


class RealRepoCoverageAgreesWithClausesJson(unittest.TestCase):
    """The "cannot rot" requirement: run the report against the actual
    repository and check its printed numbers against clauses.json counted
    independently, right here, rather than trusting coverage.py to have
    counted itself correctly."""

    def test_report_runs_clean_against_the_real_repo(self) -> None:
        result = run_coverage(REPO_ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_printed_status_counts_match_clauses_json(self) -> None:
        with (REPO_ROOT / "spec" / "clauses.json").open(encoding="utf-8") as f:
            clauses = json.load(f)["clauses"]
        counts = {"implemented": 0, "partial": 0, "divergent": 0, "absent": 0}
        for c in clauses:
            counts[c["status"]] += 1

        result = run_coverage(REPO_ROOT)
        first_line = result.stdout.splitlines()[0]
        expected = (
            f"{counts['implemented']}/{len(clauses)} clauses implemented, "
            f"{counts['partial']} partial, {counts['divergent']} divergent, {counts['absent']} absent"
        )
        self.assertIn(expected, first_line, f"report line was: {first_line!r}")

    def test_printed_conformance_fraction_matches_a_fresh_scan(self) -> None:
        with (REPO_ROOT / "spec" / "clauses.json").open(encoding="utf-8") as f:
            clauses = json.load(f)["clauses"]
        non_absent_ids = {c["id"] for c in clauses if c["status"] != "absent"}

        tagged: set[str] = set()
        for path in (REPO_ROOT / "test" / "conformance").glob("*.clauses"):
            for line in path.read_text(encoding="utf-8").splitlines():
                cid = line.strip()
                if cid and not cid.startswith("#"):
                    tagged.add(cid)

        covered = non_absent_ids & tagged
        result = run_coverage(REPO_ROOT)
        second_line = result.stdout.splitlines()[1]
        self.assertIn(f"conformance: {len(covered)} of {len(non_absent_ids)} non-absent clauses have at least one case", second_line)


if __name__ == "__main__":
    unittest.main()
