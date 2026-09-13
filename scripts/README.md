# scripts/

**Things you run.** Checks and measurements live in [`tools/`](../tools/) — that
is the whole rule, and it is why `conform.sh` sits here (you point it at a
binary you want to try) while `check_web.js` sits there (CI runs it and nobody
else does).

Everything here also has a `make` target; the scripts work without `make`.

| Script | What it does |
| --- | --- |
| `build.sh` | build the interpreter and the editor's checker bundle |
| `test.sh` | everything that can fail: unit tests, conformance, spec gates, example programs |
| `conform.sh` | run the conformance corpus through **any** `n88` — a release binary, the container, a local build. This is how the published artifacts are proven to run the same language |
| `check-invariants.sh` | the cheap tripwires for mistakes this codebase is prone to — `basic/` doing I/O, a scan getting committed, a local path in the spec |
| `build-web.sh` | build the browser console, with an honest message when it cannot |
| `build-web-docker.sh` | build the browser console using only Docker — no OCaml, no opam, no js_of_ocaml |
| `install-from-source.sh` | build this checkout and put `n88` on your PATH |
| `package-extension.sh` | package the VS Code extension as a `.vsix` |
| `install-extension.sh` | install the extension by copying the directory, for machines without `vsce` |
| `n88-docker` | present the container as a plain executable, so anything that can run `n88` can drive the image instead |

## Not here

**[`../install.sh`](../install.sh)** is the one for users: it downloads a
released binary, upgrades in place, and can remove it again. It does not build
anything. `scripts/install-from-source.sh` is its opposite — it builds from this
checkout and installs no release. They used to share a name, which helped
nobody.
