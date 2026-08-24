'use strict';

// Loads spec/keywords.json and spec/clauses.json and builds the lookup
// structures hover.js and completion.js are built from. Plain CommonJS, no
// `require('vscode')` anywhere in this file -- it must load and run
// standalone under plain node (see tools/test-features.js).

const fs = require('fs');
const path = require('path');
const { stripQualifier, wordsOf } = require('./keyword-model');

// Where the spec data lives depends on how the extension is being run, and
// getting this wrong fails silently -- hover and completion simply find
// nothing, with no error anywhere. Two situations, in priority order:
//
//   1. Installed. The extension is copied into the editor's extensions
//      directory, far from this repository, and ships its own copy of the
//      two JSON files alongside package.json.
//   2. Developed. Running from a checkout, three levels up from src/ is the
//      repository root and spec/ is the live copy -- which is what you want
//      here, so an edit to keywords.json shows up in hover without a
//      reinstall.
//
// Walking up from __dirname looking for the files, rather than assuming a
// fixed depth, covers both without either having to know about the other.
const EXTENSION_ROOT = path.join(__dirname, '..');

function findSpecDir() {
  const candidates = [EXTENSION_ROOT];
  let dir = EXTENSION_ROOT;
  for (let i = 0; i < 6; i += 1) {
    dir = path.dirname(dir);
    candidates.push(dir);
  }
  for (const base of candidates) {
    if (fs.existsSync(path.join(base, 'spec', 'keywords.json'))) {
      return path.join(base, 'spec');
    }
  }
  // Returned rather than thrown: the caller's readFileSync produces a far
  // more useful message, naming the path it actually looked for.
  return path.join(EXTENSION_ROOT, 'spec');
}

const SPEC_DIR = findSpecDir();
const REPO_ROOT = path.dirname(SPEC_DIR);

function keywordsPath() {
  return path.join(SPEC_DIR, 'keywords.json');
}

function clausesPath() {
  return path.join(SPEC_DIR, 'clauses.json');
}

function loadKeywords(customPath) {
  return JSON.parse(fs.readFileSync(customPath || keywordsPath(), 'utf8'));
}

function loadClauses(customPath) {
  return JSON.parse(fs.readFileSync(customPath || clausesPath(), 'utf8'));
}

// spec/spec.md §2: clauses.json carries "an evidence grade naming what the
// claim rests on". "manual" (with a source citation) is the only grade this
// spec version uses; everything else means the clause is a stub -- see
// docs/superpowers/specs/2026-08-16-n88basic-design.md §7's "clauses
// grounded in the manual" for the term this function is named after.
function isGrounded(clause) {
  return !!clause && clause.evidence === 'manual' && !!clause.source;
}

function clauseIndex(clausesData) {
  const byId = new Map();
  for (const clause of clausesData.clauses) byId.set(clause.id, clause);
  return byId;
}

const SCOPE_PRIORITY = { in: 0, deferred: 1, out: 2 };

// Several keyword entries can share the same literal source text -- "GET
// (graphics)"/"GET (file)", or the "ON" that both "ON…GOTO" and
// "ON…GOSUB" contribute (see keywords.json's "naming" note). Pick one
// deterministically: most in-scope first, then alphabetical by full name,
// so the same input always resolves to the same entry.
function resolveBestEntry(entries) {
  return [...entries].sort((a, b) => {
    const diff = SCOPE_PRIORITY[a.scope] - SCOPE_PRIORITY[b.scope];
    if (diff !== 0) return diff;
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
  })[0];
}

// Keyword kinds that can appear as literal text in a program, as opposed to
// type-suffix characters and the comment marker, which are handled by the
// grammar's own dedicated rules (see src/keyword-model.js).
const WORDLIKE_KINDS = new Set(['statement', 'function', 'function-statement', 'clause', 'option', 'device']);

// One phrase per literal text a keyword contributes, keeping the whole
// keyword record (unlike src/keyword-model.js's buildPhraseGroups,
// which merges down to grammar-only fields). An ellipsis name ("ON…GOTO")
// still decomposes into one candidate per side, same rule as the grammar
// generator, so "ON" is findable even though "ON X GOTO 10" is not one
// fixed phrase.
function buildPhraseEntries(keywordsData) {
  const phrases = [];
  for (const entry of keywordsData.keywords) {
    if (!WORDLIKE_KINDS.has(entry.kind)) continue;
    const display = stripQualifier(entry.name);
    const { words, hasGap } = wordsOf(display);
    if (words.length === 0) continue;
    if (hasGap) {
      for (const w of words) phrases.push({ words: [w], entry });
    } else {
      phrases.push({ words, entry });
    }
  }
  return phrases;
}

// Cached, since keywords.json/clauses.json don't change while the extension
// runs. `fresh: true` bypasses the cache -- used by tests that pass a
// custom path.
let cached = null;

function loadAll(options) {
  const opts = options || {};
  if (!opts.fresh && cached) return cached;
  const keywordsData = loadKeywords(opts.keywordsPath);
  const clausesData = loadClauses(opts.clausesPath);
  const result = {
    keywordsData,
    clausesData,
    clausesById: clauseIndex(clausesData),
    phraseEntries: buildPhraseEntries(keywordsData),
  };
  if (!opts.fresh) cached = result;
  return result;
}

module.exports = {
  REPO_ROOT,
  WORDLIKE_KINDS,
  keywordsPath,
  clausesPath,
  loadKeywords,
  loadClauses,
  isGrounded,
  clauseIndex,
  resolveBestEntry,
  buildPhraseEntries,
  loadAll,
};
