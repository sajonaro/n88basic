#!/usr/bin/env node
'use strict';

// Exercises the pure hover/completion/run logic under src/ as plain
// functions, without VSCode.
// Run: node editor/vscode/tools/test-features.js
// Exits non-zero on any failure.

const path = require('path');

const specData = require(path.join(__dirname, '..', 'src', 'spec-data'));
const hover = require(path.join(__dirname, '..', 'src', 'hover'));
const completion = require(path.join(__dirname, '..', 'src', 'completion'));
const run = require(path.join(__dirname, '..', 'src', 'run'));

let failures = 0;

function fail(message) {
  console.error(`FAIL: ${message}`);
  failures++;
}

function ok(message) {
  console.log(`ok: ${message}`);
}

function check(condition, message) {
  if (condition) ok(message);
  else fail(message);
}

const { keywordsData, clausesData, clausesById, phraseEntries } = specData.loadAll();

check(Array.isArray(keywordsData.keywords) && keywordsData.keywords.length > 0, 'spec-data: loads keywords.json');
check(Array.isArray(clausesData.clauses) && clausesData.clauses.length > 0, 'spec-data: loads clauses.json');
check(clausesById.size === clausesData.clauses.length, 'spec-data: clauseIndex has one entry per clause');

// ---- isGrounded --------------------------------------------------------
check(specData.isGrounded({ evidence: 'manual', source: 'ref-9801 p.1' }), 'isGrounded: true when evidence is manual and source is set');
check(!specData.isGrounded({ evidence: 'manual', source: '' }), 'isGrounded: false when source is empty');
check(!specData.isGrounded({ evidence: null, source: '' }), 'isGrounded: false when evidence is null');
check(!specData.isGrounded(null), 'isGrounded: false for a missing clause');

// ---- hover: grounded keyword (ASC, manual-evidence clause) -------------
{
  const entry = keywordsData.keywords.find((k) => k.name === 'ASC');
  check(!!entry, 'fixture: ASC exists in keywords.json');
  const clause = clausesById.get(entry.clauses[0]);
  check(specData.isGrounded(clause), 'fixture: ASC.STR.ASC clause is grounded');
  const md = hover.renderHoverMarkdown(entry, clausesById);
  check(md.includes('### ASC'), 'hover/grounded: shows the keyword name');
  check(md.includes(entry.syntax), 'hover/grounded: shows the recorded syntax');
  check(md.includes(entry.summary), 'hover/grounded: shows the summary');
  check(md.includes(clause.text), 'hover/grounded: shows the clause text');
  check(md.includes(clause.source), 'hover/grounded: shows the source citation');
  check(!md.includes('Out of scope') && !md.includes('Deferred'), 'hover/grounded: no scope banner for an in-scope keyword');
}

// ---- hover: in-scope but ungrounded keyword -------------------------------
// The fixture is synthetic on purpose. This block used to reach into the live
// spec for a keyword that happened to be ungrounded, and went red the day
// every clause acquired a citation -- a test failing because the project got
// better is a test measuring the wrong thing. What is under test is how hover
// renders an ungrounded entry, which must stay checkable even once nothing in
// the real spec is ungrounded any more.
{
  const entry = {
    name: 'EXAMPLE',
    kind: 'statement',
    syntax: null,
    summary: 'a keyword whose page has not been read yet',
    scope: 'in',
    clauses: ['EXAMPLE.STUB'],
  };
  const clause = { id: 'EXAMPLE.STUB', text: 'The syntax and behaviour of EXAMPLE.', evidence: null, source: '', status: 'absent' };
  const clausesById = new Map([[clause.id, clause]]);
  check(entry.syntax === null, 'fixture: the entry has no recorded syntax');
  check(!specData.isGrounded(clause), 'fixture: the clause is not grounded');
  const md = hover.renderHoverMarkdown(entry, clausesById);
  check(md.includes('syntax not yet recorded'), 'hover/ungrounded: says syntax is not yet recorded rather than inventing one');
  check(md.includes(entry.summary), 'hover/ungrounded: still shows the summary');
  check(!md.includes(clause.text), 'hover/ungrounded: does not quote an ungrounded clause');
  check(!md.includes('Source:'), 'hover/ungrounded: no source citation when nothing is grounded');
}

// ---- hover: out-of-scope keyword (AUTO) ---------------------------------
{
  const entry = keywordsData.keywords.find((k) => k.name === 'AUTO');
  check(!!entry && entry.scope === 'out', 'fixture: AUTO exists and is out of scope');
  const md = hover.renderHoverMarkdown(entry, clausesById);
  check(md.includes('Out of scope'), 'hover/out-of-scope: carries an unmistakable scope banner');
  check(md.includes('will not run it'), 'hover/out-of-scope: says the interpreter will not run it');
}

// ---- hover: position matching ------------------------------------------
{
  const line = '10 GOTO 20';
  const entry = hover.matchKeywordAtPosition(line, 5, phraseEntries); // inside "GOTO"
  check(!!entry && entry.name === 'GOTO', `matchKeywordAtPosition finds GOTO at column 5 (got ${entry && entry.name})`);
  const miss = hover.matchKeywordAtPosition(line, 1, phraseEntries); // inside the line number "10"
  check(miss === null, 'matchKeywordAtPosition: no match over a line number');
}
{
  // Longer phrase beats its own prefix: "LINE INPUT#" contains "LINE".
  const line = '10 LINE INPUT#1, A$';
  const entry = hover.matchKeywordAtPosition(line, 4, phraseEntries); // inside "LINE"
  check(!!entry && entry.name === 'LINE INPUT#', `longest phrase wins over its prefix (got ${entry && entry.name})`);
}

// ---- completion: keyword items ------------------------------------------
{
  const items = completion.buildKeywordCompletionItems(keywordsData);
  check(items.length > 0, 'completion: builds at least one keyword item');
  const goto = items.find((i) => i.label === 'GOTO');
  check(!!goto && goto.insertText === 'GOTO', 'completion: GOTO item inserts "GOTO"');
  check(goto.detail === 'unconditional jump', `completion: GOTO detail is its summary (got "${goto.detail}")`);
  // What matters is that documentation reflects the spec entry, whichever way
  // round it is: the recorded syntax when there is one, and an honest note
  // when there is not. Asserting one specific keyword is ungrounded made this
  // fail the day the spec grounded it.
  const entryForGoto = keywordsData.keywords.find((k) => k.name === 'GOTO');
  check(
    entryForGoto.syntax === null
      ? goto.documentation.includes('syntax not yet recorded')
      : goto.documentation.includes(entryForGoto.syntax),
    'completion: GOTO documentation shows its recorded syntax, or says there is none'
  );

  const inScope = items.filter((i) => i.scope === 'in');
  const outOfScope = items.filter((i) => i.scope === 'out');
  check(inScope.length > 0 && outOfScope.length > 0, 'completion: fixture has both in-scope and out-of-scope items');
  const bestIn = inScope.map((i) => i.sortText).sort()[0];
  const bestOut = outOfScope.map((i) => i.sortText).sort()[0];
  check(bestIn < bestOut, 'completion: an in-scope sortText always sorts before an out-of-scope one');
}

// ---- completion: line numbers --------------------------------------------
{
  const doc = '10 PRINT "A"\n25 GOTO 40\n40 PRINT "B"\n25 PRINT "dup"\n';
  const numbers = completion.extractLineNumbers(doc);
  check(numbers.join(',') === '10,25,40', `extractLineNumbers: ascending, deduplicated (got ${numbers.join(',')})`);
}
{
  check(completion.lineNumberTriggerWord('10 GOTO ') === 'GOTO', 'lineNumberTriggerWord: triggers right after GOTO');
  check(completion.lineNumberTriggerWord('10 GOTO 4') === 'GOTO', 'lineNumberTriggerWord: triggers while typing the number');
  check(completion.lineNumberTriggerWord('10 ON X GOSUB 10,') === 'GOSUB', 'lineNumberTriggerWord: triggers after a comma in a target list');
  check(completion.lineNumberTriggerWord('10 IF X THEN ') === 'THEN', 'lineNumberTriggerWord: triggers after THEN');
  check(completion.lineNumberTriggerWord('10 RESTORE') === 'RESTORE', 'lineNumberTriggerWord: RESTORE alone still counts as "before the number"');
  check(completion.lineNumberTriggerWord('10 ALGOTO 5') === null, 'lineNumberTriggerWord: does not false-trigger inside a longer identifier');
  check(completion.lineNumberTriggerWord('10 PRINT "GOTO"') === null, 'lineNumberTriggerWord: no trigger when GOTO is not the last token before the cursor');
}

// ---- run: pure path/command logic ----------------------------------------
{
  check(run.pngPathFor('/x/demo.bas') === '/x/demo.png', 'pngPathFor: replaces the extension');
  check(run.pngPathFor('/x/demo') === '/x/demo.png', 'pngPathFor: appends .png when there is no extension');
  check(run.pngPathFor('/x/demo.tar.bas') === '/x/demo.tar.png', 'pngPathFor: only the last extension is replaced');
}
{
  const existing = new Set(['/repo/dune-project', '/repo/sub/other-file']);
  const existsSync = (p) => existing.has(p);
  check(run.findRepoRoot('/repo/sub/deep', existsSync) === '/repo', 'findRepoRoot: walks up to the directory containing dune-project');
  check(run.findRepoRoot('/nowhere/at/all', existsSync) === '/nowhere/at/all', 'findRepoRoot: falls back to the start directory rather than throwing');
}
{
  const cmd = run.buildRunCommand("/tmp/it's a file.bas");
  check(cmd.includes('dune exec bin/main.exe --'), 'buildRunCommand: runs the CLI as documented');
  check(cmd.includes('opam env --switch=. --set-switch'), 'buildRunCommand: sets up the opam switch first');
  check(cmd.includes("/tmp/it'\\''s a file.bas"), 'buildRunCommand: single quotes in the path are escaped for the shell');
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
process.exit(0);
