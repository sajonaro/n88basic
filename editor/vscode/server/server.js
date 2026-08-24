'use strict';

// The n88basic language server (Path A: a Node server over the existing
// js_of_ocaml bundle). See docs/afk-runs/RESUME-HERE.md for why this is Node
// and not a native OCaml binary -- briefly, package.json declares
// extensionKind ["ui","workspace"] so the extension host is Windows, and a
// server built under WSL2 would be a Linux ELF that host cannot spawn.
//
// The important property is that this process does NOT know the language. It
// calls the same `n88basicCheck` bundle the in-process path has always used,
// which dune generates from the interpreter's own parser. So the server cannot
// drift from the language: there is exactly one parser in this project, and it
// is basic/'s. This makes the LSP a transport change rather than a
// reimplementation, which is the whole reason it is safe to add at all.
//
// Scope is deliberately diagnostics only. Every other editor feature -- hover,
// completion, quick fixes, go-to-definition, find-references, renumbering, Run
// -- stays in-process and untouched. The bar set for this work was that it must
// be neutral on what already works before it is anything else, and the surest
// way to be neutral on a feature is not to move it.

const {
  createConnection,
  TextDocuments,
  DiagnosticSeverity,
  ProposedFeatures,
  TextDocumentSyncKind,
} = require('vscode-languageserver/node');
const { TextDocument } = require('vscode-languageserver-textdocument');
const path = require('path');

// The bundle exports `n88basicCheck` on module.exports -- NOT on globalThis.
// js_of_ocaml's Js.export checks `typeof module === "object"` first, so under
// node it writes to the module. Getting this wrong yields `undefined is not a
// function` at the first keystroke (docs/afk-runs/EDITOR-HANDOVER.md §2).
function loadChecker() {
  const bundle = require(path.join(__dirname, '..', 'media', 'n88basic-check.js'));
  if (typeof bundle.n88basicCheck !== 'function')
    throw new Error('n88basic-check.js did not export n88basicCheck');
  return bundle.n88basicCheck;
}

const SEVERITY = {
  error: DiagnosticSeverity.Error,
  warning: DiagnosticSeverity.Warning,
};

// The bundle's diagnostic shape is { line, startCol, endCol, severity, message,
// code } with a 0-based line -- the same shape src/diagnostics.js consumes, so
// both paths agree by construction rather than by two conversions kept in step.
function toLspDiagnostic(d) {
  const diagnostic = {
    range: {
      start: { line: d.line, character: d.startCol },
      end: { line: d.line, character: d.endCol },
    },
    message: d.message,
    severity: SEVERITY[d.severity] !== undefined ? SEVERITY[d.severity] : DiagnosticSeverity.Error,
    source: 'n88basic',
  };
  if (d.code) diagnostic.code = d.code;
  return diagnostic;
}

function createServer(connection) {
  const check = loadChecker();
  const documents = new TextDocuments(TextDocument);

  connection.onInitialize(() => ({
    capabilities: {
      // Full sync, not incremental: a BASIC program is one file of a few
      // hundred lines and the parser takes whole source anyway, so
      // reassembling deltas would buy nothing and could only introduce a way
      // for the server's copy to differ from the editor's.
      textDocumentSync: TextDocumentSyncKind.Full,
    },
  }));

  const validate = (document) => {
    let diagnostics;
    try {
      diagnostics = check(document.getText()).map(toLspDiagnostic);
    } catch (e) {
      // A checker that throws must not take the server with it: the editor
      // would lose diagnostics for every later keystroke, silently. Report
      // nothing for this revision and keep serving.
      connection.console.error(`n88basic check failed: ${e && e.message}`);
      return;
    }
    connection.sendDiagnostics({ uri: document.uri, diagnostics });
  };

  documents.onDidChangeContent((change) => validate(change.document));
  documents.onDidClose((event) =>
    connection.sendDiagnostics({ uri: event.document.uri, diagnostics: [] })
  );

  documents.listen(connection);
  return connection;
}

// Only wire up stdio when run as a process; requiring this file (as the tests
// do) must not open a connection on stdin.
if (require.main === module) {
  createServer(createConnection(ProposedFeatures.all)).listen();
}

module.exports = { createServer, toLspDiagnostic, loadChecker };
