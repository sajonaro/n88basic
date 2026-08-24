'use strict';

// Renumbering and automatic line numbering (design §8: "line_ref.target_span
// exists precisely so a jump target can be rewritten by surgical text edit,
// leaving comments and spacing untouched").
//
// This is done in JavaScript over the document text rather than in OCaml
// (see docs/superpowers/specs/2026-08-16-n88basic-design.md §8 and this
// task's brief) so it never depends on the OCaml toolchain. That means it
// duplicates knowledge the real parser already has -- which forms/scopes
// count as a "line number" (src/renumber-scan.js does the actual text
// scanning) -- so every computed rewrite is verified against the real
// parser (media/n88basic-check.js, the committed js_of_ocaml bundle) before
// it is ever offered to the user: see computeRenumberPlan below. Everything
// here is pure (no `require('vscode')`), so it loads and runs under plain
// node -- see tools/test-renumber.js. The two vscode commands that call
// this live in src/renumber-commands.js.

const path = require('path');
const { n88basicCheck } = require(path.join(__dirname, '..', 'media', 'n88basic-check.js'));
const { splitLines, collectDefinitions, collectReferences } = require('./renumber-scan');

// ---- increment inference ---------------------------------------------------

// The most common positive gap between consecutive defined line numbers,
// ties broken toward the smaller gap; 10 (N88-BASIC's own convention) when
// there are fewer than two lines to compare.
function inferIncrement(documentText) {
  const numbers = collectDefinitions(documentText)
    .map((d) => d.number)
    .sort((a, b) => a - b);
  const counts = new Map();
  for (let i = 1; i < numbers.length; i++) {
    const diff = numbers[i] - numbers[i - 1];
    if (diff > 0) counts.set(diff, (counts.get(diff) || 0) + 1);
  }
  let best = null;
  let bestCount = 0;
  for (const [diff, count] of counts) {
    if (count > bestCount || (count === bestCount && (best === null || diff < best))) {
      best = diff;
      bestCount = count;
    }
  }
  return best || 10;
}

// ---- renumber plan ----------------------------------------------------------

// Assigns new numbers in the order lines physically appear in the document
// (the order `definitions` already comes in from collectDefinitions), NOT
// sorted by old value. That distinction only matters for a program whose
// physical order and value order disagree (a `line-order` diagnostic): a
// mapping built from value-sorted numbers is order-preserving in the old
// value, so it can never fix such a mismatch -- whichever old number was
// smallest gets the smallest new number regardless of where it physically
// sits, so the same relative (broken) arrangement survives renumbering.
// Building the mapping from first physical occurrence instead makes the new
// numbers strictly ascending in document order by construction, which is
// what "renumber" means for a BASIC listing and is what the quick fix for
// `line-order` (src/quickfix.js) depends on. For a program that is already
// in ascending order (every existing fixture), first-physical-occurrence
// order and value order are the same sequence, so this is not a behaviour
// change for the common case.
function buildMapping(definitions, startNumber, increment) {
  const uniqueNumbers = [];
  const seen = new Set();
  for (const d of definitions) {
    if (!seen.has(d.number)) {
      seen.add(d.number);
      uniqueNumbers.push(d.number);
    }
  }
  const mapping = new Map();
  uniqueNumbers.forEach((oldNumber, i) => mapping.set(oldNumber, startNumber + i * increment));
  return mapping;
}

function applyEditsToText(documentText, edits) {
  const eol = documentText.includes('\r\n') ? '\r\n' : '\n';
  const lines = splitLines(documentText);
  const byLine = new Map();
  for (const e of edits) {
    if (!byLine.has(e.lineIndex)) byLine.set(e.lineIndex, []);
    byLine.get(e.lineIndex).push(e);
  }
  for (const [lineIndex, lineEdits] of byLine) {
    lineEdits.sort((a, b) => b.start - a.start); // right-to-left: earlier offsets stay valid
    let text = lines[lineIndex];
    for (const e of lineEdits) text = text.slice(0, e.start) + e.newText + text.slice(e.end);
    lines[lineIndex] = text;
  }
  return lines.join(eol);
}

const BLOCKING_CODES = {
  'syntax-error': 'a syntax error',
  'duplicate-line': 'a duplicate line number',
  'undefined-line': 'a jump to a line that does not exist',
};

function messageCounts(diags) {
  const counts = new Map();
  for (const d of diags) counts.set(d.message, (counts.get(d.message) || 0) + 1);
  return counts;
}

// The pure heart of the feature: text in, plan out. Never touches the
// document; the caller applies plan.edits (or doesn't, on refusal).
//
// Refuses -- rather than producing a possibly-wrong renumbering -- when:
//  - the real parser (n88basicCheck) reports a syntax error, a duplicate
//    line number, or a jump to a line that doesn't exist yet, on the
//    ORIGINAL text (task requirement (c));
//  - this module's own reference scan (renumber-scan.js) finds a jump it
//    doesn't have a mapping for (belt-and-braces: catches forms
//    n88basicCheck doesn't validate, e.g. ON ERROR GOTO -- see that file's
//    GOTO_GOSUB_RE comment);
//  - after computing the rewrite, re-running n88basicCheck on the RESULT
//    shows a new undefined-line diagnostic the original didn't have --
//    i.e. this module's own regex-based rewrite missed a reference form
//    and broke a jump. This is the self-check the task calls for.
function computeRenumberPlan(documentText, options) {
  const startNumber = options && Number.isFinite(options.start) ? options.start : 10;
  const increment = options && Number.isFinite(options.increment) ? options.increment : 10;
  if (!Number.isInteger(startNumber) || startNumber < 0) {
    return { ok: false, reason: 'Starting line number must be a non-negative integer.' };
  }
  if (!Number.isInteger(increment) || increment <= 0) {
    return { ok: false, reason: 'Increment must be a positive integer.' };
  }

  let preCheck;
  try {
    preCheck = n88basicCheck(documentText);
  } catch (err) {
    return { ok: false, reason: `could not check the program before renumbering (${err.message}).` };
  }
  const blocking = preCheck.filter((d) => BLOCKING_CODES[d.code]);
  if (blocking.length > 0) {
    const codes = [...new Set(blocking.map((d) => BLOCKING_CODES[d.code]))];
    return {
      ok: false,
      reason: `refused: the program has ${codes.join(' and ')} (${blocking[0].message}). Fix it, then renumber.`,
    };
  }

  const definitions = collectDefinitions(documentText);
  if (definitions.length === 0) {
    return { ok: false, reason: 'no numbered lines found to renumber.' };
  }

  const mapping = buildMapping(definitions, startNumber, increment);
  const references = collectReferences(documentText);
  for (const ref of references) {
    if (!mapping.has(ref.number)) {
      return { ok: false, reason: `refused: line ${ref.number} is referenced but does not exist.` };
    }
  }

  const edits = [];
  for (const d of definitions) edits.push({ lineIndex: d.lineIndex, start: d.start, end: d.end, newText: String(mapping.get(d.number)) });
  for (const r of references) edits.push({ lineIndex: r.lineIndex, start: r.start, end: r.end, newText: String(mapping.get(r.number)) });

  const newText = applyEditsToText(documentText, edits);

  let postCheck;
  try {
    postCheck = n88basicCheck(newText);
  } catch (err) {
    return { ok: false, reason: `aborted: the result failed to check (${err.message}). No changes were made.` };
  }
  const before = messageCounts(preCheck.filter((d) => d.code === 'undefined-line'));
  const after = postCheck.filter((d) => d.code === 'undefined-line');
  const afterCounts = messageCounts(after);
  let newlyBroken = false;
  for (const [msg, count] of afterCounts) {
    if (count > (before.get(msg) || 0)) {
      newlyBroken = true;
      break;
    }
  }
  if (newlyBroken) {
    return {
      ok: false,
      reason:
        'aborted: the renumbered program has a broken jump the original did not ' +
        `(${after.map((d) => d.message).join('; ')}). No changes were made.`,
    };
  }

  return { ok: true, text: newText, mapping, edits };
}

// ---- automatic line numbering ----------------------------------------------

// Where the next line number should go, continuing the sequence from
// whatever is defined at or before cursorLineIndex, using the file's own
// increment. Returns null when there is no integer room left between that
// line and the next defined one (rather than creating a duplicate).
function computeNextLineInsertion(documentText, cursorLineIndex) {
  const defs = collectDefinitions(documentText);
  const increment = inferIncrement(documentText);
  let prev = null;
  let after = null;
  for (const d of defs) {
    if (d.lineIndex <= cursorLineIndex) prev = d.number;
    else if (after === null) after = d.number;
  }
  if (prev === null) return increment;
  let next = prev + increment;
  if (after !== null && next >= after) {
    const mid = prev + Math.floor((after - prev) / 2);
    if (mid > prev) next = mid;
    else return null;
  }
  return next;
}

module.exports = {
  inferIncrement,
  buildMapping,
  applyEditsToText,
  computeRenumberPlan,
  computeNextLineInsertion,
};
