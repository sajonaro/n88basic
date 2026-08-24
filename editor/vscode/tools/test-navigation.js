'use strict';

// Go-to-definition and find-references, tested as pure functions — no VSCode
// host. Run: node editor/vscode/tools/test-navigation.js

const nav = require('../src/navigation');

let failures = 0;
function check(cond, what) {
  if (cond) console.log(`  ok   ${what}`);
  else {
    console.log(`  FAIL ${what}`);
    failures += 1;
  }
}
function eq(actual, expected, what) {
  check(JSON.stringify(actual) === JSON.stringify(expected), `${what} (got ${JSON.stringify(actual)})`);
}

const PROG = [
  '10 PRINT "START"',
  '20 GOTO 40',
  '30 PRINT "GOTO 40 in a string"',
  '40 ON X GOSUB 10,30',
  "50 REM GOTO 10 in a comment",
  '60 IF X THEN 10 ELSE 30',
  '70 RESTORE 10',
  '80 RESUME 30',
].join('\n');

console.log('lineNumberAt');
// "20 GOTO 40" — column 8 is inside the target 40
eq(nav.lineNumberAt(PROG, 1, 8), { kind: 'reference', number: 40, start: 8, end: 10 },
  'a jump target is recognised');
// column 0 is inside the line's own number
eq(nav.lineNumberAt(PROG, 1, 0), { kind: 'definition', number: 20, start: 0, end: 2 },
  "a line's own number is recognised");
check(nav.lineNumberAt(PROG, 0, 12) === null, 'nothing is claimed inside a string literal');

console.log('definitionTargets');
eq(nav.definitionTargets(PROG, 1, 8), [{ lineIndex: 3, start: 0, end: 2 }],
  'GOTO 40 resolves to the line beginning 40');
eq(nav.definitionTargets(PROG, 1, 0), [],
  "standing on a line's own number offers no jump to itself");
eq(nav.definitionTargets(PROG, 2, 12), [],
  'a number inside a string is not a jump target');

console.log('referencesTo');
// Line 10 is named by: ON X GOSUB 10,30 / THEN 10 / RESTORE 10.
// NOT by the comment on line 50 or the string on line 30.
eq(nav.referencesTo(PROG, 10).map((r) => r.lineIndex), [3, 5, 6],
  'references to 10 skip the comment and the string literal');
eq(nav.referencesTo(PROG, 30).map((r) => r.lineIndex), [3, 5, 7],
  'references to 30 include the ON…GOSUB list entry, ELSE, and RESUME');
eq(nav.referencesTo(PROG, 99), [], 'a number nothing names has no references');

console.log('referenceTargets');
// Standing on a jump target, find-references reports every reference to that
// number — including the one under the cursor, which is itself a reference.
eq(nav.referenceTargets(PROG, 1, 8, {}).map((r) => r.lineIndex), [1],
  'from GOTO 40, the only reference to 40 is that GOTO itself');
eq(nav.referenceTargets(PROG, 3, 0, {}).map((r) => r.lineIndex), [1],
  "from line 40's own number, its one caller is found");
eq(nav.referenceTargets(PROG, 3, 0, { includeDeclaration: true }).map((r) => r.lineIndex), [3, 1],
  'includeDeclaration puts the definition alongside the uses');

console.log('duplicates are all reported, not silently narrowed');
const DUP = '10 PRINT 1\n10 PRINT 2\n20 GOTO 10\n';
eq(nav.definitionTargets(DUP, 2, 8).map((d) => d.lineIndex), [0, 1],
  'a duplicated target returns both definitions');

console.log(failures ? `\n${failures} failure(s)` : '\nall navigation checks passed');
process.exit(failures ? 1 : 0);
