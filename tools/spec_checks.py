#!/usr/bin/env python3
"""spec_checks.py — individual structural checks for the spec companion data.

Each ``check_*`` function validates one rule against the parsed JSON
documents and returns ``(ok, issues)`` (or, for the two checks other checks
depend on, an extra data value alongside). See ``check_spec.py`` for the
schema these checks validate and the overall exit-code policy; this module
holds the checks themselves so that file stays under the project's
300-line-per-file limit.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

# A clause id is one or more alphanumeric segments joined by dots or hyphens.
# Requiring a segment on each side of every separator rejects ids that are
# punctuation only ("." , "---") or that dangle a separator (".PRINT", "NUM.").
CLAUSE_ID_RE = re.compile(r"^[A-Z0-9]+(?:[.\-][A-Z0-9]+)*$")
EVIDENCE_VALUES = {"manual", "inferred", "unspecified"}
STATUS_VALUES = {"implemented", "partial", "absent", "divergent"}
SCOPE_VALUES = {"in", "deferred", "out"}


def load_json(path: Path) -> tuple[Any, str | None]:
    """Load JSON from path. Returns (data, None) or (None, error message)."""
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f), None
    except OSError as e:
        return None, f"cannot read {path}: {e}"
    except json.JSONDecodeError as e:
        return None, f"invalid JSON in {path}: {e}"


def check_parses(spec_dir: Path) -> tuple[bool, list[str], dict[str, Any]]:
    """Check 1: every file parses as JSON and has the expected envelope shape.

    "Shape" includes the entries, not just the wrapper: every element of a
    collection must be a JSON object. A string or a number sitting in the
    list is malformed data, and every later check would otherwise have to
    skip it — which is how malformed entries used to pass validation
    vacuously.
    """
    issues: list[str] = []
    docs: dict[str, Any] = {}
    files = {
        "keywords.json": "keywords",
        "clauses.json": "clauses",
        "errors.json": "errors",
    }
    for filename, key in files.items():
        data, err = load_json(spec_dir / filename)
        if err:
            issues.append(err)
            docs[key] = []
            continue
        if not isinstance(data, dict) or not isinstance(data.get(key), list):
            issues.append(
                f"{filename}: expected an object with a \"{key}\" list at top level"
            )
            docs[key] = []
            continue
        for i, entry in enumerate(data[key]):
            if not isinstance(entry, dict):
                issues.append(
                    f"{filename}[{i}]: entry is not an object (got {type(entry).__name__})"
                )
        docs[key] = data[key]
    return (not issues, issues, docs)


def check_clause_ids(clauses: list[Any]) -> tuple[bool, list[str], set[str]]:
    """Check 2: clause ids are unique and match the strict format."""
    issues: list[str] = []
    seen: set[str] = set()
    valid_ids: set[str] = set()
    for i, clause in enumerate(clauses):
        if not isinstance(clause, dict) or "id" not in clause:
            issues.append(f"clauses.json[{i}]: missing \"id\" field")
            continue
        cid = clause["id"]
        if not isinstance(cid, str) or not CLAUSE_ID_RE.match(cid):
            issues.append(f"clauses.json[{i}]: id {cid!r} does not match {CLAUSE_ID_RE.pattern}")
            continue
        if cid in seen:
            issues.append(f"clauses.json: duplicate clause id {cid!r}")
            continue
        seen.add(cid)
        valid_ids.add(cid)
    return (not issues, issues, valid_ids)


def check_references(keywords: list[Any], errors: list[Any], clause_ids: set[str]) -> tuple[bool, list[str]]:
    """Check 3: every clause id referenced from keywords/errors exists in clauses.json."""
    issues: list[str] = []
    for kw in keywords:
        if not isinstance(kw, dict):
            continue
        name = kw.get("name", "<unnamed>")
        for cid in kw.get("clauses", []) or []:
            if cid not in clause_ids:
                issues.append(f"keywords.json: {name!r} references unknown clause {cid!r}")
    for err in errors:
        if not isinstance(err, dict):
            continue
        num = err.get("number", "<unnumbered>")
        cid = err.get("clause")
        if cid is not None and cid not in clause_ids:
            issues.append(f"errors.json: error {num!r} references unknown clause {cid!r}")
    return (not issues, issues)


def check_enums(keywords: list[Any], clauses: list[Any]) -> tuple[bool, list[str]]:
    """Check 4: evidence/status/scope enums hold only their allowed values."""
    issues: list[str] = []
    for c in clauses:
        if not isinstance(c, dict):
            continue
        cid = c.get("id", "<no id>")
        evidence = c.get("evidence")
        if evidence is not None and evidence not in EVIDENCE_VALUES:
            issues.append(f"clauses.json: {cid!r} has invalid evidence {evidence!r}")
        status = c.get("status")
        if status not in STATUS_VALUES:
            issues.append(f"clauses.json: {cid!r} has invalid status {status!r}")
    for kw in keywords:
        if not isinstance(kw, dict):
            continue
        name = kw.get("name", "<unnamed>")
        scope = kw.get("scope")
        if scope not in SCOPE_VALUES:
            issues.append(f"keywords.json: {name!r} has invalid scope {scope!r}")
    return (not issues, issues)


def check_evidence_status_invariant(clauses: list[Any]) -> tuple[bool, list[str]]:
    """Check 5: non-"absent" clauses must have non-null evidence and non-empty source."""
    issues: list[str] = []
    for c in clauses:
        if not isinstance(c, dict):
            continue
        cid = c.get("id", "<no id>")
        status = c.get("status")
        if status == "absent":
            continue
        evidence = c.get("evidence")
        source = c.get("source")
        if evidence is None:
            issues.append(f"clauses.json: {cid!r} has status {status!r} but evidence is null")
        if not source or not isinstance(source, str):
            issues.append(f"clauses.json: {cid!r} has status {status!r} but source is empty")
    return (not issues, issues)


def check_keyword_syntax_source_invariant(keywords: list[Any]) -> tuple[bool, list[str]]:
    """Check 6: a keyword with non-null syntax must cite where that syntax came from.

    Mirrors check_evidence_status_invariant's rule for clauses: syntax
    filled in from memory, with no citation, must be structurally
    impossible. A keyword with syntax left null (the inventory default)
    needs no source.
    """
    issues: list[str] = []
    for kw in keywords:
        if not isinstance(kw, dict):
            continue
        name = kw.get("name", "<unnamed>")
        syntax = kw.get("syntax")
        if syntax is None:
            continue
        source = kw.get("source")
        if not source or not isinstance(source, str):
            issues.append(f"keywords.json: {name!r} has non-null syntax but source is empty")
    return (not issues, issues)


def check_error_entries(errors: list[Any]) -> tuple[bool, list[str]]:
    """Check 7: every errors.json entry is complete, correctly typed, and cited.

    errors.json is the one companion file that asserts substantive facts —
    52 error numbers, their message text, and what raises them — so it is
    held to the same citation rule as clauses.json and keywords.json: a
    non-empty "source" naming where the row was read from. "number",
    "message" and "meaning" are required and typed, and numbers must be
    unique, so a half-written or duplicated row cannot slip through.
    """
    issues: list[str] = []
    seen: set[int] = set()
    for i, err in enumerate(errors):
        if not isinstance(err, dict):
            continue  # already reported by check_parses
        where = f"errors.json[{i}]"
        num = err.get("number")
        if not isinstance(num, int) or isinstance(num, bool):
            issues.append(f"{where}: \"number\" must be an integer, got {num!r}")
        else:
            where = f"errors.json: error {num}"
            if num in seen:
                issues.append(f"errors.json: duplicate error number {num}")
            seen.add(num)
        for field in ("message", "meaning", "source"):
            value = err.get(field)
            if not isinstance(value, str) or not value.strip():
                issues.append(f"{where}: \"{field}\" must be a non-empty string, got {value!r}")
    return (not issues, issues)


def check_in_scope_keywords_have_clauses(keywords: list[Any]) -> tuple[bool, list[str]]:
    """Check 8: every keyword with scope "in" references at least one clause.

    Deferred and out-of-scope keywords are exempt — nothing has been
    specified for them yet, so an empty "clauses" array is correct rather
    than a gap. A keyword declared in scope with no clause would let
    coverage look complete while the spec still says nothing about it, so
    this is structural (fails the build), not advisory.
    """
    issues: list[str] = []
    for kw in keywords:
        if not isinstance(kw, dict):
            continue
        if kw.get("scope") != "in":
            continue
        name = kw.get("name", "<unnamed>")
        if not kw.get("clauses"):
            issues.append(f"keywords.json: {name!r} is scope \"in\" but has no clauses")
    return (not issues, issues)


def extract_section_31_keywords(spec_md_path: Path) -> set[str] | None:
    """Parse backtick-quoted tokens from spec.md between §3.1 and §3.2. None if spec.md is absent."""
    try:
        text = spec_md_path.read_text(encoding="utf-8")
    except OSError:
        return None
    start = text.find("### 3.1 In scope")
    end = text.find("### 3.2", start if start >= 0 else 0)
    if start == -1 or end == -1:
        return set()
    section = text[start:end]
    return set(re.findall(r"`([^`]+)`", section))


def check_scope_coverage(spec_dir: Path, keywords: list[Any]) -> list[str]:
    """Check 9 (coverage, never fails): compare §3.1 keyword names against keywords.json."""
    lines: list[str] = []
    section_keywords = extract_section_31_keywords(spec_dir / "spec.md")
    if section_keywords is None:
        lines.append("COVERAGE scope-coverage: spec.md not found, skipped")
        return lines

    in_scope_entries = {
        kw.get("name") for kw in keywords if isinstance(kw, dict) and kw.get("scope") == "in"
    }
    missing = sorted(section_keywords - in_scope_entries)
    extra = sorted(in_scope_entries - section_keywords)

    lines.append(
        f"COVERAGE scope-coverage: {len(section_keywords) - len(missing)}/{len(section_keywords)} "
        f"§3.1 keywords present in keywords.json (scope=in)"
    )
    if missing:
        lines.append(f"  missing from keywords.json ({len(missing)}): {', '.join(missing)}")
    if extra:
        lines.append(
            f"  in keywords.json with scope=in but not listed in §3.1 ({len(extra)}): {', '.join(extra)}"
        )
    return lines
