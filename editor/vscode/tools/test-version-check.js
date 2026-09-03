'use strict';
// Run: node editor/vscode/tools/test-version-check.js
const { compareVersions, verdict, MINIMUM } = require('../src/version-check');
let failures = 0;
const check = (c, l) => { console.log(`${c ? 'ok  ' : 'FAIL'}: ${l}`); if (!c) failures++; };

check(compareVersions('0.1.1', '0.1.3') < 0, 'compare: 0.1.1 is older than 0.1.3');
check(compareVersions('0.1.4', '0.1.4') === 0, 'compare: equal versions compare equal');
// Lexical comparison gets this wrong, and it is the classic way a version
// check starts lying after ten releases.
check(compareVersions('0.1.10', '0.1.9') > 0, 'compare: 0.1.10 is NEWER than 0.1.9, numerically');
check(compareVersions('0.2', '0.1.9') > 0, 'compare: missing components count as zero');

check(verdict('0.1.4', null).level === 'error', 'verdict: a missing interpreter is an error');
check(verdict('0.1.4', '0.1.1').level === 'warning', 'verdict: below the floor is a warning');
check(verdict('0.1.4', '0.1.1').message.includes(MINIMUM), 'verdict: the warning names the minimum');
check(verdict('0.1.4', '0.1.3').level === 'info', 'verdict: behind the extension but usable is info');
check(verdict('0.1.4', '0.1.4') === null, 'verdict: matched versions say nothing');
check(verdict('0.1.4', '0.2.0') === null, 'verdict: an interpreter AHEAD says nothing');
check(verdict('0.1.4', 'wrapper v9').level === 'info', 'verdict: unparseable output is reported, not assumed fine');
check(verdict('0.1.4', ' 0.1.4\n') === null, 'verdict: trailing newline from the CLI is tolerated');

if (failures) { console.error(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nall checks passed');
