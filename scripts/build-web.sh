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

# The project keeps a local opam switch. A caller who has not run
# `eval $(opam env)` still has one right here -- but putting ./_opam/bin on
# PATH is NOT enough: dune finds its libraries through the switch's
# environment, not its bin directory, so it would then fail with "Library
# js_of_ocaml not found" while ocamlfind could see it perfectly well. Ask opam
# for the environment instead of assembling it by hand.
if command -v dune >/dev/null 2>&1; then
  :                                   # the caller already activated a switch
elif command -v opam >/dev/null 2>&1 && [ -d ./_opam ]; then
  eval "$(opam env --switch=. --set-switch)"
elif command -v opam >/dev/null 2>&1; then
  eval "$(opam env)" 2>/dev/null || true
fi

if ! command -v dune >/dev/null 2>&1; then
  echo "dune is not available." >&2
  if [ -d ./_opam ]; then
    echo "This tree has a switch at ./_opam -- activate it with:" >&2
    echo "    eval \$(opam env --switch=. --set-switch)" >&2
  else
    echo "Create one with:" >&2
    echo "    opam switch create . --deps-only" >&2
  fi
  exit 1
fi

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
