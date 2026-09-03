'use strict';

// The manifest is the one file in this extension that nothing else could
// test: every other part is exercised by loading it, but package.json is
// read by VSCode itself, on the UI host, before any of our code runs. A
// fault here does not throw anywhere we can see -- the extension is simply
// skipped, silently, and everything downstream looks fine from in here.
//
// That is not hypothetical. `publisher` was missing for the whole life of
// the extension. VSCode builds an extension's identity as `<publisher>.<name>`
// when it scans the extensions folder, so a manifest without one has no
// identity to register under; the install path this repo documents,
// `n88basic.n88basic-0.1.0`, is that identifier and implies a publisher the
// manifest never declared. It is the leading explanation for why the
// extension has never once been confirmed to load.
//
// So this checks the things whose absence is invisible from this side.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));

const failures = [];
const check = (ok, message) => {
  if (!ok) failures.push(message);
};

// VSCode requires these to register the extension at all.
// extensionKind decides WHICH MACHINE the extension runs on, and everything
// this one does belongs where the files are: run.js and session.js spawn the
// interpreter, the language client talks to a server that parses workspace
// files, and diagnostics, hover and completion all read them. Nothing here is
// UI-only.
//
// It was ["ui", "workspace"], and "ui" first means VSCode loads the extension
// on the LOCAL machine. In any remote window -- WSL, SSH, a dev container,
// Codespaces -- the workspace and the interpreter are on the remote and the UI
// is local, so Run created a terminal on the wrong side and handed it a path
// from the other one:
//
//   The terminal process failed to launch: Starting directory (cwd)
//   "\root\docs\projects\..." does not exist.
//
// The newer commands would fail differently and more confusingly: session.js
// spawns the interpreter directly, and on the local side n88 is not installed
// at all, so an immediate session dies with a missing binary rather than a bad
// path.
//
// This is checked HERE, in the manifest test, because the manifest is what
// decides which machine the code paths run on -- the feature tests exercise
// the code and would pass on either side of the boundary. Same shape as the
// Run command that shelled `dune exec`: correct behaviour, wrong machine.
check(
  Array.isArray(manifest.extensionKind) &&
    manifest.extensionKind.length === 1 &&
    manifest.extensionKind[0] === 'workspace',
  'extensionKind is exactly ["workspace"] -- it spawns the interpreter and reads workspace files'
);

for (const field of ['name', 'publisher', 'version', 'engines', 'main']) {
  check(
    manifest[field] !== undefined && manifest[field] !== '',
    `package.json is missing "${field}", without which VSCode cannot register the extension`
  );
}

check(
  manifest.engines && typeof manifest.engines.vscode === 'string',
  'engines.vscode must name a VSCode version range'
);

// Every path the manifest contributes must exist, or the contribution is
// dropped on load -- again silently.
// The Overview panel is opened BEFORE you have a BASIC file -- possibly on
// first install, which is the whole point of putting it in the Activity Bar.
// With only onLanguage activation the icon appears and the panel stays empty
// exactly when it matters most.
{
  const views = manifest.contributes?.views?.n88basic ?? [];
  const ae = manifest.activationEvents ?? [];
  for (const v of views)
    check(
      ae.includes(`onView:${v.id}`),
      `activationEvents contains onView:${v.id}, so the panel works with no BASIC file open`
    );
}

const contributedPaths = [];
if (manifest.main) contributedPaths.push(['main', manifest.main]);
for (const [i, g] of (manifest.contributes?.grammars ?? []).entries())
  contributedPaths.push([`contributes.grammars[${i}].path`, g.path]);
for (const [i, l] of (manifest.contributes?.languages ?? []).entries()) {
  if (l.configuration) contributedPaths.push([`contributes.languages[${i}].configuration`, l.configuration]);
  for (const theme of ['light', 'dark'])
    if (l.icon?.[theme]) contributedPaths.push([`contributes.languages[${i}].icon.${theme}`, l.icon[theme]]);
}
for (const [i, s] of (manifest.contributes?.snippets ?? []).entries())
  contributedPaths.push([`contributes.snippets[${i}].path`, s.path]);
// The marketplace image and the Activity Bar mark. Neither is loaded at
// runtime by anything this suite exercises, so a path that points nowhere here
// ships silently: a missing marketplace icon fails at publish time and a
// missing Activity Bar icon leaves a blank square in the strip. This is the
// only check either of them gets.
if (manifest.icon) contributedPaths.push(['icon', manifest.icon]);
for (const [i, v] of (manifest.contributes?.viewsContainers?.activitybar ?? []).entries())
  contributedPaths.push([`contributes.viewsContainers.activitybar[${i}].icon`, v.icon]);

for (const [label, rel] of contributedPaths)
  check(fs.existsSync(path.join(root, rel)), `${label} points at ${rel}, which does not exist`);

// A contributed command with no registration is a menu entry that throws
// "command not found" when a user picks it.
const sources = [fs.readFileSync(path.join(root, 'extension.js'), 'utf8')].concat(
  fs.readdirSync(path.join(root, 'src')).map((f) => fs.readFileSync(path.join(root, 'src', f), 'utf8'))
);
for (const command of (manifest.contributes?.commands ?? []).map((c) => c.command))
  check(
    sources.some((s) => s.includes(command)),
    `command "${command}" is contributed but never registered in extension.js or src/`
  );

// The runtime dependencies are vendored (Alex's ruling, 2026-08-17) so the
// extension stays install-by-copy with no build step. That only holds if the
// tree is actually complete in the repo AND actually gets copied -- and a
// missing dependency does not fail loudly, it fails when someone first enables
// the server, in an editor nobody here can see. So assert it from this side,
// which is the same reason this file exists at all.
const runtimeDeps = Object.keys(manifest.dependencies ?? {});
check(runtimeDeps.length > 0, 'package.json declares no runtime dependencies; the vendoring check below is then vacuous');
// Walk the dependency GRAPH, not just the declared three. A first version
// checked only that each declared directory existed and passed happily with
// `semver` -- a dependency of a dependency -- deleted. A second tried to
// require() them, which cannot work: vscode-languageclient requires 'vscode',
// which exists only inside the extension host. Reading each vendored package's
// own dependencies is the version that actually covers the tree.
const seen = new Set();
const queue = [...runtimeDeps];
while (queue.length > 0) {
  const dep = queue.shift();
  if (seen.has(dep)) continue;
  seen.add(dep);
  const manifestPath = path.join(root, 'node_modules', dep, 'package.json');
  if (!fs.existsSync(manifestPath)) {
    failures.push(
      `dependency "${dep}" is required by the vendored tree but is not present under node_modules/ -- ` +
        `the extension installs by copying, so an absent one means the server cannot start`
    );
    continue;
  }
  const depManifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  queue.push(...Object.keys(depManifest.dependencies ?? {}));
}

// A tracked symlink is what destroyed the opam switch on 2026-08-17: git
// records mode 120000 and a checkout recreates it, which for a self-referential
// target loops over a real directory. The vendored tree must contain none.
const symlinks = [];
(function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isSymbolicLink()) symlinks.push(path.relative(root, full));
    else if (entry.isDirectory()) walk(full);
  }
})(path.join(root, 'node_modules'));
check(
  symlinks.length === 0,
  `the vendored tree contains symlinks, which must not be committed: ${symlinks.join(', ')}`
);

if (failures.length > 0) {
  console.error('manifest FAILED:');
  for (const f of failures) console.error('  - ' + f);
  process.exit(1);
}
console.log(
  `manifest OK (${manifest.publisher}.${manifest.name}-${manifest.version}, ` +
    `${contributedPaths.length} contributed paths, ${seen.size} vendored packages, 0 symlinks)`
);
