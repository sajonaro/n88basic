'use strict';

// Turns spec/keywords.json into the phrase groups the TextMate grammar is
// built from. This is the ONLY place that reads keywords.json's shape, so
// generate-grammar.js and check-grammar.js can never drift from each other
// -- they both call buildPhraseGroups() and get the same answer.
//
// The three pitfalls the task calls out are handled here, generically, not
// by naming the specific keywords that trigger them:
//
//   1. "GET (graphics)" / "GET (file)" -- the parenthetical is an editorial
//      disambiguator (see keywords.json's "naming" note), stripped before
//      the name is used as source text.
//   2. "ON…GOTO" / "ON…GOSUB" -- the U+2026 marks a real expression in real
//      source ("ON X GOTO 10,20"), not literal text, so a name containing it
//      cannot become one fixed phrase. It decomposes into independent
//      single-word candidates instead (see collectPhraseCandidates).
//   3. Multi-word names ("KEY OFF", "LINE INPUT#") stay as one fixed phrase
//      so that, e.g., bare "KEY" (out of scope) and "KEY OFF" (in scope)
//      don't collide -- see mergeCandidates and the sort in sortGroups for
//      how phrase-vs-prefix precedence is resolved without hardcoding which
//      names collide.

const fs = require('fs');
const path = require('path');

const ELLIPSIS = '…';

const WORDLIKE_KINDS = new Set([
  'statement',
  'function',
  'function-statement',
  'clause',
  'option',
  'device',
]);

// Any keyword whose spec summary calls it a "comment" is a comment marker.
// Currently matches "'" (kind: comment) and "REM" (kind: statement) -- both
// pulled from the data, not named directly, so a future comment-introducing
// keyword picks itself up automatically.
function isCommentMarker(entry) {
  return typeof entry.summary === 'string' && /comment/i.test(entry.summary);
}

function stripQualifier(name) {
  return name.replace(/\s*\([^)]*\)\s*$/, '').trim();
}

function wordsOf(displayName) {
  if (displayName.includes(ELLIPSIS)) {
    return {
      words: displayName.split(ELLIPSIS).map((w) => w.trim()).filter(Boolean),
      hasGap: true,
    };
  }
  return { words: displayName.split(/\s+/).filter(Boolean), hasGap: false };
}

function loadKeywordsData(specPath) {
  const raw = fs.readFileSync(specPath, 'utf8');
  return JSON.parse(raw);
}

function defaultSpecPath() {
  // Walk up looking for spec/keywords.json rather than counting directories.
  // A fixed depth breaks the moment this file moves or the extension is
  // installed away from the repository, and it breaks silently -- the read
  // just misses. See src/spec-data.js, which resolves the same way.
  let dir = path.join(__dirname, '..');
  for (let i = 0; i < 7; i += 1) {
    const candidate = path.join(dir, 'spec', 'keywords.json');
    if (fs.existsSync(candidate)) return candidate;
    dir = path.dirname(dir);
  }
  return path.join(__dirname, '..', 'spec', 'keywords.json');
}

// One candidate per literal phrase a keyword entry contributes. An
// ellipsis name contributes one candidate per side of the ellipsis instead
// of one fixed phrase, because the text between the words varies at the
// call site.
function collectPhraseCandidates(keywords) {
  const candidates = [];
  for (const entry of keywords) {
    if (!WORDLIKE_KINDS.has(entry.kind)) continue; // type-suffix, comment
    if (isCommentMarker(entry)) continue; // handled by comment rules instead
    const display = stripQualifier(entry.name);
    const { words, hasGap } = wordsOf(display);
    if (words.length === 0) continue;
    if (hasGap) {
      for (const w of words) {
        candidates.push({ words: [w], kind: entry.kind, scope: entry.scope, source: entry.name });
      }
    } else {
      candidates.push({ words, kind: entry.kind, scope: entry.scope, source: entry.name });
    }
  }
  return candidates;
}

const SCOPE_PRIORITY = { in: 0, deferred: 1, out: 2 };

// Merges candidates that resolve to the same literal source text. Some
// merges are harmless (ON…GOTO and ON…GOSUB both contribute the word "ON"
// with the same kind/scope -- just a duplicate). Some are genuine
// conflicts: the same literal text names two different features with
// different scopes (GET (graphics) vs GET
// (file), PUT (graphics) vs PUT (file)) and a regex over bare source text
// cannot tell them apart -- there's no parser here. Conflicts are resolved
// by scope priority in > deferred > out (prefer not flagging something as
// broken when a lexer can't be sure) and recorded in the `conflicts`
// return value so the choice is visible, not silent.
function mergeCandidates(candidates) {
  const byKey = new Map();
  for (const c of candidates) {
    const key = c.words.join(' ').toUpperCase();
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(c);
  }

  const groups = [];
  const conflicts = [];
  for (const list of byKey.values()) {
    const distinct = [];
    for (const c of list) {
      if (!distinct.some((d) => d.kind === c.kind && d.scope === c.scope)) distinct.push(c);
    }
    let chosen = distinct[0];
    for (const c of distinct.slice(1)) {
      if (SCOPE_PRIORITY[c.scope] < SCOPE_PRIORITY[chosen.scope]) chosen = c;
    }
    if (distinct.length > 1) {
      conflicts.push({
        text: list[0].words.join(' '),
        candidates: distinct.map((d) => ({ kind: d.kind, scope: d.scope, source: d.source })),
        resolvedScope: chosen.scope,
        rule: 'ambiguous keyword text (same literal source, different scope); resolved by priority in > deferred > out -- see editor/vscode/README.md',
      });
    }
    groups.push({
      words: chosen.words,
      kind: chosen.kind,
      scope: chosen.scope,
      sources: [...new Set(list.map((l) => l.source))],
    });
  }
  return { groups, conflicts };
}

function buildPhraseGroups(keywords) {
  const candidates = collectPhraseCandidates(keywords);
  return mergeCandidates(candidates);
}

// Longer / more literal phrases must be tried before shorter ones that are
// a prefix of them ("LINE INPUT#" before "LINE INPUT" before "LINE"), or a
// short in-scope keyword could steal a longer out-of-scope one's text.
// Sorting globally by specificity -- not by scope or category -- means this
// holds regardless of which scope each phrase happens to carry.
function groupSortKey(g) {
  const totalLen = g.words.reduce((n, w) => n + w.length, 0);
  return [-g.words.length, -totalLen, g.words.join(' ')];
}

function sortGroups(groups) {
  return [...groups].sort((a, b) => {
    const ka = groupSortKey(a);
    const kb = groupSortKey(b);
    for (let i = 0; i < ka.length; i++) {
      if (ka[i] < kb[i]) return -1;
      if (ka[i] > kb[i]) return 1;
    }
    return 0;
  });
}

function suffixChars(keywords) {
  return keywords.filter((k) => k.kind === 'type-suffix').map((k) => k.name);
}

function commentMarkerEntries(keywords) {
  return keywords.filter(isCommentMarker);
}

const REGEX_SPECIAL = /[.*+?^${}()|[\]\\]/;

function escapeRegexChar(ch) {
  return REGEX_SPECIAL.test(ch) ? '\\' + ch : ch;
}

// A case-insensitive literal built from character classes rather than an
// engine flag or an inline modifier group. Oniguruma (what VS Code's
// grammar engine uses) accepts "(?i:...)", but plain Node RegExp -- used by
// check-grammar.js's "does every pattern compile" sanity check -- does not,
// so relying on it would make the checker lie. Character classes are
// standard regex and mean the same thing in both engines.
function ciLiteral(word) {
  return word
    .split('')
    .map((ch) => (/[A-Za-z]/.test(ch) ? `[${ch.toUpperCase()}${ch.toLowerCase()}]` : escapeRegexChar(ch)))
    .join('');
}

// Boundaries built from lookaround, not \b. \b is a *transition*: it holds
// only when exactly one side of the position is a word character. That
// breaks the moment the matched text can optionally end in a suffix
// character ("LEFT$", or a number with an optional %/!/# suffix): the
// engine would then require whatever comes *after* the "$" to be a word
// character, which is backwards -- "LEFT$ " or "LEFT$(" would fail to
// match. `(?<![A-Za-z0-9])` / `(?![A-Za-z0-9])` instead assert directly
// that the neighbouring character isn't alphanumeric, which is what "don't
// match inside a longer identifier" actually means and works the same
// whether or not an optional group before/after it matched.
const NOT_BEFORE_ALNUM = '(?<![A-Za-z0-9])';
const NOT_AFTER_ALNUM = '(?![A-Za-z0-9])';

// BASIC keywords are matched case-insensitively and can abut punctuation
// but not other identifier characters. A boundary is only meaningful next
// to a letter or digit; a word ending in "$" or "#" (LEFT$, INPUT#) needs
// no trailing boundary because those characters can't be
// identifier-continuation characters anyway.
function literalPattern(word) {
  const lead = /[A-Za-z0-9]/.test(word[0]) ? NOT_BEFORE_ALNUM : '';
  const trail = /[A-Za-z0-9]/.test(word[word.length - 1]) ? NOT_AFTER_ALNUM : '';
  return lead + ciLiteral(word) + trail;
}

function phraseMatch(words) {
  return words.map(literalPattern).join('\\s+');
}

module.exports = {
  ELLIPSIS,
  NOT_BEFORE_ALNUM,
  NOT_AFTER_ALNUM,
  loadKeywordsData,
  defaultSpecPath,
  stripQualifier,
  wordsOf,
  isCommentMarker,
  collectPhraseCandidates,
  mergeCandidates,
  buildPhraseGroups,
  sortGroups,
  suffixChars,
  commentMarkerEntries,
  ciLiteral,
  escapeRegexChar,
  literalPattern,
  phraseMatch,
};
