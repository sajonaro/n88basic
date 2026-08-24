#!/usr/bin/env node
'use strict';

// Exercises the pure renumbering/auto-numbering logic under src/ as plain
// functions, without VSCode, including a round-trip of every renumbered
// result through the real parser bundle (media/n88basic-check.js).
// Run: node editor/vscode/tools/test-renumber.js
// Exits non-zero on any failure.

const path = require('path');

const renumber = require(path.join(__dirname, '..', 'src', 'renumber'));
const scan = require(path.join(__dirname, '..', 'src', 'renumber-scan'));
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

function undefinedLineCount(text) {
  return n88basicCheck(text).filter((d) => d.code === 'undefined-line').length;
}

// ---- a simple program, every jump kind at once -----------------------------
{
  const src = [
    '10 PRINT "HELLO"',
    '20 ON X GOTO 30,40,50',
    '30 IF X THEN 40 ELSE 50',
    '40 GOSUB 50',
    '50 RESTORE 10',
    '60 REM GOTO 999 is not a jump',
    '70 PRINT "GOTO 999 is not a jump either"',
    '80 GOTO 10',
    '',
  ].join('\n');

  check(undefinedLineCount(src) === 0, 'fixture: the "all jump kinds" program is clean before renumbering');

  const plan = renumber.computeRenumberPlan(src, { start: 100, increment: 5 });
  check(plan.ok, `renumber all-jump-kinds program: succeeds (${plan.ok ? '' : plan.reason})`);
  if (plan.ok) {
    const lines = plan.text.split('\n');
    check(lines[0] === '100 PRINT "HELLO"', `own line number renumbered (got "${lines[0]}")`);
    check(lines[1] === '105 ON X GOTO 110,115,120', `ON...GOTO list rewritten (got "${lines[1]}")`);
    check(lines[2] === '110 IF X THEN 115 ELSE 120', `THEN/ELSE targets rewritten (got "${lines[2]}")`);
    check(lines[3] === '115 GOSUB 120', `GOSUB target rewritten (got "${lines[3]}")`);
    check(lines[4] === '120 RESTORE 100', `RESTORE target rewritten (got "${lines[4]}")`);
    check(lines[5] === '125 REM GOTO 999 is not a jump', `text inside REM is untouched (got "${lines[5]}")`);
    check(
      lines[6] === '130 PRINT "GOTO 999 is not a jump either"',
      `text inside a string literal is untouched (got "${lines[6]}")`
    );
    check(lines[7] === '135 GOTO 100', `final GOTO rewritten (got "${lines[7]}")`);

    // The self-check the task requires: no NEW undefined-line diagnostic.
    check(undefinedLineCount(plan.text) === 0, 'round-trip: renumbered program has no undefined-line diagnostics');
  }
}

// ---- ON X GOTO 10,20,30 specifically ---------------------------------------
{
  const src = '10 ON X GOTO 10,20,30\n20 PRINT "A"\n30 PRINT "B"\n';
  const plan = renumber.computeRenumberPlan(src, { start: 1, increment: 1 });
  check(plan.ok, `ON...GOTO fixture renumbers (${plan.ok ? '' : plan.reason})`);
  if (plan.ok) {
    check(plan.text.split('\n')[0] === '1 ON X GOTO 1,2,3', `ON...GOTO list fully rewritten (got "${plan.text.split('\n')[0]}")`);
    check(undefinedLineCount(plan.text) === 0, 'ON...GOTO round-trip: no undefined-line diagnostics');
  }
}

// ---- THEN/ELSE pair ----------------------------------------------------------
{
  const src = '100 IF X THEN 200 ELSE 300\n200 PRINT "yes"\n300 PRINT "no"\n';
  const plan = renumber.computeRenumberPlan(src, { start: 10, increment: 10 });
  check(plan.ok, `THEN/ELSE fixture renumbers (${plan.ok ? '' : plan.reason})`);
  if (plan.ok) {
    check(plan.text.split('\n')[0] === '10 IF X THEN 20 ELSE 30', `THEN/ELSE pair rewritten (got "${plan.text.split('\n')[0]}")`);
    check(undefinedLineCount(plan.text) === 0, 'THEN/ELSE round-trip: no undefined-line diagnostics');
  }
}

// ---- refusal: duplicate line numbers ---------------------------------------
{
  const src = '10 PRINT 1\n10 PRINT 2\n20 GOTO 10\n';
  const plan = renumber.computeRenumberPlan(src, { start: 10, increment: 10 });
  check(!plan.ok, 'refuses a program with a duplicate line number');
  check(plan.ok || /duplicate/i.test(plan.reason), `refusal reason mentions the duplicate (got "${plan.reason}")`);
}

// ---- refusal: syntax error --------------------------------------------------
{
  const src = '10 PRINT (\n20 GOTO 10\n';
  const plan = renumber.computeRenumberPlan(src, { start: 10, increment: 10 });
  check(!plan.ok, 'refuses a program with a syntax error');
  check(plan.ok || /syntax/i.test(plan.reason), `refusal reason mentions the syntax error (got "${plan.reason}")`);
}

// ---- refusal: jump to a line that does not exist, before renumbering -------
{
  const src = '10 GOTO 999\n20 PRINT "x"\n';
  const plan = renumber.computeRenumberPlan(src, { start: 10, increment: 10 });
  check(!plan.ok, 'refuses a program with a pre-existing dangling jump');
  check(plan.ok || /does not exist/i.test(plan.reason), `refusal reason mentions the missing target (got "${plan.reason}")`);
}

// ---- refusal: no numbered lines at all --------------------------------------
{
  const plan = renumber.computeRenumberPlan('\n', { start: 10, increment: 10 });
  check(!plan.ok, 'refuses a program with no numbered lines');
}

// ---- refusal: bad options ----------------------------------------------------
{
  const src = '10 PRINT 1\n';
  check(!renumber.computeRenumberPlan(src, { start: -1, increment: 10 }).ok, 'refuses a negative starting number');
  check(!renumber.computeRenumberPlan(src, { start: 10, increment: 0 }).ok, 'refuses a zero increment');
  check(!renumber.computeRenumberPlan(src, { start: 1.5, increment: 10 }).ok, 'refuses a non-integer starting number');
}

// ---- increment inference -----------------------------------------------------
{
  check(renumber.inferIncrement('10 PRINT 1\n20 PRINT 2\n30 PRINT 3\n') === 10, 'inferIncrement: reads the file\'s own step of 10');
  check(renumber.inferIncrement('5 PRINT 1\n10 PRINT 2\n15 PRINT 3\n') === 5, 'inferIncrement: reads a step of 5');
  check(renumber.inferIncrement('10 PRINT 1\n') === 10, 'inferIncrement: falls back to 10 with only one line');
  check(renumber.inferIncrement('') === 10, 'inferIncrement: falls back to 10 with no lines at all');
  // Mixed gaps: the most common gap wins, ties broken toward the smaller gap.
  check(
    renumber.inferIncrement('10 PRINT\n20 PRINT\n30 PRINT\n35 PRINT\n') === 10,
    'inferIncrement: picks the more common gap over an outlier'
  );
}

// ---- computeNextLineInsertion ------------------------------------------------
{
  const doc = '10 PRINT "A"\n20 PRINT "B"\n30 PRINT "C"\n';
  check(renumber.computeNextLineInsertion(doc, 2) === 40, `insertNextLine after the last line continues the sequence (got ${renumber.computeNextLineInsertion(doc, 2)})`);
  check(renumber.computeNextLineInsertion('', 0) === 10, 'insertNextLine on an empty document falls back to 10');
  // Inserting after line 10 but before line 20 (gap of 10, increment 10):
  // 10 + 10 = 20 collides, so it should split the gap instead of colliding.
  const mid = renumber.computeNextLineInsertion(doc, 0);
  check(mid > 10 && mid < 20, `insertNextLine between two lines splits the gap rather than colliding (got ${mid})`);
  // No room at all between adjacent BASIC numbers.
  const tight = '10 PRINT "A"\n11 PRINT "B"\n';
  check(renumber.computeNextLineInsertion(tight, 0) === null, 'insertNextLine returns null when there is no integer room left');
}

// ---- scan primitives: strings and comments are never touched ---------------
{
  const refs = scan.findReferencesInLine('10 PRINT "GOTO 5, GOSUB 6": REM GOTO 7');
  check(refs.length === 0, `findReferencesInLine: ignores GOTO/GOSUB text inside a string and a REM comment (got ${refs.length})`);
}
{
  const refs = scan.findReferencesInLine("10 GOTO 20 ' trailing comment GOTO 30");
  check(refs.length === 1 && refs[0].number === 20, `findReferencesInLine: stops scanning at an apostrophe comment (got ${JSON.stringify(refs)})`);
}
{
  check(scan.parseDefinition('  10 PRINT 1').number === 10, 'parseDefinition: reads a line number past leading whitespace');
  check(scan.parseDefinition('REM no number here') === null, 'parseDefinition: null when a physical line has no leading number');
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
process.exit(0);
