'use strict';

// Hover: given the line text and the cursor's character offset, find which
// keyword it names and render the same text the specification carries --
// design §8's "editor help and the specification are the same text and
// cannot drift". The matching and rendering here are pure functions (no
// `require('vscode')` at module scope) so tools/test-features.js can call
// them directly; registerHoverProvider is the only part that touches
// vscode, and it require()s it lazily so this file still loads standalone.

const { resolveBestEntry, isGrounded } = require('./spec-data');
const { phraseMatch } = require('./keyword-model');

// Longer, more literal phrases outrank shorter ones ("LINE INPUT#" beats
// "LINE INPUT" beats "LINE"), same tie-break as check-grammar.js's sort.
function specificity(words) {
  const totalLen = words.reduce((n, w) => n + w.length, 0);
  return [-words.length, -totalLen];
}

function compareSpecificity(a, b) {
  return a[0] - b[0] || a[1] - b[1];
}

// Finds the keyword entry whose text spans `character` on `lineText`, or
// null. When several phrase entries tie for the most specific match at that
// position (e.g. "ON" from both ON…GOTO and ON…GOSUB), resolveBestEntry
// picks one.
function matchKeywordAtPosition(lineText, character, phraseEntries) {
  let bestSpec = null;
  let candidates = [];
  for (const p of phraseEntries) {
    const regex = new RegExp(phraseMatch(p.words), 'gi');
    let m = regex.exec(lineText);
    while (m) {
      if (m[0].length === 0) {
        regex.lastIndex++;
      } else {
        const start = m.index;
        const end = start + m[0].length;
        if (character >= start && character <= end) {
          const spec = specificity(p.words);
          const cmp = bestSpec === null ? -1 : compareSpecificity(spec, bestSpec);
          if (cmp < 0) {
            bestSpec = spec;
            candidates = [p.entry];
          } else if (cmp === 0) {
            candidates.push(p.entry);
          }
        }
      }
      m = regex.exec(lineText);
    }
  }
  if (candidates.length === 0) return null;
  return resolveBestEntry(candidates);
}

const SCOPE_BANNER = {
  deferred:
    '**Deferred.** This is real N88-BASIC(86), recognised by the specification, but this interpreter does not implement it yet.',
  out: '**Out of scope.** This is real N88-BASIC(86), but this interpreter will not run it.',
};

// The clause text and source citation, for every clause of `entry` that is
// grounded (see spec-data.js's isGrounded) -- ungrounded clauses are stubs
// ("The syntax and behaviour of X.") not worth quoting.
function groundedClauseSections(entry, clausesById) {
  const sections = [];
  for (const id of entry.clauses || []) {
    const clause = clausesById.get(id);
    if (!isGrounded(clause)) continue;
    sections.push('---', '', clause.text, '', `*Source: ${clause.source}*`);
  }
  return sections;
}

// Renders the markdown a hover popup shows for `entry`. Honest about gaps:
// a null syntax says so rather than inventing one, and an out-of-scope or
// deferred keyword gets an unmistakable banner.
function renderHoverMarkdown(entry, clausesById) {
  const lines = [`### ${entry.name}`, ''];
  lines.push(entry.syntax ? '```\n' + entry.syntax + '\n```' : '*syntax not yet recorded*');
  lines.push('', entry.summary || '*no summary recorded*');
  const banner = SCOPE_BANNER[entry.scope];
  if (banner) lines.push('', banner);
  const clauseLines = groundedClauseSections(entry, clausesById);
  if (clauseLines.length > 0) lines.push('', ...clauseLines);
  return lines.join('\n');
}

function registerHoverProvider(context, specData) {
  const vscode = require('vscode');
  const provider = {
    provideHover(document, position) {
      const lineText = document.lineAt(position.line).text;
      const entry = matchKeywordAtPosition(lineText, position.character, specData.phraseEntries);
      if (!entry) return undefined;
      const markdown = renderHoverMarkdown(entry, specData.clausesById);
      return new vscode.Hover(new vscode.MarkdownString(markdown));
    },
  };
  context.subscriptions.push(vscode.languages.registerHoverProvider('n88basic', provider));
}

module.exports = {
  matchKeywordAtPosition,
  renderHoverMarkdown,
  registerHoverProvider,
};
