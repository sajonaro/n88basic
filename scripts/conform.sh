#!/usr/bin/env bash
# conform.sh -- run the conformance corpus through an n88 EXECUTABLE.
#
# WHY THIS EXISTS. test/test_conformance.ml links N88basic.Interp and runs
# the cases in process. That proves the LIBRARY obeys the spec; it says
# nothing about the artifact we publish. The released binary is a different
# build (release profile, native glibc) and the container is a different
# libc again (Alpine/musl), and neither had ever been run against the corpus
# -- only against one hand-written smoke program. This closes that gap: it
# takes any n88 on disk and asks whether the thing we ship behaves like the
# thing we tested.
#
# Usage:  scripts/conform.sh /path/to/n88
#         scripts/conform.sh 'docker run --rm -i -v CASEDIR:/work IMAGE'
#
# Exit status is 0 only if every runnable case matches.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASES="$ROOT/test/conformance"
N88="${1:?usage: conform.sh /path/to/n88}"

[ -x "$N88" ] || { echo "not an executable: $N88" >&2; exit 2; }

pass=0; fail=0; failed=()
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

for bas in "$CASES"/*.bas; do
  name="$(basename "$bas" .bas)"
  exp="$CASES/$name.expected"
  # Framebuffer cases assert a digest of the display list, which is an
  # in-process structure -- a binary emits a PNG instead, so this cannot
  # decide them. They are NAMED at the end rather than passed over quietly.
  [ -f "$exp" ] || continue

  # Run in a scratch directory: a drawing case writes a PNG beside its
  # source, and the corpus must not be dirtied by being checked.
  cp "$bas" "$work/$name.bas"
  # The two streams are captured SEPARATELY and then concatenated, stdout
  # first. Merging them with 2>&1 in the child looks simpler and is wrong:
  # ordering between the streams is not preserved when the child is a
  # `docker run` (the daemon multiplexes them), so six cases that print and
  # then fail reported a mismatch against the very image they were byte
  # -identical to. Concatenating in a fixed order also matches what
  # test_conformance.ml does in process -- stdout, then the error's text.
  if [ -f "$CASES/$name.stdin" ]; then
    "$N88" "$work/$name.bas" < "$CASES/$name.stdin" > "$work/out" 2> "$work/err"
  else
    "$N88" "$work/$name.bas" < /dev/null > "$work/out" 2> "$work/err"
  fi
  # The interpreter reports a written PNG on stderr; that is a progress
  # notice, not program output, and no .expected records it. Its path
  # differs between a host run and a container run, so it cannot be compared
  # even in principle.
  got="$(cat "$work/out"; grep -v '^wrote .*\.png$' "$work/err")"

  if [ "$got" = "$(cat "$exp")" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); failed+=("$name")
    printf 'FAIL %s\n' "$name"
    diff <(cat "$exp") <(printf '%s\n' "$got") | sed 's/^/     /' | head -12
  fi
done

skipped=$(ls "$CASES"/*.digest 2>/dev/null | wc -l | tr -d ' ')
echo
echo "$pass of $((pass + fail)) text cases match through $(basename "$N88")."
if [ "$skipped" -gt 0 ]; then
  echo "$skipped framebuffer cases are NOT checked here -- they assert a digest of"
  echo "an in-process display list, which a binary does not expose. Saying so"
  echo "because a runner that dropped them silently would report a coverage it"
  echo "has not earned."
fi
[ "$fail" -eq 0 ] || { echo; echo "Failed: ${failed[*]}"; exit 1; }
