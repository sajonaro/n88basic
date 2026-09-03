#!/bin/sh
# check_interactive_flush.sh -- the prompt must be visible BEFORE the answer.
#
# WHY THIS IS NOT A CONFORMANCE CASE. The corpus compares bytes, and the bytes
# were never wrong: a program whose stdout is captured to a file produces a
# perfect file whether or not it flushed before blocking. The defect is in WHEN
# the bytes arrive, and the only observer who can see it is a person waiting at
# a terminal. A fixture capturing stdout is precisely the case where full
# buffering is correct, so no fixture this project has could ever have caught
# it -- which is how it shipped through five releases.
#
# So this measures instead of comparing: it starts the interpreter with input
# that will not arrive for a while, and asserts the prompt is already there.
#
# Usage:  tools/check_interactive_flush.sh [path-to-n88]
set -eu
N88="${1:-./_build/default/bin/main.exe}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail=0

check() {
  name="$1"; program="$2"; expect="$3"
  printf '%s' "$program" > "$work/p.bas"
  : > "$work/out"
  # The answer arrives after 3 seconds; the prompt must not wait for it.
  ( sleep 3; printf '7\n' ) | "$N88" "$work/p.bas" > "$work/out" 2>/dev/null &
  pid=$!
  sleep 1
  early="$(cat "$work/out")"
  wait "$pid" 2>/dev/null || true
  if printf '%s' "$early" | grep -q "$expect"; then
    echo "ok  : $name -- prompt visible one second in, three before the answer"
  else
    echo "FAIL: $name -- nothing on stdout before the answer arrived"
    echo "      expected to find: $expect"
    echo "      had: [$early]"
    fail=1
  fi
}

check "INPUT with a prompt" \
  '10 PRINT "EARLY"
20 INPUT "X"; X
' 'X?'

check "bare INPUT" \
  '10 PRINT "EARLY"
20 INPUT X
' 'EARLY'

check "LINE INPUT" \
  '10 PRINT "EARLY"
20 LINE INPUT "NAME"; N$
' 'NAME'

[ "$fail" -eq 0 ] || { echo; echo "The interpreter is not flushing stdout before it blocks on stdin."; exit 1; }
echo
echo "stdout is flushed at the point of blocking, so a prompt is never invisible."
