'use strict';

// Asks the interpreter what version it is, once, at activation.
//
// WHY THIS EXISTS. Upgrading was never the hard part -- noticing was. A user
// can run a stale binary for hours with no signal, and the failure it produces
// does not point at the cause: extension 0.1.4 driving n88 0.1.1 gets an
// unknown-option error from `--immediate`, which reads as a broken extension
// rather than an old interpreter. One `--version` at startup turns that into a
// sentence.
//
// THE PAIRING RULE, stated here because a check needs something to compare
// against: the extension and the interpreter are released under one tag and
// carry the same version string, so extension X.Y.Z expects n88 X.Y.Z. An
// interpreter AHEAD of the extension is fine and says nothing -- new CLI
// features do not break an older editor. One BEHIND is what gets reported.
//
// IT NEVER INSTALLS ANYTHING. A downstream consumer's fixtures are byte-exact
// and the 0.1.1 -> 0.1.3 upgrade moved every PNG; an extension that quietly
// upgraded the binary underneath someone would rewrite their evidence between
// one test run and the next. Surface it, offer the instructions, and let the
// person decide.

// Numeric compare of dotted versions. Returns <0, 0, >0.
function compareVersions(a, b) {
  const pa = String(a).trim().split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).trim().split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

// The oldest interpreter that supports everything this extension drives:
// `-` and `--immediate` both landed in 0.1.3.
const MINIMUM = '0.1.3';

// Pure: given what the extension is and what `n88 --version` said, decide what
// to tell the user. `reported` is null when the interpreter could not be run.
function verdict(extensionVersion, reported) {
  if (reported === null || reported === undefined) {
    return {
      level: 'error',
      message:
        'n88basic: no interpreter found. The extension edits and checks BASIC, ' +
        'but running a program needs the n88 binary on your PATH.',
    };
  }
  const v = String(reported).trim();
  if (!/^\d+(\.\d+)*$/.test(v)) {
    // Not a version we understand. Say so rather than guessing it is fine:
    // a wrapper script that prints something else is a real possibility.
    return { level: 'info', message: `n88basic: could not read the interpreter's version (got "${v}").` };
  }
  if (compareVersions(v, MINIMUM) < 0) {
    return {
      level: 'warning',
      message:
        `n88basic: n88 ${v} is too old for this extension. Execute Buffer, ` +
        `Execute Selection and Immediate Statement need ${MINIMUM} or newer.`,
    };
  }
  if (compareVersions(v, extensionVersion) < 0) {
    return {
      level: 'info',
      message: `n88basic: extension ${extensionVersion}, interpreter ${v}. They are released together; upgrading n88 keeps them in step.`,
    };
  }
  return null; // equal, or the interpreter is ahead -- nothing to say
}

module.exports = { compareVersions, verdict, MINIMUM };

// ---------------------------------------------------------------- vscode side

const RELEASES = 'https://github.com/sajonaro/n88basic/releases/latest';

// Runs once per window. Failures here must never break activation: an
// interpreter that hangs, a wrapper that writes to stderr, a PATH with
// something surprising on it -- none of that should stop the editor's
// highlighting and diagnostics, which need no interpreter at all.
function registerVersionCheck(context) {
  const vscode = require('vscode');
  const { execFile } = require('child_process');
  const { interpreterCommand } = require('./session');

  const cmd = interpreterCommand(vscode.workspace.getConfiguration('n88basic'));
  const mine = (context && context.extension && context.extension.packageJSON
    && context.extension.packageJSON.version) || '0.0.0';

  execFile(cmd, ['--version'], { timeout: 5000 }, (err, stdout) => {
    const v = verdict(mine, err ? null : String(stdout));
    if (!v) return;
    const show =
      v.level === 'error' ? vscode.window.showErrorMessage
      : v.level === 'warning' ? vscode.window.showWarningMessage
      : vscode.window.showInformationMessage;
    show.call(vscode.window, v.message, 'How to upgrade').then((choice) => {
      if (choice === 'How to upgrade') {
        vscode.env.openExternal(vscode.Uri.parse(RELEASES));
      }
    });
  });
}

module.exports.registerVersionCheck = registerVersionCheck;
