#!/usr/bin/env python3
"""Checks the release-tag rule. Run: python3 tools/test_check_version_bump.py"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from check_version_bump import check, parse

failures = []
def ok(cond, label):
    print(f"{'ok  ' if cond else 'FAIL'}: {label}")
    if not cond:
        failures.append(label)

ok(check("v0.2.0", "v0.1.4") == [], "v0.2.0 follows v0.1.4")
# 9 is not a carry digit: the rule is "bump the minor", so v0.9.3 is followed
# by v0.10.0. A major bump is a different decision and this rule does not make
# it -- which is worth pinning, because "surely 0.9 goes to 1.0" is exactly the
# assumption that would quietly change the scheme.
ok(check("v0.10.0", "v0.9.3") == [], "v0.9.3 is followed by v0.10.0, not v1.0.0")
ok(check("v1.0.0", "v0.9.3") != [], "a MAJOR bump is refused; this rule does not make that call")
ok(check("v0.1.5", "v0.1.4") != [], "a PATCH bump is refused -- the rule being enforced")
ok(check("v0.3.0", "v0.1.4") != [], "skipping a minor is refused")
ok(check("v0.2.1", "v0.1.4") != [], "a minor bump with a non-zero patch is refused")
ok(check("v0.1.4", "v0.1.4") != [], "re-tagging the same version is refused")
ok(check("v0.1.0", "v0.2.0") != [], "going backwards is refused")
ok(check("0.2.0", "v0.1.4") != [], "a tag without its v is refused")
ok(check("v0.2", "v0.1.4") != [], "a two-component tag is refused")
ok(check("v0.1.0", None) == [], "a first release ending .0 is fine")
ok(check("v0.1.1", None) != [], "a first release not ending .0 is refused")
# The message has to name the tag to use, or the check is a riddle.
ok("v0.2.0" in check("v0.1.5", "v0.1.4")[0], "the refusal names the correct next tag")
ok(parse("v12.34.56") == (12, 34, 56), "multi-digit components parse")

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
