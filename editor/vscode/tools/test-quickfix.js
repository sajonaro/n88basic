#!/usr/bin/env node
'use strict';

// Exercises the pure quick-fix logic under src/quickfix.js as plain
// functions, without VSCode -- see that file for the design rationale.
// Run: node editor/vscode/tools/test-quickfix.js
// Exits non-zero on any failure.

const path = require('path');

const quickfix = require(path.join(__dirname, '..', 'src', 'quickfix'));
const { n88basicCheck } = require(path.join(__dirname, '..', 'media', 'n88basic-check.js'));

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

// Apply a quick-fix action's edits to text the same way applyEditsToText
// (renumber.js) does: right-to-left per physical line, so earlier offsets on
// the same line stay valid. Independent from quickfix.js/renumber.js so the
// test is not just re-running the module's own machinery on itself.
function applyEdits(documentText, edits) {
  const eol = documentText.includes('\r\n') ? '\r\n' : '\n';
  const lines = documentText.split(/\r\n|\r|\n/);
  const byLine = new Map();
  for (const e of edits) {
    if (!byLine.has(e.line)) byLine.set(e.line, []);
    byLine.get(e.line).push(e);
  }
  for (const [line, lineEdits] of byLine) {
    lineEdits.sort((a, b) => b.startCol - a.startCol);
    let text = lines[line];
    for (const e of lineEdits) text = text.slice(0, e.startCol) + e.newText + text.slice(e.endCol);
    lines[line] = text;
  }
  return lines.join(eol);
}

function firstDiagnostic(source, code) {
  const diags = n88basicCheck(source);
  return diags.find((d) => d.code === code);
}

// ---- undefined-line: GOTO to a missing line offers the right candidates ----
{
  // 10 has a line before the missing target (30) and one after it (1000),
  // so both directions get an action.
  const src = ['10 PRINT 1', '20 GOTO 999', '30 PRINT 2', '1000 PRINT 3', ''].join('\n');
  const diag = firstDiagnostic(src, 'undefined-line');
  check(!!diag, 'fixture: GOTO 999 produces an undefined-line diagnostic');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 2, `two candidates offered, one before and one after (got ${actions.length})`);
    const titles = actions.map((a) => a.title);
    check(
      titles.some((t) => t.includes('999') && t.includes('30') && t.includes('before')),
      `an action offers the nearest line before (30) (got ${JSON.stringify(titles)})`
    );
    check(
      titles.some((t) => t.includes('999') && t.includes('1000') && t.includes('after')),
      `an action offers the nearest line after (1000) (got ${JSON.stringify(titles)})`
    );
    // Applying either action produces a program the checker reports clean.
    for (const action of actions) {
      const after = applyEdits(src, action.edits);
      const remaining = n88basicCheck(after).filter((d) => d.code === 'undefined-line');
      check(remaining.length === 0, `applying "${action.title}" leaves no undefined-line diagnostic`);
    }
  }
}

// ---- the literal example from the task brief: "10 GOTO 999" ---------------
{
  const src = ['10 GOTO 999', '20 PRINT 1', '30 PRINT 2', '1010 PRINT 3', ''].join('\n');
  const diag = firstDiagnostic(src, 'undefined-line');
  check(!!diag, 'fixture: "10 GOTO 999" produces an undefined-line diagnostic');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    console.log('\n-- actions for "10 GOTO 999" --');
    for (const action of actions) {
      console.log(`  "${action.title}"`);
      for (const e of action.edits) {
        console.log(`    replace line ${e.line} cols ${e.startCol}-${e.endCol} with "${e.newText}"`);
      }
    }
    check(actions.length === 2, `both a before- and after-candidate are offered (got ${actions.length})`);
  }
}

// ---- undefined-line with only one direction available ----------------------
// The line with the GOTO does not count as a candidate for itself -- "point
// this GOTO at itself" is a mechanically honest but useless answer (a silent
// infinite loop), so with nothing else in the document, this yields zero
// candidates (see nearestLineCandidates' excludeLineIndex).
{
  const src = ['10 GOTO 999', ''].join('\n');
  const diag = firstDiagnostic(src, 'undefined-line');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 0, `a lone GOTO with no other line in the document offers no self-loop candidate (got ${actions.length})`);
  }
}
// With one other line before the target and none after, exactly one
// candidate is offered, and it is not the GOTO's own line.
{
  const src = ['5 PRINT 1', '10 GOTO 999', ''].join('\n');
  const diag = firstDiagnostic(src, 'undefined-line');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 1, `one other existing line, so exactly one candidate is offered (got ${actions.length})`);
    check(actions[0] && actions[0].title.includes(' 5 ') && actions[0].title.includes('before'), `the one candidate is line 5, not the GOTO's own line 10 (got "${actions[0] && actions[0].title}")`);
  }
}

// ---- no action is offered where none is safe: duplicate-line --------------
{
  const src = ['10 PRINT 1', '10 PRINT 2', '20 GOTO 10', ''].join('\n');
  const diag = firstDiagnostic(src, 'duplicate-line');
  check(!!diag, 'fixture: duplicate line number produces a duplicate-line diagnostic');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 0, `duplicate-line gets no quick fix, deliberately (got ${actions.length} action(s))`);
  }
}

// ---- no action is offered where none is safe: syntax-error ----------------
{
  const src = '10 PRINT (\n';
  const diag = firstDiagnostic(src, 'syntax-error');
  check(!!diag, 'fixture: bad syntax produces a syntax-error diagnostic');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 0, `syntax-error gets no quick fix (got ${actions.length} action(s))`);
  }
}

// ---- line-order: offers a renumber action when the plan would succeed -----
{
  const src = ['20 PRINT 1', '10 PRINT 2', ''].join('\n');
  const diag = firstDiagnostic(src, 'line-order');
  check(!!diag, 'fixture: out-of-order lines produce a line-order diagnostic');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 1, `line-order offers exactly one renumber action (got ${actions.length})`);
    if (actions[0]) {
      const after = applyEdits(src, actions[0].edits);
      const remaining = n88basicCheck(after).filter((d) => d.code === 'line-order');
      check(remaining.length === 0, 'applying the renumber action leaves no line-order diagnostic');
      check(n88basicCheck(after).length === 0, `applying the renumber action leaves the checker fully clean (got ${JSON.stringify(n88basicCheck(after))})`);
    }
  }
}

// ---- line-order: withheld when renumbering would refuse -------------------
// Out of order AND a jump to a line that doesn't exist yet: computeRenumberPlan
// refuses on a pre-existing dangling jump (renumber.js), so no action must be
// offered -- an action that fails on invocation is worse than none.
{
  const src = ['20 GOTO 999', '10 PRINT 2', ''].join('\n');
  const diag = firstDiagnostic(src, 'line-order');
  check(!!diag, 'fixture: out-of-order lines with a dangling jump still produce a line-order diagnostic');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 0, `line-order action withheld when the renumber plan would refuse (got ${actions.length})`);
  }
}
// Also withheld with a duplicate line number present.
{
  const src = ['20 PRINT 1', '10 PRINT 2', '10 PRINT 3', ''].join('\n');
  const diag = firstDiagnostic(src, 'line-order');
  if (diag) {
    const actions = quickfix.computeActionsForDiagnostic(diag, src);
    check(actions.length === 0, `line-order action withheld when a duplicate line number is present (got ${actions.length})`);
  }
}

// ---- unknown/unhandled diagnostic codes get no action ----------------------
{
  const actions = quickfix.computeActionsForDiagnostic({ line: 0, startCol: 0, endCol: 1, code: 'something-else' }, '10 PRINT 1\n');
  check(actions.length === 0, 'an unrecognised diagnostic code gets no action');
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
process.exit(0);
