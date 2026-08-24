#!/usr/bin/env node
'use strict';

// Exercises the compiled checker bundle as a pure function, without VSCode.
// Run: node editor/vscode/tools/test-diagnostics.js
// Exits non-zero on any failure.

const path = require('path');

const BUNDLE_PATH = path.join(__dirname, '..', 'media', 'n88basic-check.js');

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

let n88basicCheck;
try {
  ({ n88basicCheck } = require(BUNDLE_PATH));
} catch (err) {
  fail(`cannot load ${BUNDLE_PATH}: ${err.message}`);
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}

check(typeof n88basicCheck === 'function', 'bundle exports n88basicCheck as a function');

// A clean program yields no diagnostics.
{
  const diags = n88basicCheck('10 PRINT "HELLO"\n20 GOTO 10\n');
  check(Array.isArray(diags), 'clean program: result is an array');
  check(diags.length === 0, `clean program: no diagnostics (got ${diags.length})`);
}

// A GOTO to a missing line yields exactly one diagnostic, bracketing the
// line number precisely.
{
  const source = '10 GOTO 999\n20 PRINT 1\n';
  const diags = n88basicCheck(source);
  check(diags.length === 1, `GOTO to missing line: exactly one diagnostic (got ${diags.length})`);
  const d = diags[0];
  if (d) {
    check(d.line === 0, `GOTO to missing line: reports 0-based line 0 (got ${d.line})`);
    check(d.startCol === 8 && d.endCol === 11, `GOTO to missing line: columns bracket "999" (got ${d.startCol}-${d.endCol})`);
    check(source.slice(d.startCol, d.endCol) === '999', 'GOTO to missing line: columns slice out exactly "999"');
    check(d.severity === 'error', `GOTO to missing line: severity is "error" (got ${d.severity})`);
    check(d.code === 'undefined-line', `GOTO to missing line: code is "undefined-line" (got ${d.code})`);
  }
}

// A syntactically bad line yields a syntax diagnostic.
{
  const diags = n88basicCheck('10 PRINT (\n');
  check(diags.length === 1, `syntax error: exactly one diagnostic (got ${diags.length})`);
  const d = diags[0];
  if (d) {
    check(d.severity === 'error', `syntax error: severity is "error" (got ${d.severity})`);
    check(d.code === 'syntax-error', `syntax error: code is "syntax-error" (got ${d.code})`);
  }
}

// Duplicate line numbers and out-of-order line numbers are both reported.
{
  const diags = n88basicCheck('10 PRINT 1\n10 PRINT 2\n');
  check(
    diags.some((d) => d.code === 'duplicate-line'),
    'duplicate line number is reported'
  );
}
{
  const diags = n88basicCheck('20 PRINT 1\n10 PRINT 2\n');
  check(
    diags.some((d) => d.code === 'line-order'),
    'out-of-ascending-order line number is reported'
  );
}

// The parser recovers per physical line (basic/program.ml), so a program
// with several independent problems gets a diagnostic for each rather than
// stopping at the first.
{
  const diags = n88basicCheck('10 GOTO 999\n20 GOSUB 888\n30 PRINT (\n');
  check(diags.length >= 3, `multiple independent problems all reported (got ${diags.length})`);
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
process.exit(0);
