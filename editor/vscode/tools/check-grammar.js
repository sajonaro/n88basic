#!/usr/bin/env node
'use strict';

// Verifies the committed grammar hasn't drifted from spec/keywords.json,
// and that it's well-formed. Exits non-zero on any failure. Run this in CI
// / before committing a spec change.
//
// Checks, in order:
//   1. syntaxes/n88basic.tmLanguage.json is valid JSON.
//   2. language-configuration.json is valid JSON.
//   3. Regenerating the grammar from the current spec/keywords.json
//      produces byte-identical output to what's committed -- if not, the
//      grammar is stale and someone forgot to re-run generate-grammar.js
//      after editing the spec.
//   4. Every "match", "begin", and "end" regex string in the grammar
//      compiles as a JS RegExp (a proxy for "compiles under Oniguruma" --
//      see keyword-model.js's ciLiteral comment for why the generator
//      avoids Oniguruma-only syntax so this check means what it says).

const fs = require('fs');
const path = require('path');
const { loadKeywordsData, defaultSpecPath } = require('../src/keyword-model');
const { buildGrammar } = require('./lib/build-grammar');

const GRAMMAR_PATH = path.join(__dirname, '..', 'syntaxes', 'n88basic.tmLanguage.json');
const LANG_CONFIG_PATH = path.join(__dirname, '..', 'language-configuration.json');

let failures = 0;

function fail(message) {
  console.error(`FAIL: ${message}`);
  failures++;
}

function ok(message) {
  console.log(`ok: ${message}`);
}

function readJson(filePath, label) {
  let text;
  try {
    text = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    fail(`${label}: cannot read ${filePath}: ${err.message}`);
    return null;
  }
  try {
    const parsed = JSON.parse(text);
    ok(`${label} is valid JSON (${filePath})`);
    return parsed;
  } catch (err) {
    fail(`${label}: invalid JSON in ${filePath}: ${err.message}`);
    return null;
  }
}

// Recursively finds every {match}/{begin}/{end} regex string in a
// TextMate-shaped grammar tree.
function collectRegexStrings(node, out) {
  if (Array.isArray(node)) {
    for (const item of node) collectRegexStrings(item, out);
    return;
  }
  if (node && typeof node === 'object') {
    for (const key of ['match', 'begin', 'end']) {
      if (typeof node[key] === 'string') out.push({ key, pattern: node[key] });
    }
    for (const value of Object.values(node)) collectRegexStrings(value, out);
  }
}

function checkRegexesCompile(grammar) {
  const found = [];
  collectRegexStrings(grammar, found);
  if (found.length === 0) {
    fail('no match/begin/end regex strings found in grammar -- that itself looks wrong');
    return;
  }
  let bad = 0;
  for (const { key, pattern } of found) {
    try {
      // eslint-disable-next-line no-new
      new RegExp(pattern);
    } catch (err) {
      fail(`regex in "${key}" does not compile: ${pattern} (${err.message})`);
      bad++;
    }
  }
  if (bad === 0) ok(`all ${found.length} match/begin/end regex strings compile as RegExp`);
}

function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function checkNotStale() {
  const specPath = defaultSpecPath();
  let data;
  try {
    data = loadKeywordsData(specPath);
  } catch (err) {
    fail(`cannot read ${specPath}: ${err.message}`);
    return null;
  }
  const { grammar: fresh } = buildGrammar(data);

  let committed;
  try {
    committed = JSON.parse(fs.readFileSync(GRAMMAR_PATH, 'utf8'));
  } catch (err) {
    fail(`cannot read committed grammar ${GRAMMAR_PATH}: ${err.message}`);
    return null;
  }

  if (deepEqual(fresh, committed)) {
    ok('committed grammar matches what generate-grammar.js produces from the current spec/keywords.json (not stale)');
  } else {
    fail(
      `${GRAMMAR_PATH} is out of step with ${specPath} -- ` +
        're-run "node editor/vscode/tools/generate-grammar.js" and commit the result'
    );
    const freshKeys = new Set(fresh.repository.keywords.patterns.map((p) => p.match));
    const committedKeys = new Set(committed.repository && committed.repository.keywords ? committed.repository.keywords.patterns.map((p) => p.match) : []);
    const onlyFresh = [...freshKeys].filter((k) => !committedKeys.has(k));
    const onlyCommitted = [...committedKeys].filter((k) => !freshKeys.has(k));
    if (onlyFresh.length) console.error(`  ${onlyFresh.length} keyword rule(s) missing from the committed file`);
    if (onlyCommitted.length) console.error(`  ${onlyCommitted.length} keyword rule(s) in the committed file no longer produced by the spec`);
  }
  return fresh;
}

function main() {
  readJson(LANG_CONFIG_PATH, 'language-configuration.json');
  const committedGrammar = readJson(GRAMMAR_PATH, 'syntaxes/n88basic.tmLanguage.json');

  const fresh = checkNotStale();

  if (committedGrammar) {
    checkRegexesCompile(committedGrammar);
  } else if (fresh) {
    checkRegexesCompile(fresh);
  }

  if (failures > 0) {
    console.error(`\n${failures} check(s) failed`);
    process.exit(1);
  }
  console.log('\nall checks passed');
  process.exit(0);
}

main();
