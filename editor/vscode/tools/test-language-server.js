'use strict';

// Drives the language server the way VSCode would: spawn it as a child
// process, speak real LSP over the wire, and assert on the diagnostics it
// publishes. No VSCode involved.
//
// This matters more here than a test like it normally would. Nothing in this
// extension has ever been observed running inside a real editor -- the
// extension was not even registrable until the publisher fix -- so "it works
// in the editor" is not a check anyone can currently perform. Driving the
// actual protocol over an actual pipe is the closest thing to evidence
// available from this side of the WSL boundary, and it is a good deal closer
// than requiring the module and calling a function.
//
// It asserts the two things that could plausibly be wrong and would be silent:
// that the server starts and completes an initialize handshake at all, and
// that a diagnostic survives the round trip with its position intact -- LSP
// ranges are 0-based in both axes and the bundle's are 0-based in line only,
// so an off-by-one here would be invisible until someone looked at a squiggle
// in the wrong place.

const { spawn } = require('child_process');
const path = require('path');
const {
  createMessageConnection,
  StreamMessageReader,
  StreamMessageWriter,
} = require('vscode-jsonrpc/node');

const SERVER = path.join(__dirname, '..', 'server', 'server.js');
const TIMEOUT_MS = 15000;

const failures = [];
const check = (ok, message) => {
  if (!ok) failures.push(message);
};

function deferred() {
  let resolve;
  const promise = new Promise((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

async function main() {
  const child = spawn(process.execPath, [SERVER, '--stdio'], { stdio: ['pipe', 'pipe', 'pipe'] });
  const stderr = [];
  child.stderr.on('data', (b) => stderr.push(b.toString()));

  const connection = createMessageConnection(
    new StreamMessageReader(child.stdout),
    new StreamMessageWriter(child.stdin)
  );

  const published = deferred();
  connection.onNotification('textDocument/publishDiagnostics', (params) => published.resolve(params));
  connection.listen();

  const initialize = await connection.sendRequest('initialize', {
    processId: process.pid,
    rootUri: null,
    capabilities: {},
  });
  check(
    initialize && initialize.capabilities && initialize.capabilities.textDocumentSync !== undefined,
    'initialize did not answer with a textDocumentSync capability'
  );
  await connection.sendNotification('initialized', {});

  await connection.sendNotification('textDocument/didOpen', {
    textDocument: {
      uri: 'file:///test.bas',
      languageId: 'n88basic',
      version: 1,
      // A GOTO to a line that does not exist: the checker's own example, and
      // an error the parser can only find by knowing the language.
      text: '10 PRINT "HI"\n20 GOTO 999\n',
    },
  });

  const timeout = setTimeout(() => published.resolve(null), TIMEOUT_MS);
  const params = await published.promise;
  clearTimeout(timeout);

  if (params === null) {
    failures.push(`no diagnostics published within ${TIMEOUT_MS}ms; stderr: ${stderr.join('')}`);
  } else {
    check(params.uri === 'file:///test.bas', `diagnostics published for the wrong uri: ${params.uri}`);
    check(params.diagnostics.length === 1, `expected exactly one diagnostic, got ${params.diagnostics.length}`);
    const d = params.diagnostics[0] || {};
    check(
      d.message === 'Line 999 does not exist',
      `unexpected message: ${JSON.stringify(d.message)}`
    );
    // Line 1 (0-based) is "20 GOTO 999"; the target starts at column 8.
    check(d.range && d.range.start.line === 1, `expected line 1, got ${d.range && d.range.start.line}`);
    check(
      d.range && d.range.start.character === 8 && d.range.end.character === 11,
      `expected characters 8..11, got ${d.range && d.range.start.character}..${d.range && d.range.end.character}`
    );
    check(d.severity === 1, `expected severity Error (1), got ${d.severity}`);
    check(d.source === 'n88basic', `expected source n88basic, got ${d.source}`);
  }

  connection.dispose();
  child.kill();

  // The non-regression guarantee, checked rather than asserted in prose: the
  // server is opt-in, so an editor that has never heard of this setting keeps
  // exactly the in-process behaviour it had before the server existed.
  const manifest = require(path.join(__dirname, '..', 'package.json'));
  const setting = manifest.contributes?.configuration?.properties?.['n88basic.languageServer'];
  check(setting !== undefined, 'package.json does not contribute n88basic.languageServer');
  check(setting && setting.default === false, 'n88basic.languageServer must default to false');

  const client = require(path.join(__dirname, '..', 'src', 'language-client.js'));

  // The document selector must NOT pin a URI scheme. This project is edited
  // over a WSL remote, where documents are `vscode-remote://...`; a selector of
  // { scheme: 'file' } matches nothing there, so the client forwards no
  // documents, the server publishes nothing, and the in-process checker has
  // already stood down -- diagnostics disappear completely. That shipped once,
  // and this test did not catch it because it drives the server directly with
  // a file:// URI and never exercises the client's selector at all.
  for (const selector of client.clientOptions().documentSelector) {
    check(
      selector.scheme === undefined,
      `documentSelector pins scheme "${selector.scheme}", which excludes remote workspaces`
    );
    check(selector.language === 'n88basic', 'documentSelector must select the n88basic language');
  }

  check(client.isEnabled({ get: () => undefined }) === false, 'an unset configuration must read as disabled');
  check(client.isEnabled({ get: () => false }) === false, 'false must read as disabled');
  check(client.isEnabled({ get: () => true }) === true, 'true must read as enabled');

  if (failures.length > 0) {
    console.error('language server FAILED:');
    for (const f of failures) console.error('  - ' + f);
    process.exit(1);
  }
  console.log('language server OK (initialize handshake, diagnostics round trip with positions intact)');
}

main().catch((e) => {
  console.error('language server FAILED: ' + (e && e.stack));
  process.exit(1);
});
