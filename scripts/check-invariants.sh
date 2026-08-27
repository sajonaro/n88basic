#!/bin/sh
# Project invariants: cheap checks for the mistakes this codebase is prone to.
# Each is a tripwire, not a proof. Run by scripts/test.sh.
set -eu
cd "$(dirname "$0")/.."

fail=0
report() { printf '  %-26s %s\n' "$1" "$2"; }

# 1. No manual prose copied into the specification.
#
#    The spec restates the dialect's rules and cites the page they came from;
#    it does not reproduce the manual. A long run of Japanese in spec/ means
#    prose was copied rather than restated, which is both a citation problem
#    and a copyright one. Short quotations -- a keyword, an error message, a
#    phrase pinning an exact rule -- fall well under the threshold.
if python3 - <<'PY'
import re, subprocess, sys
files = subprocess.run(["git","ls-files","spec/"],capture_output=True,text=True).stdout.split()
bad = []
for f in files:
    try: t = open(f, encoding="utf-8").read()
    except Exception: continue
    for m in re.finditer(r"[぀-ヿ㐀-䶵一-鿿]{40,}", t):
        bad.append(f"{f}: {len(m.group(0))} characters: {m.group(0)[:40]}...")
for b in bad[:5]: print("   ", b)
sys.exit(1 if bad else 0)
PY
then
  report "no-manual-prose" "ok"
else
  report "no-manual-prose" "FAIL - a long run of Japanese in spec/ (copied prose?)"
  fail=1
fi

# 2. Sources are cited by name and link, never by local path.
#
#    A citation naming a file on someone's disk cannot be checked by anyone
#    else. The scans are not redistributed; spec/sources.md links to them.
if git grep -nE '\.pdf' -- 'spec/*.md' 'spec/*.json' >/dev/null 2>&1; then
  report "sources-by-link-only" "FAIL - a local PDF path appears in spec/"
  fail=1
else
  report "sources-by-link-only" "ok"
fi

# 2b. No scan is ever tracked, anywhere in the tree.
#
#     The manual scans are copyrighted and were removed from this repository
#     and its history when it was made public. They still have to be READ to
#     write a clause, so they live outside the working tree -- which makes an
#     accidental `git add` the realistic failure, not a deliberate one. The
#     .gitignore is the first line; this is the one that fails the build.
if git ls-files | grep -qiE '\.(pdf|djvu)$'; then
  report "no-scans-tracked" "FAIL - a scan is tracked by git"
  git ls-files | grep -iE '\.(pdf|djvu)$' | head -5
  fail=1
else
  report "no-scans-tracked" "ok"
fi

# 3. The interpreter library performs no I/O.
#
#    The load-bearing rule of the design: because basic/ neither reads nor
#    writes anything, one interpreter serves the command-line runner, the
#    editor's checker, the conformance runner and a js_of_ocaml build. Break
#    this and the js build is the first thing to fail, confusingly.
if git grep -nE 'Printf\.printf|Printf\.eprintf|print_string|print_endline|print_newline|prerr_|read_line|input_line|open_out|open_in|Unix\.|stdout|stdin' -- 'basic/*.ml' >/dev/null 2>&1; then
  report "basic-does-no-io" "FAIL - basic/ performs I/O"
  git grep -nE 'Printf\.printf|print_string|open_in|open_out|Unix\.' -- 'basic/*.ml' | head -5
  fail=1
else
  report "basic-does-no-io" "ok"
fi

# 4. No absolute paths from a developer's machine.
#
#    A test once hardcoded a path to one machine's Python and so skipped
#    silently everywhere else, leaving a round-trip check inert for weeks.
if git grep -nE '"/(home|tmp|Users)/' -- '*.ml' 'tools/*.py' 'scripts/*.sh' >/dev/null 2>&1; then
  report "no-absolute-paths" "FAIL - a machine-specific absolute path is hardcoded"
  git grep -nE '"/(home|tmp|Users)/' -- '*.ml' 'tools/*.py' 'scripts/*.sh' | head -5
  fail=1
else
  report "no-absolute-paths" "ok"
fi

exit $fail
