#!/usr/bin/env python3
"""check_spec.py — structural validator for the N88-BASIC(86) spec companion data.

Standard library only. Validates the three companion data files described in
spec/spec.md §2:

    spec/keywords.json
        { "keywords": [
            { "name": str,               # e.g. "PRINT USING"
              "kind": str,               # e.g. "statement", "function"
              "syntax": str | null,
              "summary": str,            # one-line summary
              "scope": "in" | "deferred" | "out",
              "clauses": [clause_id, ...],  # governing clauses
              "source": str              # citation; required if syntax is non-null
            }, ... ] }

    spec/clauses.json
        { "clauses": [
            { "id": clause_id,           # e.g. "PRINT.USING.OVERFLOW"
              "status": "implemented" | "partial" | "absent" | "divergent",
              "evidence": "manual" | "inferred" | "unspecified" | null,
              "source": str,             # citation; required unless status is "absent"
              "text": str                # optional prose statement of the rule
            }, ... ] }

    spec/errors.json
        { "errors": [
            { "number": int,             # required, unique
              "message": str,            # required, non-empty
              "meaning": str,            # required, non-empty
              "clause": clause_id,       # governing clause
              "source": str,             # required; citation, non-empty
              "partial": bool,           # optional; the manual documents more
              "note": str                # optional; what "partial" elides
            }, ... ] }

A clause_id is one or more alphanumeric segments joined by dots or hyphens
(``^[A-Z0-9]+(?:[.-][A-Z0-9]+)*$``): uppercase letters and digits, with no
separator left dangling, so "." and "---" are not clause ids.

Checks performed (implemented in spec_checks.py; see that module's
docstrings for each check's exact rule):
    1. Every file parses as JSON and has the expected envelope shape,
       including that every entry in a collection is a JSON object.
    2. Clause ids are unique within clauses.json and match the strict format.
    3. Referential integrity: every clause id referenced from keywords.json
       ("clauses") or errors.json ("clause") exists in clauses.json.
    4. Enum validity: evidence, status, and keyword scope are drawn from
       their fixed vocabularies (or null, for evidence).
    5. Evidence/status invariant: a clause whose status is not "absent" must
       carry a non-null evidence grade and a non-empty source citation. A
       stub clause (status "absent") may have evidence: null.
    6. Keyword syntax/source invariant: a keyword whose "syntax" is
       non-null must carry a non-empty "source" citation. A keyword with
       "syntax": null needs no source.
    7. Error entry validity: every errors.json entry carries an integer
       "number" unique within the file, and non-empty "message", "meaning"
       and "source" strings.
    8. In-scope clause coverage: every keyword with "scope": "in" has a
       non-empty "clauses" array. Deferred and out-of-scope keywords are
       exempt.
    9. Scope coverage: every keyword named in spec/spec.md §3.1 (the
       backtick-quoted tokens between the "### 3.1 In scope" and
       "### 3.2 Deferred" headings) has a keywords.json entry with
       scope "in", and vice versa.

   10. Citation page map: every "source" naming a printed and a PDF page
       parses, pairs its two page lists one-to-one at a single offset, and
       never lets that offset rise as the printed page advances within one
       source document. spec/sources.md states this rule in prose; see
       tools/spec_citations.py for why the ordering is the testable part
       of it, and for what it deliberately cannot prove.

   11. Stale-excuse scan: report every clause whose prose justifies itself
       with a fact about a DIFFERENT part of the system ("out of scope",
       "the lexer cannot yet", "does not track"). Nothing re-derives such a
       status when that fact moves, and it is this repo's most-repeated
       defect. See tools/spec_staleness.py for the incidents behind each
       phrasing, and for why it reports rather than fails.

Exit code policy — this is the important part:
    Checks 1-8 and 10 are STRUCTURAL: malformed JSON, a broken envelope, a
    non-object entry, duplicate or malformed clause ids, dangling references,
    invalid enum values, a violated evidence/status or syntax/source
    invariant, an uncited or half-written error entry, an in-scope keyword
    with no governing clause, or a citation that contradicts the page map are
    all bugs in the data. Any one of them makes the exit code non-zero, from
    the very first commit.

    Checks 9 and 11 are ADVISORY, and neither ever changes the exit code.

    Check 9 is coverage, not structure. keywords.json starts empty and is
    populated incrementally over the life of the project; §3.1 will always
    list keywords not yet inventoried until the inventory is complete. A gap
    found here is reported (as a COVERAGE line, with counts and offenders)
    but never changes the exit code. Coverage is tracked, not enforced.

    Check 11 reports rather than fails for a different reason: a hit is not
    a defect. "No text screen" is a true and stable fact about this
    interpreter, and a clause may recount an expired excuse deliberately, as
    history. Only a reader can tell those from a live stale excuse, because
    the difference is whether the fact still holds. A gate here would be
    noise, and a noisy gate gets ignored.

Usage:
    python3 tools/check_spec.py [repo_root]

``repo_root`` defaults to the parent of this script's directory, i.e. the
repository root when the script lives at ``<repo>/tools/check_spec.py``. It
must contain a ``spec/`` directory holding the three JSON files and
``spec.md``.
"""

from __future__ import annotations

import sys
from pathlib import Path

from spec_citations import check_citation_page_map
from spec_staleness import check_stale_excuses
from spec_checks import (
    check_enums,
    check_error_entries,
    check_evidence_status_invariant,
    check_in_scope_keywords_have_clauses,
    check_keyword_syntax_source_invariant,
    check_clause_ids,
    check_parses,
    check_references,
    check_scope_coverage,
)


def run_checks(repo_root: Path) -> tuple[int, list[str]]:
    spec_dir = repo_root / "spec"
    report: list[str] = []
    structural_ok = True

    ok, issues, docs = check_parses(spec_dir)
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} json-parses-and-envelope-shape")
    report.extend(f"  {i}" for i in issues)

    ok, issues, clause_ids = check_clause_ids(docs["clauses"])
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} clause-ids-unique-and-well-formed")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_references(docs["keywords"], docs["errors"], clause_ids)
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} referential-integrity")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_enums(docs["keywords"], docs["clauses"])
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} enum-validity")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_evidence_status_invariant(docs["clauses"])
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} evidence-status-invariant")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_keyword_syntax_source_invariant(docs["keywords"])
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} keyword-syntax-source-invariant")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_error_entries(docs["errors"])
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} error-entry-validity")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_in_scope_keywords_have_clauses(docs["keywords"])
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} in-scope-keywords-have-clauses")
    report.extend(f"  {i}" for i in issues)

    ok, issues = check_citation_page_map(docs)
    structural_ok &= ok
    report.append(f"{'PASS' if ok else 'FAIL'} citation-page-map")
    report.extend(f"  {i}" for i in issues)

    report.extend(check_scope_coverage(spec_dir, docs["keywords"]))
    report.extend(check_stale_excuses(docs["clauses"]))

    exit_code = 0 if structural_ok else 1
    report.append(f"SUMMARY: structural={'PASS' if structural_ok else 'FAIL'} exit={exit_code}")
    return exit_code, report


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        repo_root = Path(argv[1]).resolve()
    else:
        repo_root = Path(__file__).resolve().parent.parent
    exit_code, report = run_checks(repo_root)
    print("\n".join(report))
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
