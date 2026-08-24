'use strict';

// The client half of the optional language server. Off by default.
//
// Why off by default: every feature the server could carry already works
// in-process, and this extension had never once been confirmed to load on a
// real machine until the publisher fix landed. Shipping a client/server split
// as the default would put a new failure mode in front of every user of a
// thing we have only just seen work at all. The setting exists so the server
// can be proven on a real editor first; flipping the default is a later
// decision, made on evidence rather than on completion.
//
// When enabled it replaces ONE feature -- diagnostics -- and nothing else.
// Hover, completion, quick fixes, go-to-definition, find-references,
// renumbering and Run all stay in-process. The bar for this work was that it
// must be neutral on what already works, and the surest way to be neutral on a
// feature is not to move it.
//
// `require('vscode-languageclient')` is deferred into start() so this module
// still loads under plain node, the same convention every other src/ module
// follows for `require('vscode')`.

const path = require('path');

const CONFIG_SECTION = 'n88basic';
const CONFIG_KEY = 'languageServer';
const LANGUAGE_ID = 'n88basic';

// Exported so a test can assert the decision without a VSCode instance.
function isEnabled(configuration) {
  return configuration.get(CONFIG_KEY) === true;
}

function serverModulePath() {
  return path.join(__dirname, '..', 'server', 'server.js');
}

// Built as a plain object rather than inline so tests can check the shape --
// in particular that the server is launched with the extension's own node
// (`module` transport), not an assumed global one.
function serverOptions(TransportKind) {
  const module = serverModulePath();
  return {
    run: { module, transport: TransportKind.ipc },
    debug: { module, transport: TransportKind.ipc, options: { execArgv: ['--nolazy', '--inspect=6009'] } },
  };
}

// No `scheme` restriction, and that omission is the whole point. A selector of
// { scheme: 'file', language: 'n88basic' } looks obviously right and is wrong
// here: this project is edited over a WSL remote, where documents arrive as
// `vscode-remote://wsl+.../...`, not `file://`. Pinning the scheme meant the
// client never forwarded a single document, so the server sat idle publishing
// nothing -- while the in-process checker had already stood down because a
// client existed. Diagnostics vanished entirely.
//
// Matching on language alone is also simply more correct: this extension's
// checker takes source text and needs no file access, so it has no reason to
// care where the bytes came from -- untitled buffers and any future scheme
// included.
function clientOptions() {
  return { documentSelector: [{ language: LANGUAGE_ID }] };
}

function registerLanguageClient(context) {
  const vscode = require('vscode');
  if (!isEnabled(vscode.workspace.getConfiguration(CONFIG_SECTION))) return null;

  const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
  const client = new LanguageClient(
    'n88basicLanguageServer',
    'N88-BASIC Language Server',
    serverOptions(TransportKind),
    clientOptions()
  );
  client.start();
  context.subscriptions.push({ dispose: () => client.stop() });
  return client;
}

module.exports = {
  registerLanguageClient,
  isEnabled,
  serverOptions,
  clientOptions,
  serverModulePath,
  CONFIG_SECTION,
  CONFIG_KEY,
};
