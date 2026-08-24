#!/usr/bin/env node
'use strict';

// Generates syntaxes/n88basic.tmLanguage.json from spec/keywords.json.
//
// Why generated rather than hand-written: spec/keywords.json is the single
// source of truth for what N88-BASIC(86) contains (spec/spec.md §2's
// companion-data table). A hand-maintained keyword list in a grammar file
// is a second source of truth that silently falls out of step with the
// spec the moment a keyword is added, renamed, or its scope changes --
// exactly the drift design §8's "hover and completion from keywords.json"
// argument warns about, applied to syntax highlighting instead.
//
// Usage: node editor/vscode/tools/generate-grammar.js
// Re-run this after any change to spec/keywords.json (or the hand-written
// operator/punctuation tables in tools/lib/build-grammar.js) and commit the
// regenerated syntaxes/n88basic.tmLanguage.json alongside it.
// tools/check-grammar.js verifies the two haven't drifted apart.

const fs = require('fs');
const path = require('path');
const { loadKeywordsData, defaultSpecPath } = require('../src/keyword-model');
const { buildGrammar } = require('./lib/build-grammar');

function main() {
  const specPath = defaultSpecPath();
  const outPath = path.join(__dirname, '..', 'syntaxes', 'n88basic.tmLanguage.json');

  const data = loadKeywordsData(specPath);
  const { grammar, conflicts } = buildGrammar(data);

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(grammar, null, 2) + '\n');

  const keywordRuleCount = grammar.repository.keywords.patterns.length;
  console.log(`generated ${outPath}`);
  console.log(`  from ${data.keywords.length} spec/keywords.json entries`);
  console.log(`  ${keywordRuleCount} keyword grammar rules`);
  if (conflicts.length) {
    console.log(`  ${conflicts.length} scope conflict(s) resolved (see grammar's "scopeConflicts"):`);
    for (const c of conflicts) {
      console.log(`    "${c.text}": ${c.candidates.map((x) => x.scope).join(' vs ')} -> chose ${c.resolvedScope}`);
    }
  }
}

main();
