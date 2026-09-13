# scripts/

**Things you run.** Checks and measurements live in [`tools/`](../tools/).

Names follow their intent — `build-` produces something, `check-` verifies
something, `install-`/`package-` delivers something.

| | |
| --- | --- |
| `build-interpreter.sh` | the `n88` binary and the editor's checker bundle |
| `build-web-console.sh` | the browser console, falling back to Docker when `js_of_ocaml` is missing |
| `build-web-console-in-docker.sh` | the browser console using only Docker — no OCaml on this machine |
| `serve-web-console.sh` | serve the built console on localhost, from a container, until you stop it |
| `check-everything.sh` | every gate, in Docker — the one pipeline, and the same one CI runs |
| `check-conformance.sh` | run the corpus through **any** `n88` — a release binary, the container, a local build. This is how published artifacts are proven to run the same language |
| `check-invariants.sh` | the tripwires for mistakes this codebase is prone to — `basic/` doing I/O, a manual scan getting committed, a local path in the spec |
| `install-from-source.sh` | build this checkout and put `n88` on your PATH |
| `install-extension.sh` | install the extension by copying the directory, for machines without `vsce` |
| `package-extension.sh` | package the extension as a `.vsix` |
| `n88-docker` | present the container as a plain executable, so anything that can run `n88` can drive the image instead |
| `lib/activate-opam-switch.sh` | sourced by the others; finds dune when the caller has not activated a switch |

Everything here also has a `make` target. The scripts work without `make`.

## Not here

[`../install.sh`](../install.sh) is the one for **users**: it downloads a
released binary, upgrades in place, and can remove it again. It builds nothing.
`install-from-source.sh` is its opposite. They used to share a name, which
helped nobody.
