'use strict';
// Run: node editor/vscode/tools/test-panel.js
const { renderHtml } = require('../src/panel');
let failures = 0;
const check = (c, l) => { console.log(`${c ? 'ok  ' : 'FAIL'}: ${l}`); if (!c) failures++; };

const matched = renderHtml({ extensionVersion: '0.1.4', interpreter: '0.1.4', interpreterPath: '' });
check(matched.includes('class="status ok"'), 'matched versions: green status');
check(!matched.includes('id="upgrade"'), 'matched versions: no upgrade button to ignore');

const behind = renderHtml({ extensionVersion: '0.1.4', interpreter: '0.1.1', interpreterPath: '' });
check(behind.includes('class="status warn"'), 'interpreter below the floor: warning status');
check(behind.includes('id="upgrade"'), 'interpreter below the floor: offers the upgrade link');
check(behind.includes('0.1.1'), 'interpreter below the floor: shows the version it found');

const missing = renderHtml({ extensionVersion: '0.1.4', interpreter: null, interpreterPath: '/opt/n88' });
check(missing.includes('class="status bad"'), 'no interpreter: error status');
check(missing.includes('not found'), 'no interpreter: says so plainly');
check(missing.includes('/opt/n88'), 'no interpreter: names the path it looked at');

const ahead = renderHtml({ extensionVersion: '0.1.4', interpreter: '0.2.0', interpreterPath: '' });
check(ahead.includes('class="status ok"'), 'interpreter ahead: still fine, not a warning');

// The version string reaches the DOM, so it is a place untrusted-ish text is
// interpolated. A wrapper script can print anything at all.
const nasty = renderHtml({
  extensionVersion: '0.1.4',
  interpreter: '<img src=x onerror=alert(1)>',
  interpreterPath: '"><script>alert(2)</script>',
});
check(!nasty.includes('<img src=x'), 'escaping: interpreter output cannot inject markup');
check(!nasty.includes('<script>alert(2)'), 'escaping: the configured path cannot either');

// Every button must name a command the manifest actually contributes.
const manifest = require('../package.json');
const contributed = new Set(manifest.contributes.commands.map((c) => c.command));
for (const m of matched.matchAll(/data-cmd="([^"]+)"/g))
  check(contributed.has(m[1]), `panel button ${m[1]} is a contributed command`);

if (failures) { console.error(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nall checks passed');
