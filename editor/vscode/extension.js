'use strict';

// Plain CommonJS, no dependencies. Wires up the extension's features, each
// implemented in its own module under src/ -- see that directory and
// docs/superpowers/specs/2026-08-16-n88basic-design.md §8. This file is the
// only one that requires('vscode') at load time; every module under src/
// defers that require into its register*() function so the rest of it can
// be unit-tested with plain node (see tools/test-features.js).

const { registerDiagnostics } = require('./src/diagnostics');
const { registerLanguageClient } = require('./src/language-client');
const { registerHoverProvider } = require('./src/hover');
const { registerCompletionProvider } = require('./src/completion');
const { registerRunCommand } = require('./src/run');
const { registerSessionCommands } = require('./src/session');
const { registerRenumberCommand, registerInsertNextLineCommand } = require('./src/renumber-commands');
const { registerCodeActionProvider } = require('./src/quickfix');
const { registerNavigation } = require('./src/navigation');
const { loadAll } = require('./src/spec-data');

function activate(context) {
  // The language server, when enabled, provides diagnostics -- so the
  // in-process checker must not also publish them, or every problem appears
  // twice. Disabled (the default) the client returns null and this is exactly
  // the code that has always run.
  const languageClient = registerLanguageClient(context);
  if (!languageClient) registerDiagnostics(context);

  const specData = loadAll();
  registerHoverProvider(context, specData);
  registerCompletionProvider(context, specData);

  registerRunCommand(context);
  // Execute buffer / selection / immediate statement -- three commands rather
  // than one, because "run the current line" is not a meaningful request in a
  // numbered BASIC program (src/session.js says why).
  registerSessionCommands(context);
  registerRenumberCommand(context);
  registerInsertNextLineCommand(context);
  registerCodeActionProvider(context);
  registerNavigation(context);
}

function deactivate() {}

module.exports = { activate, deactivate };
