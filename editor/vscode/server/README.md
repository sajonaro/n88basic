# Vendored runtime dependencies

`editor/vscode/node_modules/` is **committed on purpose** (Alex's ruling,
2026-08-17). The extension installs by copying a directory and has no build
step, and that is the property that matters: the extension was silently dead
for weeks because the installed copy was stale, and an `npm install` step is
the same class of hazard — skippable, half-completable, and quiet when it
fails. 3.1MB in git is the cheaper failure. Bundling to one file with esbuild
was considered and rejected for the same reason: it adds the build step.

## What is pinned, and by what

`package.json`'s `dependencies` pin the two protocol halves to **exact**
versions, not ranges:

| Package | Pin | Why |
| --- | --- | --- |
| `vscode-languageclient` | `8.1.0` | declares `vscode ^1.67.0`, which the extension's own `engines.vscode` (`^1.75.0`) satisfies. 9.x needs `^1.82.0` and 10.x needs `^1.91.0` — either would raise the minimum editor version for nothing this project needs |
| `vscode-languageserver` | `8.1.0` | must match the client's major |
| `vscode-languageserver-textdocument` | `^1.0.13` | independent of the protocol version |

## Refreshing them

Vendored dependencies rot silently — a fact true when committed, with nothing
prompting a re-read. That is this project's recurring failure in another
costume, so the procedure is written down rather than remembered:

```sh
cd editor/vscode
rm -rf node_modules package-lock.json
npm install --omit=dev            # production only, or the tree balloons
rm -rf node_modules/.bin          # CLI shims: symlinks, and nothing launches them
node tools/test-manifest.js       # walks the graph, asserts 0 symlinks
node tools/test-language-server.js
```

**Never commit `node_modules/.bin`.** It contains symlinks, and git records a
symlink as mode `120000` and recreates it on checkout. A tracked symlink is
what destroyed the opam switch on 2026-08-17. `tools/test-manifest.js` fails if
any symlink appears anywhere in the vendored tree; `git ls-files -s` will show
you the modes directly.

Raising the client past 8.x means raising `engines.vscode` to match. Check the
new client's own `engines` field before assuming it is a drop-in.
