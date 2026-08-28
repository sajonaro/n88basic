'use strict';

// Exercises src/session.js's pure logic, and then the thing that actually
// matters: that a real n88 answers what the extension would send it. The
// second half is skipped rather than failed when no interpreter is on PATH,
// because a contributor without one should still be able to run the suite --
// but it SAYS it skipped, since a check that quietly passes when it did
// nothing is worse than no check.
//
// Run: node editor/vscode/tools/test-session.js

const { spawnSync } = require('child_process');
const session = require('../src/session');

let failures = 0;
function check(cond, label) {
  console.log(`${cond ? 'ok  ' : 'FAIL'}: ${label}`);
  if (!cond) failures++;
}

// --- pure -------------------------------------------------------------------
check(session.interpreterCommand(null) === 'n88', 'interpreterCommand: defaults to n88 on PATH');
check(session.interpreterCommand({ get: () => '/opt/n88' }) === '/opt/n88', 'interpreterCommand: configured path wins');
check(session.interpreterCommand({ get: () => '  ' }) === 'n88', 'interpreterCommand: blank falls back');

check(session.selectedProgram('10 A=1\n', '') === '10 A=1\n', 'selectedProgram: no selection means the whole buffer');
check(session.selectedProgram('10 A=1\n', '20 B=2') === '20 B=2\n', 'selectedProgram: a selection is a program in its own right');
check(session.selectedProgram('10 A=1\n', '   ') === '10 A=1\n', 'selectedProgram: whitespace-only selection is no selection');
check(session.immediateInput('PRINT 1\n\n') === 'PRINT 1\n', 'immediateInput: exactly one newline, whatever arrived');

// --- against a real interpreter ---------------------------------------------
const n88 = process.env.N88 || 'n88';
const probe = spawnSync(n88, ['--version'], { encoding: 'utf8' });
if (probe.error) {
  console.log(`\nSKIPPED the end-to-end checks: no interpreter at ${n88}.`);
  console.log('Set N88=/path/to/n88 to run them. They are the half that proves');
  console.log('the extension sends something the interpreter actually accepts.');
} else {
  const buffer = spawnSync(n88, ['-'], { input: '10 PRINT "buffer";1+1\n', encoding: 'utf8' });
  check(buffer.stdout.includes('buffer 2'), 'execute buffer: n88 - runs what the editor would pipe');

  const sel = spawnSync(n88, ['-'], {
    input: session.selectedProgram('10 PRINT "all"\n', '20 PRINT "just this"'),
    encoding: 'utf8',
  });
  check(sel.stdout.includes('just this') && !sel.stdout.includes('all'),
    'execute selection: only the selected lines run');

  // The whole point of the immediate command: one process, state carried
  // across statements, exactly as the extension drives it.
  const live = spawnSync(n88, ['--immediate'], {
    input: session.immediateInput('A=7') + session.immediateInput('PRINT A*2'),
    encoding: 'utf8',
  });
  check(/\s14\s/.test(live.stdout), 'immediate statement: state persists between statements');
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
