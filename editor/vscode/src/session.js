'use strict';

// Session: the three "execute this" commands, and the interpreter-locating
// logic they share with src/run.js.
//
// WHY THREE COMMANDS AND NOT ONE. "Execute the current line" means something
// in Python that it does not mean in BASIC. Line 30 of a numbered program has
// no DIM, no DATA and none of the assignments above it, so running it alone is
// almost never what anyone wants. The manual draws the same line: printed
// pp.4-6 separate DIRECT mode, where a statement stands alone, from PROGRAM
// mode, where numbered lines are stored and RUN executes them in order. So:
//
//   executeBuffer     -- the whole document, as a program (n88 -)
//   executeSelection  -- the selected lines, as a program in their own right
//   immediateStatement-- one unnumbered statement against a LIVE session
//                        (n88 --immediate), where variables persist
//
// The third is the one that needs the interpreter's immediate mode rather than
// a fresh process per statement: a session that replayed earlier assignments
// ahead of each new one would be an illusion, and would diverge the moment a
// statement had a side effect.

const path = require('path');

// A configured path wins; otherwise "n88", which is on PATH after either the
// prebuilt binary or `opam install n88basic`. This used to be hard-coded as
// `eval $(opam env --switch=.) && dune exec bin/main.exe`, which works ONLY
// inside a checkout of the interpreter's own repository -- so the published
// extension could not run anything for anyone who had merely installed it.
function interpreterCommand(config) {
  const configured = config && config.get && config.get('interpreterPath');
  return configured && String(configured).trim() ? String(configured).trim() : 'n88';
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

// The lines a selection covers, as a program in their own right. An empty or
// single-cursor selection means the whole document: "run the selection" with
// nothing selected is a request to run everything, not to run nothing.
function selectedProgram(text, selectionText) {
  const chosen = selectionText && selectionText.trim() ? selectionText : text;
  return chosen.replace(/\s+$/, '') + '\n';
}

// Statements typed at the prompt are fed to a live `n88 --immediate`, so what
// the extension sends is exactly what a person would type. Numbered lines are
// stored by the interpreter itself; nothing here has to know the difference.
function immediateInput(statement) {
  return String(statement).replace(/\r?\n+$/, '') + '\n';
}

module.exports = { interpreterCommand, shellQuote, selectedProgram, immediateInput };

// ---------------------------------------------------------------- vscode side

// Output goes to an OutputChannel rather than a terminal. A terminal is right
// for `run`, which is a person watching a program; these are editor actions
// whose result should land next to the code without stealing focus, and a
// channel can be written to from a long-lived process.
function channel(vscode, state) {
  if (!state.channel) state.channel = vscode.window.createOutputChannel('N88-BASIC');
  return state.channel;
}

// One program, one process: text in on stdin, output to the channel. This is
// what `n88 -` bought -- before it, every one of these would have had to
// marshal a temp file, and an editor does this often.
function runProgram(vscode, state, source, cwd) {
  const { spawn } = require('child_process');
  const out = channel(vscode, state);
  const cmd = interpreterCommand(vscode.workspace.getConfiguration('n88basic'));
  out.show(true);
  let child;
  try {
    child = spawn(cmd, ['-'], { cwd });
  } catch (e) {
    out.appendLine(`n88basic: cannot run ${cmd}: ${e.message}`);
    return;
  }
  child.on('error', (e) => {
    out.appendLine(`n88basic: cannot run ${cmd}: ${e.message}`);
    out.appendLine('Set n88basic.interpreterPath, or install n88 on your PATH.');
  });
  child.stdout.on('data', (d) => out.append(d.toString()));
  child.stderr.on('data', (d) => out.append(d.toString()));
  child.stdin.end(source);
}

// The live session. One `n88 --immediate` per window, kept until the extension
// is disposed, because that process IS the state: killing it between
// statements would put us back to replaying assignments.
function immediateSession(vscode, state, cwd) {
  if (state.session && !state.session.killed) return state.session;
  const { spawn } = require('child_process');
  const out = channel(vscode, state);
  const cmd = interpreterCommand(vscode.workspace.getConfiguration('n88basic'));
  const child = spawn(cmd, ['--immediate'], { cwd });
  child.on('error', (e) => {
    out.appendLine(`n88basic: cannot start a session with ${cmd}: ${e.message}`);
    state.session = null;
  });
  child.on('exit', () => { state.session = null; });
  child.stdout.on('data', (d) => out.append(d.toString()));
  child.stderr.on('data', (d) => out.append(d.toString()));
  state.session = child;
  return child;
}

function registerSessionCommands(context) {
  const vscode = require('vscode');
  const state = { channel: null, session: null };

  const docAndCwd = () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'n88basic') return null;
    return { editor, cwd: path.dirname(editor.document.fileName) };
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('n88basic.executeBuffer', () => {
      const ctx = docAndCwd();
      if (!ctx) return vscode.window.showWarningMessage('n88basic: open a BASIC file first.');
      runProgram(vscode, state, ctx.editor.document.getText(), ctx.cwd);
    }),

    vscode.commands.registerCommand('n88basic.executeSelection', () => {
      const ctx = docAndCwd();
      if (!ctx) return vscode.window.showWarningMessage('n88basic: open a BASIC file first.');
      const sel = ctx.editor.document.getText(ctx.editor.selection);
      runProgram(vscode, state, selectedProgram(ctx.editor.document.getText(), sel), ctx.cwd);
    }),

    vscode.commands.registerCommand('n88basic.immediateStatement', async () => {
      const statement = await vscode.window.showInputBox({
        prompt: 'N88-BASIC immediate statement',
        placeHolder: 'PRINT 21+6-5',
      });
      if (!statement) return;
      const ctx = docAndCwd();
      const child = immediateSession(vscode, state, ctx ? ctx.cwd : undefined);
      channel(vscode, state).show(true);
      if (child && child.stdin && child.stdin.writable) child.stdin.write(immediateInput(statement));
    }),

    vscode.commands.registerCommand('n88basic.endSession', () => {
      if (state.session) { state.session.stdin.end(); state.session = null; }
      channel(vscode, state).appendLine('-- session ended --');
    }),

    { dispose: () => { if (state.session) state.session.kill(); } }
  );
}

module.exports.registerSessionCommands = registerSessionCommands;
