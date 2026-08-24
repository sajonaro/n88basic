"""Tests for check_spec.py.

Builds small fixture repos under a temp directory and runs the checker
against them as a real subprocess, asserting on the exit code (and, where
useful, on the report text) — proving both that the checker accepts good
data and that it actually fails on each bad-data scenario it claims to
catch.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHECKER = REPO_ROOT / "tools" / "check_spec.py"

VALID_CLAUSE = {
    "id": "PRINT.BASIC",
    "status": "implemented",
    "evidence": "manual",
    "source": "N88-BASIC(86) Reference Manual p.1",
    "text": "PRINT writes a value to the screen.",
}

VALID_KEYWORD = {
    "name": "PRINT",
    "kind": "statement",
    "syntax": "PRINT expr",
    "summary": "Writes a value to the screen.",
    "scope": "in",
    "clauses": ["PRINT.BASIC"],
    "source": "N88-BASIC(86) Reference Manual p.1",
}

VALID_ERROR = {
    "number": 5,
    "message": "Illegal function call",
    "meaning": "An argument lay outside the domain the built-in accepts.",
    "clause": None,
    "source": "N88BASIC86Manual printed p.184 / PDF p.193",
}


def run_checker(repo_root: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CHECKER), str(repo_root)],
        capture_output=True,
        text=True,
    )


def write_fixture(tmp_path: Path, keywords: list, clauses: list, errors: list) -> None:
    spec_dir = tmp_path / "spec"
    spec_dir.mkdir(parents=True, exist_ok=True)
    (spec_dir / "keywords.json").write_text(json.dumps({"keywords": keywords}))
    (spec_dir / "clauses.json").write_text(json.dumps({"clauses": clauses}))
    (spec_dir / "errors.json").write_text(json.dumps({"errors": errors}))


class CheckSpecTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp_path = Path(self._tmp.name)

    def test_well_formed_fixture_passes(self) -> None:
        write_fixture(self.tmp_path, [VALID_KEYWORD], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_absent_clause_may_have_null_evidence(self) -> None:
        stub = dict(VALID_CLAUSE, id="STUB.CLAUSE", status="absent", evidence=None, source="")
        write_fixture(self.tmp_path, [], [stub], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_duplicate_clause_id_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE, dict(VALID_CLAUSE)], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate clause id", result.stdout)

    def test_dangling_clause_reference_fails(self) -> None:
        kw = dict(VALID_KEYWORD, clauses=["NO.SUCH.CLAUSE"])
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown clause", result.stdout)

    def test_dangling_error_clause_reference_fails(self) -> None:
        err = dict(VALID_ERROR, clause="NO.SUCH.CLAUSE")
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [err])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown clause", result.stdout)

    def test_well_formed_error_entry_passes(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [VALID_ERROR])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_error_without_source_field_fails(self) -> None:
        err = {k: v for k, v in VALID_ERROR.items() if k != "source"}
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [err])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("\"source\" must be a non-empty string", result.stdout)

    def test_error_with_blank_source_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [dict(VALID_ERROR, source="   ")])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("\"source\" must be a non-empty string", result.stdout)

    def test_error_with_non_integer_number_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [dict(VALID_ERROR, number="5")])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("\"number\" must be an integer", result.stdout)

    def test_error_with_empty_message_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [dict(VALID_ERROR, message="")])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("\"message\" must be a non-empty string", result.stdout)

    def test_error_with_null_meaning_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [dict(VALID_ERROR, meaning=None)])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("\"meaning\" must be a non-empty string", result.stdout)

    def test_duplicate_error_number_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [VALID_ERROR, dict(VALID_ERROR)])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate error number 5", result.stdout)

    def test_non_object_error_entry_fails(self) -> None:
        # The reviewer's payload: an empty entry, a bare string, and an
        # entry with nothing but a number all used to pass vacuously.
        write_fixture(self.tmp_path, [], [VALID_CLAUSE], [{}, "garbage", {"number": 1}])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("errors.json[1]: entry is not an object", result.stdout)
        self.assertIn("\"message\" must be a non-empty string", result.stdout)

    def test_non_object_keyword_entry_fails(self) -> None:
        write_fixture(self.tmp_path, ["oops", 42, None], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("keywords.json[0]: entry is not an object", result.stdout)
        self.assertIn("keywords.json[2]: entry is not an object", result.stdout)

    def test_non_object_clause_entry_fails(self) -> None:
        write_fixture(self.tmp_path, [], [VALID_CLAUSE, "garbage"], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clauses.json[1]: entry is not an object", result.stdout)

    def test_punctuation_only_clause_id_rejected(self) -> None:
        for bad_id in (".", "---"):
            with self.subTest(clause_id=bad_id):
                write_fixture(self.tmp_path, [], [dict(VALID_CLAUSE, id=bad_id)], [])
                result = run_checker(self.tmp_path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("does not match", result.stdout)

    def test_invalid_clause_id_format_fails(self) -> None:
        bad = dict(VALID_CLAUSE, id="print.basic")
        write_fixture(self.tmp_path, [], [bad], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stdout)

    def test_invalid_status_enum_fails(self) -> None:
        bad = dict(VALID_CLAUSE, status="bogus")
        write_fixture(self.tmp_path, [], [bad], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid status", result.stdout)

    def test_invalid_evidence_enum_fails(self) -> None:
        bad = dict(VALID_CLAUSE, evidence="guessed")
        write_fixture(self.tmp_path, [], [bad], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid evidence", result.stdout)

    def test_invalid_scope_enum_fails(self) -> None:
        bad = dict(VALID_KEYWORD, scope="maybe")
        write_fixture(self.tmp_path, [bad], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid scope", result.stdout)

    def test_implemented_with_null_evidence_fails(self) -> None:
        bad = dict(VALID_CLAUSE, evidence=None)
        write_fixture(self.tmp_path, [], [bad], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("evidence is null", result.stdout)

    def test_implemented_with_empty_source_fails(self) -> None:
        bad = dict(VALID_CLAUSE, source="")
        write_fixture(self.tmp_path, [], [bad], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source is empty", result.stdout)

    def test_keyword_syntax_without_source_field_fails(self) -> None:
        kw = {k: v for k, v in VALID_KEYWORD.items() if k != "source"}
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-null syntax but source is empty", result.stdout)

    def test_keyword_syntax_with_empty_source_fails(self) -> None:
        kw = dict(VALID_KEYWORD, source="")
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-null syntax but source is empty", result.stdout)

    def test_keyword_syntax_with_source_passes(self) -> None:
        write_fixture(self.tmp_path, [VALID_KEYWORD], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_keyword_null_syntax_needs_no_source(self) -> None:
        kw = {k: v for k, v in VALID_KEYWORD.items() if k != "source"}
        kw["syntax"] = None
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_in_scope_keyword_with_empty_clauses_fails(self) -> None:
        kw = dict(VALID_KEYWORD, clauses=[])
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is scope \"in\" but has no clauses", result.stdout)

    def test_in_scope_keyword_with_clauses_passes(self) -> None:
        write_fixture(self.tmp_path, [VALID_KEYWORD], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_deferred_keyword_with_empty_clauses_passes(self) -> None:
        kw = dict(VALID_KEYWORD, scope="deferred", clauses=[])
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_out_of_scope_keyword_with_empty_clauses_passes(self) -> None:
        kw = dict(VALID_KEYWORD, scope="out", clauses=[])
        write_fixture(self.tmp_path, [kw], [VALID_CLAUSE], [])
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_malformed_json_fails(self) -> None:
        spec_dir = self.tmp_path / "spec"
        spec_dir.mkdir(parents=True, exist_ok=True)
        (spec_dir / "keywords.json").write_text("{ this is not json")
        (spec_dir / "clauses.json").write_text(json.dumps({"clauses": []}))
        (spec_dir / "errors.json").write_text(json.dumps({"errors": []}))
        result = run_checker(self.tmp_path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid JSON", result.stdout)

    def test_coverage_gap_does_not_fail_exit_code(self) -> None:
        # keywords.json empty but spec.md lists §3.1 keywords: a coverage
        # gap, not a structural failure, so the exit code must stay 0.
        spec_dir = self.tmp_path / "spec"
        spec_dir.mkdir(parents=True, exist_ok=True)
        (spec_dir / "keywords.json").write_text(json.dumps({"keywords": []}))
        (spec_dir / "clauses.json").write_text(json.dumps({"clauses": []}))
        (spec_dir / "errors.json").write_text(json.dumps({"errors": []}))
        (spec_dir / "spec.md").write_text(
            "### 3.1 In scope\n\n`PRINT` · `LET`\n\n### 3.2 Deferred\n\n`VIEW`\n"
        )
        result = run_checker(self.tmp_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("COVERAGE", result.stdout)
        self.assertIn("PRINT", result.stdout)

    def test_real_repo_seed_files_pass(self) -> None:
        result = run_checker(REPO_ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
