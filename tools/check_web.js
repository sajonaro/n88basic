#!/usr/bin/env node
'use strict';
// check_web.js -- the browser build must agree with the corpus.
//
// WHY THIS IS NOT OPTIONAL. web/main.ml is a second HOST, not a second
// interpreter, and the whole claim of the web console is that it runs the same
// language. That claim is checkable and nothing else checks it: dune test
// links the library natively, scripts/conform.sh drives the CLI, and neither
// touches the JavaScript.
//
// It is also the only thing standing between us and a real hazard.
// js_of_ocaml warns "the generated code might be incorrect" on the CRC-32 and
// deflate constants in raster/, because 0xffffffff and 0xedb88320 do not fit
// an OCaml int on a 32-bit target. They are fine -- every drawing hashes
// identically -- but "fine" was a measurement, not a deduction, and it needs
// re-measuring whenever raster/ or the compiler moves.
//
// Usage:  node tools/check_web.js

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = path.resolve(__dirname, '..');
const bundle = path.join(root, '_build/default/web/main.bc.js');
if (!fs.existsSync(bundle)) {
  console.error('no browser build -- run `dune build @web/web` first');
  process.exit(2);
}
const api = require(bundle).n88;
const dir = path.join(root, 'test/conformance');
const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');

let pass = 0;
const fail = [];

// Text cases. The .stdin sidecar is the program's INPUT answers, which is
// exactly what the page's input box supplies.
for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.expected')).sort()) {
  const name = f.replace(/\.expected$/, '');
  const stdin = fs.existsSync(path.join(dir, name + '.stdin')) ? read(name + '.stdin') : '';
  const r = api.run(read(name + '.bas'), stdin);
  // The in-process runner concatenates stdout then the error's own text; the
  // browser host returns them separately, so they are joined the same way here.
  const got = r.output + (r.error ? r.error + '\n' : '');
  if (got === read(f)) pass++;
  else fail.push(`${name}: text differs`);
}

// Drawing cases, against the same PNG hashes scripts/conform.sh uses for the
// released binary and the container.
for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.pnghash')).sort()) {
  const name = f.replace(/\.pnghash$/, '');
  const r = api.run(read(name + '.bas'), '');
  if (!r.png) { fail.push(`${name}: drew no PNG`); continue; }
  const got = crypto.createHash('sha256').update(Buffer.from(r.png, 'binary')).digest('hex');
  if (got === read(f).trim()) pass++;
  else fail.push(`${name}: PNG differs (web ${got.slice(0, 16)}, expected ${read(f).trim().slice(0, 16)})`);
}

for (const f of fail) console.log(`  FAIL ${f}`);
console.log(`\n${pass} of ${pass + fail.length} conformance cases match through the browser build.`);
if (fail.length) process.exit(1);
console.log('The page runs the same language as the command line, drawings included.');
