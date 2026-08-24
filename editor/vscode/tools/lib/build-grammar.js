'use strict';

// Builds the TextMate grammar object from spec/keywords.json data. Pure
// function of its input -- no file I/O here -- so generate-grammar.js and
// check-grammar.js can both call it and compare results deterministically.

const {
  buildPhraseGroups,
  sortGroups,
  suffixChars,
  commentMarkerEntries,
  stripQualifier,
  ciLiteral,
  escapeRegexChar,
  phraseMatch,
  NOT_BEFORE_ALNUM,
  NOT_AFTER_ALNUM,
} = require('../../src/keyword-model');

// Scope names chosen so an ordinary theme colours them differently without
// any custom theme rules:
//   - kind decides the FAMILY: statements get keyword.control, functions
//     get support.function -- the two base scopes almost every theme
//     already styles apart (control-flow colour vs. builtin-call colour).
//   - scope decides the TIER: "in" keeps the family's normal colour;
//     "deferred" and "out" are both prefixed invalid.deprecated, a scope
//     old enough that most themes render it visibly differently (muted,
//     strikethrough, or red) -- exactly the "this parses but won't run"
//     signal spec/spec.md §3 asks the editor to surface. deferred and out
//     keep their own trailing segment (.deferred. / .out.) so a theme
//     author who wants to tell them apart still can, even though the
//     out-of-the-box colour is shared.
function scopeName(kind, scope) {
  const base =
    kind === 'function' || kind === 'function-statement'
      ? 'support.function'
      : kind === 'clause'
        ? 'keyword.control.conditional'
        : kind === 'option'
          ? 'keyword.other.option'
          : kind === 'device'
            ? 'support.type.device'
            : 'keyword.control'; // statement
  if (scope === 'in') return `${base}.n88basic`;
  const tier = scope === 'deferred' ? 'deferred' : 'out';
  return `invalid.deprecated.${tier}.${base.replace(/\./g, '-')}.n88basic`;
}

function buildKeywordPatterns(keywords) {
  const { groups, conflicts } = buildPhraseGroups(keywords);
  const sorted = sortGroups(groups);
  const patterns = sorted.map((g) => ({
    match: phraseMatch(g.words),
    name: scopeName(g.kind, g.scope),
  }));
  return { patterns, conflicts };
}

function buildCommentPatterns(keywords) {
  return commentMarkerEntries(keywords).map((entry) => {
    const display = stripQualifier(entry.name);
    const isWord = /^[A-Za-z]/.test(display);
    const lead = isWord ? '\\b' : '';
    return {
      match: `${lead}${ciLiteral(display)}.*$`,
      name: `comment.line.${isWord ? display.toLowerCase() : 'apostrophe'}.n88basic`,
    };
  });
}

// Hand-written, NOT derived from spec/keywords.json: arithmetic/relational
// operators and the logical/word operators (AND OR NOT MOD XOR EQV IMP) and
// FOR's TO/STEP are real N88-BASIC(86) reserved words but spec/keywords.json
// does not carry them (it inventories statements, functions, clauses,
// options, type-suffixes, comment markers, and devices -- operators aren't
// any of those kinds). basic/token.ml's reserved-word table confirms these
// are genuinely reserved in this interpreter. Longer symbolic operators are
// listed before the shorter operators they contain (<=, >=, <> before <, >,
// =) for the same prefix-precedence reason the generated keyword patterns
// are sorted longest-first.
const WORD_OPERATORS = ['AND', 'OR', 'NOT', 'MOD', 'XOR', 'EQV', 'IMP', 'STEP', 'TO'];

function buildOperatorPatterns() {
  const wordPatterns = WORD_OPERATORS.map((w) => ({
    match: `${NOT_BEFORE_ALNUM}${ciLiteral(w)}${NOT_AFTER_ALNUM}`,
    name: 'keyword.operator.word.n88basic',
  }));
  const symbolPatterns = ['<=', '>=', '<>', '=', '<', '>', '\\+', '-', '\\*', '/', '\\\\', '\\^'].map((m) => ({
    match: m,
    name: 'keyword.operator.n88basic',
  }));
  return [...wordPatterns, ...symbolPatterns];
}

// Also hand-written: statement separators and grouping punctuation. Not in
// keywords.json for the same reason operators aren't.
function buildPunctuationPatterns() {
  return [
    { match: '\\(', name: 'punctuation.section.round.begin.n88basic' },
    { match: '\\)', name: 'punctuation.section.round.end.n88basic' },
    { match: ',', name: 'punctuation.separator.comma.n88basic' },
    { match: ';', name: 'punctuation.separator.semicolon.n88basic' },
    { match: ':', name: 'punctuation.separator.statement.n88basic' },
  ];
}

function buildNumberPatterns(suffixes) {
  const suffixClass = suffixes.length ? `[${suffixes.map(escapeRegexChar).join('')}]` : '';
  const suffixOpt = suffixClass ? `${suffixClass}?` : '';
  // N88-BASIC(86) float literals take an exponent marker (single/double
  // precision) after the mantissa. &H/&O radix literals are deliberately
  // NOT handled: spec/spec.md never states them as literal syntax (only as
  // a character-code value in prose, e.g. "&H20"), and basic/token.ml's
  // lexer has no support for them either -- so there is nothing in this
  // repo's source of truth to generate the pattern from yet.
  //
  // The trailing boundary is a lookahead, not \b, because the suffix is
  // optional: \d+\b would demand the character after an optional "%" be a
  // word character, which is backwards. See keyword-model.js's comment on
  // NOT_AFTER_ALNUM.
  return [
    {
      match: `${NOT_BEFORE_ALNUM}\\d+(?:\\.\\d+)?(?:[DdEe][+-]?\\d+)?${suffixOpt}${NOT_AFTER_ALNUM}`,
      name: 'constant.numeric.n88basic',
    },
    {
      match: `\\.\\d+(?:[DdEe][+-]?\\d+)?${suffixOpt}${NOT_AFTER_ALNUM}`,
      name: 'constant.numeric.n88basic',
    },
  ];
}

function buildGrammar(data) {
  const keywords = data.keywords;
  const suffixes = suffixChars(keywords);
  const suffixClass = suffixes.length ? `[${suffixes.map(escapeRegexChar).join('')}]` : '';

  const { patterns: keywordPatterns, conflicts } = buildKeywordPatterns(keywords);
  const commentPatterns = buildCommentPatterns(keywords);

  const grammar = {
    $schema: 'https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json',
    name: 'N88-BASIC(86)',
    scopeName: 'source.n88basic',
    fileTypes: ['bas'],
    generatedFrom: 'spec/keywords.json',
    generatedBy:
      'editor/vscode/tools/generate-grammar.js -- do not hand-edit this file; edit spec/keywords.json (or the hand-written parts of build-grammar.js noted in its comments) and re-run the generator',
    scopeLegend: {
      'keyword.control.n88basic / support.function.n88basic': 'in-scope statement / function -- the interpreter runs this',
      'invalid.deprecated.deferred.*.n88basic': 'part of the language, not implemented yet (spec/spec.md §3.2)',
      'invalid.deprecated.out.*.n88basic': 'parses but the interpreter will not run it (spec/spec.md §3.3)',
    },
    scopeConflicts: conflicts,
    patterns: [
      { include: '#comments' },
      { include: '#strings' },
      { include: '#line-numbers' },
      { include: '#keywords' },
      { include: '#numbers' },
      { include: '#operators' },
      { include: '#punctuation' },
      { include: '#identifiers' },
    ],
    repository: {
      comments: { patterns: commentPatterns },
      strings: {
        name: 'string.quoted.double.n88basic',
        begin: '"',
        end: '"|$',
        patterns: [],
      },
      'line-numbers': {
        match: '^\\s*(\\d+)\\b',
        captures: { '1': { name: 'constant.numeric.line-number.n88basic' } },
      },
      keywords: { patterns: keywordPatterns },
      numbers: { patterns: buildNumberPatterns(suffixes) },
      operators: { patterns: buildOperatorPatterns() },
      punctuation: { patterns: buildPunctuationPatterns() },
      identifiers: {
        // Trailing lookahead, not \b -- same reason as the number pattern:
        // the suffix is optional, so \b right after it would misfire.
        match: `${NOT_BEFORE_ALNUM}[A-Za-z][A-Za-z0-9]*${suffixClass}?${NOT_AFTER_ALNUM}`,
        name: 'variable.other.n88basic',
      },
    },
  };

  return { grammar, conflicts };
}

module.exports = { buildGrammar, scopeName };
