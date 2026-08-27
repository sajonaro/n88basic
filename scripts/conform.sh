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

echo
echo "$pass of $((pass + fail)) text cases match through $(basename "$N88")."

# The drawing cases assert a digest of the in-process display list, which a
# binary does not expose -- so each carries a .pnghash as well, the sha256 of
# the PNG it produces. That is a weaker claim than the digest (it says
# "unchanged", never "correct") and it is the one decidable from outside a
# process, which is what makes a released binary and a container checkable at
# all. See tools/png_hashes.py.
#
# NOTE that a .pnghash pins the ENCODER as well as the drawing, so an older
# artifact can fail these while drawing exactly the same picture -- that is
# what happened across the compression change, where every hash moved and no
# display-list digest did. A drawing mismatch against a PREVIOUS release is a
# question ("did the encoder change?"), not automatically a defect; against
# the build you just made from this tree, it is a defect.
dpass=0; dfail=0
for dg in "$CASES"/*.digest; do
  [ -e "$dg" ] || continue
  name="$(basename "$dg" .digest)"
  want="$CASES/$name.pnghash"
  if [ ! -f "$want" ]; then
    echo "FAIL $name (drawing): no .pnghash -- run tools/png_hashes.py --write"
    dfail=$((dfail + 1)); failed+=("$name"); continue
  fi
  cp "$CASES/$name.bas" "$work/$name.bas"
  rm -f "$work/$name.png"
  "$N88" "$work/$name.bas" >/dev/null 2>&1
  if [ ! -f "$work/$name.png" ]; then
    echo "FAIL $name (drawing): drew no PNG"
    dfail=$((dfail + 1)); failed+=("$name"); continue
  fi
  got="$(sha256sum "$work/$name.png" | cut -d" " -f1)"
  if [ "$got" = "$(cat "$want" | tr -d "[:space:]")" ]; then
    dpass=$((dpass + 1))
  else
    echo "FAIL $name (drawing): PNG hash ${got:0:16}, expected $(cut -c1-16 "$want")"
    dfail=$((dfail + 1)); failed+=("$name")
  fi
done
echo "$dpass of $((dpass + dfail)) drawing cases match by PNG hash."

fail=$((fail + dfail))
[ "$fail" -eq 0 ] || { echo; echo "Failed: ${failed[*]}"; exit 1; }
