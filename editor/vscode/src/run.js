'use strict';

// Run: n88basic.run executes the active buffer through the CLI in a VSCode
// terminal (design §8 -- "text in a terminal", no subprocess capture) and,
// if the program draws, offers to open the PNG the CLI writes beside the
// source file (bin/main.ml's write_png). The path/command logic is pure (no
// `require('vscode')` at module scope); registerRunCommand is the only part
// that touches vscode, and it require()s it lazily.

const path = require('path');

// Mirrors bin/main.ml's png_path_for: replace the last extension with
// .png, or just append .png if there is none.
function pngPathFor(filePath) {
  const ext = path.extname(filePath);
  const withoutExt = ext ? filePath.slice(0, -ext.length) : filePath;
  return withoutExt + '.png';
}

// Walks upward from `startDir` looking for dune-project, which marks the
// repository root the CLI's `opam env --switch=.` needs to be run from.
// Falls back to `startDir` itself if none is found, rather than throwing --
// the run command still fires, and the shell reports whatever going wrong
// looks like from there (design §8: no stack trace for a missing
// toolchain).
function findRepoRoot(startDir, existsSync) {
  let dir = startDir;
  for (;;) {
    if (existsSync(path.join(dir, 'dune-project'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return startDir;
    dir = parent;
  }
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

// The exact command docs/superpowers/specs/2026-08-16-n88basic-design.md
// §8 and this task specify, run with the repository root as cwd so
// `--switch=.` resolves.
function buildRunCommand(filePath) {
  return `eval $(opam env --switch=. --set-switch) && dune exec bin/main.exe -- ${shellQuote(filePath)}`;
}

const POLL_MS = 750;
const MAX_ATTEMPTS = 30; // ~22s: generous for a dune build, bounded so it can't poll forever

// After sending the run command, watches for the PNG the CLI would write
// (mtime at or after `startTime`, so a stale PNG from a previous run isn't
// mistaken for this one) and offers to open it. Not every program draws, so
// giving up silently after MAX_ATTEMPTS is the correct outcome, not a bug.
function offerPngWhenReady(vscode, pngPath, startTime) {
  const fs = require('fs');
  let attempts = 0;
  const timer = setInterval(() => {
    attempts++;
    fs.stat(pngPath, (err, stats) => {
      if (!err && stats.mtimeMs >= startTime) {
        clearInterval(timer);
        vscode.window
          .showInformationMessage(`n88basic: wrote ${path.basename(pngPath)}`, 'Open PNG')
          .then((choice) => {
            if (choice === 'Open PNG') {
              vscode.commands.executeCommand('vscode.open', vscode.Uri.file(pngPath));
            }
          });
      } else if (attempts >= MAX_ATTEMPTS) {
        clearInterval(timer);
      }
    });
  }, POLL_MS);
}

function registerRunCommand(context) {
  const vscode = require('vscode');
  const fs = require('fs');

  const disposable = vscode.commands.registerCommand('n88basic.run', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'n88basic') {
      vscode.window.showWarningMessage('n88basic: open a .bas or .n88 file to run it.');
      return;
    }
    const document = editor.document;
    if (document.isDirty) await document.save();

    const filePath = document.fileName;
    const repoRoot = findRepoRoot(path.dirname(filePath), fs.existsSync);
    const terminal =
      vscode.window.terminals.find((t) => t.name === 'n88basic') ||
      vscode.window.createTerminal({ name: 'n88basic', cwd: repoRoot });
    terminal.show();
    const startTime = Date.now();
    terminal.sendText(buildRunCommand(filePath));

    offerPngWhenReady(vscode, pngPathFor(filePath), startTime);
  });
  context.subscriptions.push(disposable);
}

module.exports = {
  pngPathFor,
  findRepoRoot,
  buildRunCommand,
  registerRunCommand,
};
