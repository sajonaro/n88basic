'use strict';

// The text-scanning half of renumbering: splitting a physical line into code
// vs. string/comment, finding each line's own number (a "definition"), and
// finding every jump target a line names (a "reference") -- GOTO, GOSUB,
// THEN <n>, ELSE <n>, RESTORE <n>, and the comma-separated lists after
// ON...GOTO / ON...GOSUB. Split out of src/renumber.js, which holds the plan
// computation that consumes these, purely to stay under the 300-line limit.
// See that file for the design rationale (design §8, and why this is
// verified against the real parser rather than trusted on its own).

// A jump target only ever appears in code. Renumbering must never touch a
// digit run inside a string literal (`PRINT "GOTO 100"`) or a comment (`REM
// GOTO 100` / `' GOTO 100`), so every keyword/number search below runs over
// codeSegments(), never over the raw line text.
function codeSegments(lineText) {
  const segments = [];
  const n = lineText.length;
  let i = 0;
  let segStart = 0;
  const flush = (end) => {
    if (end > segStart) segments.push({ text: lineText.slice(segStart, end), offset: segStart });
  };
  while (i < n) {
    const ch = lineText[i];
    if (ch === '"') {
      flush(i);
      i++;
      while (i < n && lineText[i] !== '"') i++;
      if (i < n) i++; // skip closing quote
      segStart = i;
      continue;
    }
    if (ch === "'") {
      flush(i);
      return segments; // rest of the physical line is a comment
    }
    if ((ch === 'R' || ch === 'r') && lineText.slice(i, i + 3).toUpperCase() === 'REM') {
      const prevCh = lineText[i - 1];
      const nextCh = lineText[i + 3];
      const prevOk = i === 0 || !/[A-Za-z0-9_]/.test(prevCh);
      const nextOk = nextCh === undefined || !/[A-Za-z0-9_]/.test(nextCh);
      if (prevOk && nextOk) {
        flush(i);
        return segments;
      }
    }
    i++;
  }
  flush(i);
  return segments;
}

function splitLines(documentText) {
  return documentText.split(/\r\n|\r|\n/);
}

// ---- finding definitions (a line's own number) -----------------------------

const LEADING_NUMBER_RE = /^(\s*)(\d+)/;

function parseDefinition(lineText) {
  const m = LEADING_NUMBER_RE.exec(lineText);
  if (!m) return null;
  const start = m[1].length;
  return { start, end: start + m[2].length, number: Number(m[2]) };
}

function collectDefinitions(documentText) {
  const defs = [];
  splitLines(documentText).forEach((lineText, lineIndex) => {
    const d = parseDefinition(lineText);
    if (d) defs.push({ lineIndex, start: d.start, end: d.end, number: d.number });
  });
  return defs;
}

// ---- finding references -----------------------------------------------------

// GOTO and GOSUB take either a single target or a comma-separated list (the
// ON...GOTO/ON...GOSUB form) -- one pattern covers both, and incidentally
// covers ON ERROR GOTO <n> too, since that is spelled with the same GOTO
// keyword (basic/parser.ml). It does NOT cover RESUME <n>, which is a
// distinct keyword -- see tools/test-renumber.js and the task report for why
// that is a known, documented gap.
const GOTO_GOSUB_RE = /\b(GOTO|GOSUB)\b(\s*)((?:\d+\s*,\s*)*\d+)/gi;
// THEN/ELSE only name a line when a number immediately follows -- "THEN
// PRINT" is not a jump target, so this must not fire there.
const THEN_ELSE_RE = /\b(THEN|ELSE)\b(\s*)(\d+)\b/gi;
const RESTORE_RE = /\bRESTORE\b(\s*)(\d+)\b/gi;
// RESUME <line> names a jump target exactly as RESTORE does. It is easy to
// miss because it belongs to error handling rather than to control flow,
// and missing it is silent: the renumbered program keeps pointing RESUME at
// a line that no longer exists, and nothing complains. Bare RESUME and
// RESUME NEXT take no number and are left alone by the digit requirement.
const RESUME_RE = /\bRESUME\b(\s*)(\d+)\b/gi;

function collectGotoGosub(seg, refs) {
  GOTO_GOSUB_RE.lastIndex = 0;
  let m;
  while ((m = GOTO_GOSUB_RE.exec(seg.text))) {
    const listText = m[3];
    const listStart = m.index + m[0].length - listText.length;
    const numRe = /\d+/g;
    let nm;
    while ((nm = numRe.exec(listText))) {
      const localStart = listStart + nm.index;
      refs.push({
        start: seg.offset + localStart,
        end: seg.offset + localStart + nm[0].length,
        number: Number(nm[0]),
      });
    }
  }
}

function collectSingle(seg, refs, re, groupIndex) {
  re.lastIndex = 0;
  let m;
  while ((m = re.exec(seg.text))) {
    const numText = m[groupIndex];
    if (!numText) continue;
    const localStart = m.index + m[0].length - numText.length;
    refs.push({
      start: seg.offset + localStart,
      end: seg.offset + localStart + numText.length,
      number: Number(numText),
    });
  }
}

function findReferencesInLine(lineText) {
  const refs = [];
  for (const seg of codeSegments(lineText)) {
    collectGotoGosub(seg, refs);
    collectSingle(seg, refs, THEN_ELSE_RE, 3);
    collectSingle(seg, refs, RESTORE_RE, 2);
    collectSingle(seg, refs, RESUME_RE, 2);
  }
  refs.sort((a, b) => a.start - b.start);
  return refs;
}

function collectReferences(documentText) {
  const refs = [];
  splitLines(documentText).forEach((lineText, lineIndex) => {
    for (const r of findReferencesInLine(lineText)) refs.push({ lineIndex, ...r });
  });
  return refs;
}

module.exports = {
  codeSegments,
  splitLines,
  parseDefinition,
  collectDefinitions,
  findReferencesInLine,
  collectReferences,
};
