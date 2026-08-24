'use strict';

// Diagnostics: checks the active n88basic document on open/change/save and
// publishes the result through a vscode.DiagnosticCollection. The check
// itself lives in editor/lsp/ and is compiled to
// editor/vscode/media/n88basic-check.js by a dune rule -- see that file and
// docs/superpowers/specs/2026-08-16-n88basic-design.md §8 for why this
// calls the checker in-process instead of running a language server (LSP
// needs vscode-languageclient from npm, which is unavailable here).
//
// `require('vscode')` is deferred into registerDiagnostics so this file
// still loads under plain node (nothing here is pure enough to unit-test
// beyond what tools/test-diagnostics.js already covers by exercising the
// compiled bundle directly).

const path = require('path');

const LANGUAGE_ID = 'n88basic';
const DEBOUNCE_MS = 300;

// The bundle exports a single function, n88basicCheck(source) -> diagnostic[],
// where each diagnostic is { line, startCol, endCol, severity, message, code }
// with a 0-based line. See editor/lsp/js_main.ml for the calling convention.
function loadChecker() {
  const bundle = require(path.join(__dirname, '..', 'media', 'n88basic-check.js'));
  return bundle.n88basicCheck;
}

function registerDiagnostics(context) {
  const vscode = require('vscode');

  const SEVERITY = {
    error: vscode.DiagnosticSeverity.Error,
    warning: vscode.DiagnosticSeverity.Warning,
  };

  function toDiagnostic(d) {
    const range = new vscode.Range(d.line, d.startCol, d.line, d.endCol);
    const severity = SEVERITY[d.severity] !== undefined ? SEVERITY[d.severity] : vscode.DiagnosticSeverity.Error;
    const diagnostic = new vscode.Diagnostic(range, d.message, severity);
    diagnostic.source = 'n88basic';
    if (d.code) diagnostic.code = d.code;
    return diagnostic;
  }

  const check = loadChecker();
  const diagnostics = vscode.languages.createDiagnosticCollection(LANGUAGE_ID);
  context.subscriptions.push(diagnostics);

  // One debounce timer per open document, keyed by URI, so a keystroke in
  // one file never resets or cancels another's pending check.
  const timers = new Map();

  function runCheck(document) {
    if (document.languageId !== LANGUAGE_ID) return;
    let results;
    try {
      results = check(document.getText());
    } catch (err) {
      // A checker crash must not crash the extension host, but it also
      // must not silently pretend the document is clean.
      console.error('n88basic: diagnostic check failed', err);
      return;
    }
    diagnostics.set(document.uri, results.map(toDiagnostic));
  }

  function scheduleCheck(document) {
    if (document.languageId !== LANGUAGE_ID) return;
    const key = document.uri.toString();
    clearTimeout(timers.get(key));
    timers.set(
      key,
      setTimeout(() => {
        timers.delete(key);
        runCheck(document);
      }, DEBOUNCE_MS)
    );
  }

  // Check whatever n88basic document is already open when the extension
  // activates, rather than waiting for the first edit.
  for (const editor of vscode.window.visibleTextEditors) runCheck(editor.document);

  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument(runCheck),
    vscode.workspace.onDidChangeTextDocument((event) => scheduleCheck(event.document)),
    vscode.workspace.onDidSaveTextDocument(runCheck),
    vscode.workspace.onDidCloseTextDocument((document) => {
      const key = document.uri.toString();
      clearTimeout(timers.get(key));
      timers.delete(key);
      diagnostics.delete(document.uri);
    })
  );
}

module.exports = { registerDiagnostics };
