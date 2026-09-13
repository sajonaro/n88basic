#!/bin/sh
# build-web.sh -- build the browser console, and say what actually went wrong.
#
# WHY THIS IS A SCRIPT. The Makefile used to run `dune build @web/web
# 2>/dev/null` and, on any failure at all, print "the web console needs
# js_of_ocaml". That message can only say one thing, so it said it when the
# real fault was `dune: command not found` -- sending someone to install a
# library they already had. A diagnostic that cannot be wrong about the cause
# is a diagnostic that is wrong whenever the cause is different.
#
# So: find dune, check the prerequisite that is actually optional, and
# otherwise show the build's own error rather than a guess about it.
set -eu
cd "$(dirname "$0")/.."
. "$(dirname "$0")/lib/switch.sh"

# js_of_ocaml is the one genuinely optional dependency: web/dune marks the
# executable (optional), so a tree without it still builds and tests the
# interpreter. Check it by name instead of inferring it from a failure -- and
# if it is missing, offer Docker rather than a toolchain lecture, because
# someone who only wants to look at the console should not have to install a
# compiler back end to do it.
if ! ocamlfind list 2>/dev/null | grep -q '^js_of_ocaml '; then
  if command -v docker >/dev/null 2>&1; then
    echo "js_of_ocaml is not installed -- building the console in Docker instead."
    exec ./scripts/build-web-docker.sh
  fi
  echo "The browser console needs js_of_ocaml:" >&2
  echo "    opam install js_of_ocaml js_of_ocaml-compiler" >&2
  echo "or install Docker and this script will build it for you." >&2
  exit 1
fi

# Anything else: let the build speak for itself.
dune build @web/web
node tools/check_web.js
python3 tools/check_svg.py
