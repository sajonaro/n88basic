# Changelog

All notable changes to this specification are recorded here. Format is
free-form but factual — this is a log of what was established, not a
narrative.

## 0.1.0 — 2026-08-16

Establishes the specification's scope and sources; does not yet write clause
bodies (see `spec.md`, "This version fixes scope and sources").

- **Scope fixed.** `spec.md` §3 sets the in-scope keyword inventory, the
  deferred list, and the out-of-scope list for N88-BASIC(86) on the PC-9801.
- **Sources recorded.** `sources.md` names the four reference sources and
  the citation procedure, including a page map for the primary Reference
  Manual scan (PDF page ↔ printed folio, with verified anchors) and the
  known limits of the page maps for the two PC-8801 secondary sources.
- **Keyword inventory populated.** `keywords.json` covers every keyword
  named in `spec.md` §3.1/§3.2/§3.3, each entry carrying kind, scope, and a
  one-line summary; syntax and governing clauses are filled in as the
  clause bodies are written in later versions. Entries are not one per
  keyword *name*: `GET`, `PUT`, and `PAINT` each name two features that sit
  in different scopes, so they appear only under qualified names —
  `GET (graphics)` and `GET (file)`, and likewise for the others. The
  file's `naming` field states that convention.
- **Clause stubs created.** `clauses.json` carries one stub clause per
  in-scope rule, `status: "absent"`, ready to be filled with evidence grade,
  source citation, and rule text subsystem by subsystem.
- **Error table populated.** `errors.json` records the error codes listed
  in the Reference Manual's error-message appendix (Appendix A, printed
  pages 181–188, PDF pages 190–197): 52 entries, each with the error
  number, the exact message text the interpreter prints, an own-words
  statement of the condition that raises it, and a `source` naming the
  printed and PDF page it was read from. Governing clauses are left `null`
  except where a clause already states the exact behaviour
  (`NUM.OVERFLOW`, `NUM.DIV-BY-ZERO`, `ERR.RESUME`); the rest are linked
  once the error-handling clauses are written.
- **The error table is not the complete set of error codes.** Four codes
  (21, 24, 25, 28) share the message "Unprintable error", and the manual
  heads that entry with those four followed by 他 — "and others". Further
  codes carry no message of their own and are not listed anywhere in the
  appendix, so the 52 entries are a floor, not the whole language. The four
  entries are marked `"partial": true` with a `note` saying so. (The
  appendix also ends with a code 51 marked as reserved to the system, with
  no message and no cause given; it is not recorded as an error entry.)
- **Checker in place.** `tools/check_spec.py` validates all three
  companion files structurally on every change, including that every
  error entry is cited, typed, and uniquely numbered.
