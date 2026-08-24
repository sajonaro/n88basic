'use strict';

// Completion: keyword completion from keywords.json (same data as hover.js,
// so they can't say different things about the same keyword), plus line
// number completion for GOTO/GOSUB/THEN/ELSE/RESTORE targets -- the
// completion a BASIC programmer wants most, and it needs no spec data at
// all, just the document's own line numbers.
//
// The item-building and text-matching functions are pure (no
// `require('vscode')` at module scope); registerCompletionProvider is the
// only part that touches vscode, and it require()s it lazily.

const { stripQualifier, wordsOf } = require('./keyword-model');
const { WORDLIKE_KINDS } = require('./spec-data');

const SCOPE_RANK = { in: 0, deferred: 1, out: 2 };
const SCOPE_NOTE = {
  deferred: 'Deferred: recognised by the spec, not yet implemented.',
  out: 'Out of scope: real N88-BASIC(86), but this interpreter will not run it.',
};

// One completion candidate per keyword entry. Ellipsis names ("ON…GOTO")
// insert just their first word ("ON") -- the rest of the statement is not
// literal text a completion can insert. In-scope keywords get the lowest
// sortText prefix so they rank first: "a user typing should reach a
// keyword that works first" (task requirement).
function buildKeywordCompletionItems(keywordsData) {
  const items = [];
  for (const entry of keywordsData.keywords) {
    if (!WORDLIKE_KINDS.has(entry.kind)) continue;
    const display = stripQualifier(entry.name);
    const { words } = wordsOf(display);
    if (words.length === 0) continue;
    const insertText = words[0];
    let documentation = entry.syntax || 'syntax not yet recorded';
    const note = SCOPE_NOTE[entry.scope];
    if (note) documentation += `\n\n${note}`;
    items.push({
      label: entry.name,
      insertText,
      kind: entry.kind,
      scope: entry.scope,
      detail: entry.summary || '(no summary recorded)',
      documentation,
      sortText: `${SCOPE_RANK[entry.scope]}${entry.name}`,
    });
  }
  return items;
}

// Every line number actually defined in the document, ascending, so a
// GOTO/GOSUB/THEN/ELSE/RESTORE target completion only ever offers targets
// that exist.
function extractLineNumbers(documentText) {
  const numbers = new Set();
  for (const line of documentText.split(/\r\n|\r|\n/)) {
    const m = /^\s*(\d+)\b/.exec(line);
    if (m) numbers.add(Number(m[1]));
  }
  return [...numbers].sort((a, b) => a - b);
}

const LINE_TARGET_KEYWORDS = ['GOTO', 'GOSUB', 'THEN', 'ELSE', 'RESTORE'];

// Matches when the text immediately before the cursor puts it in a
// line-number argument position: right after one of the target keywords,
// or continuing a comma-separated list after one (ON x GOTO 10,20,|).
// Requires a non-identifier character (or start of string) before the
// keyword so "ALGOTO" doesn't false-trigger on "GOTO".
const TRIGGER_RE = new RegExp(
  `(?:^|[^A-Za-z0-9])(${LINE_TARGET_KEYWORDS.join('|')})\\s*(?:[0-9]+\\s*,\\s*)*[0-9]*$`,
  'i'
);

function lineNumberTriggerWord(linePrefix) {
  const m = TRIGGER_RE.exec(linePrefix);
  return m ? m[1].toUpperCase() : null;
}

function registerCompletionProvider(context, specData) {
  const vscode = require('vscode');
  const keywordItems = buildKeywordCompletionItems(specData.keywordsData);
  const KIND_MAP = {
    statement: vscode.CompletionItemKind.Keyword,
    function: vscode.CompletionItemKind.Function,
    'function-statement': vscode.CompletionItemKind.Function,
    clause: vscode.CompletionItemKind.Keyword,
    option: vscode.CompletionItemKind.Property,
    device: vscode.CompletionItemKind.Value,
  };

  const provider = {
    provideCompletionItems(document, position) {
      const linePrefix = document.lineAt(position.line).text.slice(0, position.character);
      const trigger = lineNumberTriggerWord(linePrefix);
      if (trigger) {
        return extractLineNumbers(document.getText()).map((n) => {
          const item = new vscode.CompletionItem(String(n), vscode.CompletionItemKind.Reference);
          item.detail = `line ${n} (target of ${trigger})`;
          return item;
        });
      }
      return keywordItems.map((k) => {
        const item = new vscode.CompletionItem(k.label, KIND_MAP[k.kind] || vscode.CompletionItemKind.Keyword);
        item.insertText = k.insertText;
        item.detail = k.detail;
        item.documentation = new vscode.MarkdownString(k.documentation);
        item.sortText = k.sortText;
        return item;
      });
    },
  };

  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider('n88basic', provider, ' ', ',')
  );
}

module.exports = {
  buildKeywordCompletionItems,
  extractLineNumbers,
  lineNumberTriggerWord,
  registerCompletionProvider,
};
