# switch.sh -- put dune and the OCaml toolchain on PATH. Source it, don't run it.
#
#   . "$(dirname "$0")/lib/switch.sh"
#
# WHY THIS IS SHARED. Every script here that builds anything needs an activated
# opam switch, and until now they each handled that differently or not at all:
# two had their own copy of the logic and four just called `dune` and failed
# with "command not found" when the caller had not run `eval $(opam env)`.
# That is the bug that made `make wc` tell people to install js_of_ocaml when
# the real fault was a missing switch.
#
# PATH IS NOT ENOUGH, which is the part that catches people. dune resolves
# LIBRARIES through the switch environment, not through its own location, so
# putting ./_opam/bin on PATH gets you a dune that then fails with "Library
# js_of_ocaml not found" while ocamlfind lists it perfectly well. Ask opam for
# the environment instead of assembling it by hand.

n88_activate_switch() {
  # Already usable: the caller has a switch, leave it alone.
  command -v dune >/dev/null 2>&1 && return 0

  if command -v opam >/dev/null 2>&1; then
    if [ -d ./_opam ]; then
      eval "$(opam env --switch=. --set-switch 2>/dev/null)" || true
    else
      eval "$(opam env 2>/dev/null)" || true
    fi
  fi

  command -v dune >/dev/null 2>&1 && return 0

  echo "dune is not available." >&2
  if [ -d ./_opam ]; then
    echo "This tree has a switch at ./_opam -- activate it with:" >&2
    echo "    eval \$(opam env --switch=. --set-switch)" >&2
  else
    echo "Create one with:" >&2
    echo "    opam switch create . --deps-only" >&2
  fi
  return 1
}

n88_activate_switch
