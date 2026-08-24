'use strict';

// Quick fixes: one-click repairs attached to the diagnostics `src/diagnostics.js`
// already publishes. See docs/superpowers/specs/2026-08-16-n88basic-design.md §8
// and this task's brief.
//
// The diagnostics that get a fix here are exactly the ones with an
// UNAMBIGUOUS repair:
//
//  - `undefined-line` (a GOTO/GOSUB/THEN/ELSE/RESTORE/ON...GOTO/GOSUB target
//    naming a line that does not exist): offer to point it at the nearest
//    existing line number instead, one action per nearby candidate (the
//    closest defined line before the target and the closest one after it),
//    each spelling out exactly which number it would change to. Never picks
//    one silently.
//  - `line-order` (lines out of ascending order): offer to renumber the
//    whole program via `computeRenumberPlan` (src/renumber.js) -- reusing
//    that module rather than reimplementing renumbering here. If the plan
//    refuses (duplicate line, syntax error, or a pre-existing dangling
//    jump -- see renumber.js), NO action is offered: an action that fails
//    when invoked is worse than no action, per the brief.
//  - `duplicate-line` gets no action, deliberately. Given two physical lines
//    both numbered, say, 30, there is no unambiguous repair: renumbering one
//    of them requires *inventing* a target number for it, and any jump in
//    the program that names 30 was written to mean one specific physical
//    line -- which one is not recoverable from the text. A wrong guess here
//    would silently retarget a jump the author never asked to change, which
//    is exactly the "worse than no quick fix" failure mode the brief warns
//    against. So this diagnostic is deliberately left without an action.
//  - `syntax-error` gets no action: no case was found where the repair is
//    unambiguous (a syntax error can be fixed a dozen different ways, and
//    guessing one is exactly the silent-guess failure mode being avoided).
//
// Every action here is computed from a diagnostic object shaped exactly like
// the ones `n88basicCheck` (media/n88basic-check.js) produces -- {line,
// startCol, endCol, code, message} -- and, where line numbers elsewhere in
// the document are needed (only for `undefined-line`'s candidates), from
// `collectDefinitions` in `renumber-scan.js`, the *existing* scanner that
// `renumber.js` already relies on and that is itself checked against the
// real parser by `computeRenumberPlan`'s self-check. Nothing here re-scans
// the text with a new regex of its own: there is exactly one parser (the
// checker bundle) and one line-number scanner (renumber-scan.js), and this
// module is a consumer of both, not a third source of truth.
//
// Pure in, pure out: computeActionsForDiagnostic(diagnostic, documentText)
// takes a diagnostic-shaped plain object and the document text and returns
// plain {title, edits: [{line, startCol, endCol, newText}]} objects, no
// `require('vscode')` anywhere above registerCodeActionProvider. That is
// what tools/test-quickfix.js exercises without a VSCode host, exactly like
// every other module under src/.

const path = require('path');
const { collectDefinitions } = require('./renumber-scan');
const { computeRenumberPlan, inferIncrement } = require('./renumber');
const { n88basicCheck } = require(path.join(__dirname, '..', 'media', 'n88basic-check.js'));

function splitLines(documentText) {
  return documentText.split(/\r\n|\r|\n/);
}

// The closest existing defined line number below targetNumber and the
// closest one above it (there is never an exact match: this is only called
// for a target an `undefined-line` diagnostic already says doesn't exist).
// excludeLineIndex leaves out the number defined by the referencing line
// itself, if it has one: a jump target that happens to be undefined is
// usually well past the end of the program, so without this the "nearest
// line before it" candidate would frequently just be the jump's own line,
// i.e. "point this GOTO at itself" -- a mechanically honest answer but a
// useless, confusing one (a silent infinite loop). Ordered closest-first so
// the first action offered is the nearer jump.
function nearestLineCandidates(documentText, targetNumber, excludeLineIndex) {
  const existing = [...new Set(collectDefinitions(documentText)
    .filter((d) => d.lineIndex !== excludeLineIndex)
    .map((d) => d.number))];
  let below;
  let above;
  for (const n of existing) {
    if (n < targetNumber && (below === undefined || n > below)) below = n;
    if (n > targetNumber && (above === undefined || n < above)) above = n;
  }
  const candidates = [];
  if (below !== undefined) candidates.push({ number: below, direction: 'before' });
  if (above !== undefined) candidates.push({ number: above, direction: 'after' });
  candidates.sort((a, b) => Math.abs(a.number - targetNumber) - Math.abs(b.number - targetNumber));
  return candidates;
}

function undefinedLineActions(diagnostic, documentText) {
  const lines = splitLines(documentText);
  const lineText = lines[diagnostic.line];
  if (lineText === undefined) return [];
  const targetText = lineText.slice(diagnostic.startCol, diagnostic.endCol);
  if (!/^\d+$/.test(targetText)) return []; // defensive: the span should always be the digits themselves
  const targetNumber = Number(targetText);

  return nearestLineCandidates(documentText, targetNumber, diagnostic.line).map(({ number, direction }) => ({
    title: `Change ${targetText} to ${number} (nearest existing line ${direction} it)`,
    edits: [{ line: diagnostic.line, startCol: diagnostic.startCol, endCol: diagnostic.endCol, newText: String(number) }],
  }));
}

// Renumbers the whole program to fix ascending order, but only when
// computeRenumberPlan actually succeeds AND the result is verified, with the
// real checker, to have actually resolved every line-order diagnostic --
// see the module comment above for why an action must never be offered for
// a plan that would fail to deliver what its title promises. This mirrors
// the self-check computeRenumberPlan already runs internally for
// undefined-line (renumber.js): trust the parser's verdict on the result,
// not an assumption about what the rewrite does.
function lineOrderActions(diagnostic, documentText) {
  const increment = inferIncrement(documentText);
  const plan = computeRenumberPlan(documentText, { start: 10, increment });
  if (!plan.ok) return [];

  let postCheck;
  try {
    postCheck = n88basicCheck(plan.text);
  } catch (err) {
    return []; // can't verify the fix actually works -- don't offer it
  }
  if (postCheck.some((d) => d.code === 'line-order')) return [];

  return [
    {
      title: `Renumber the whole program (start at 10, step ${increment}) to fix line order`,
      edits: plan.edits.map((e) => ({ line: e.lineIndex, startCol: e.start, endCol: e.end, newText: e.newText })),
    },
  ];
}

// The single entry point: diagnostic (checker-shaped) + document text in,
// zero or more {title, edits} actions out.
function computeActionsForDiagnostic(diagnostic, documentText) {
  switch (diagnostic.code) {
    case 'undefined-line':
      return undefinedLineActions(diagnostic, documentText);
    case 'line-order':
      return lineOrderActions(diagnostic, documentText);
    // 'duplicate-line' and 'syntax-error' deliberately fall through to no
    // action -- see the module comment above.
    default:
      return [];
  }
}

function registerCodeActionProvider(context) {
  const vscode = require('vscode');

  const provider = {
    provideCodeActions(document, _range, codeActionContext) {
      const documentText = document.getText();
      const actions = [];
      for (const diagnostic of codeActionContext.diagnostics) {
        if (diagnostic.source !== 'n88basic') continue;
        const pureDiagnostic = {
          line: diagnostic.range.start.line,
          startCol: diagnostic.range.start.character,
          endCol: diagnostic.range.end.character,
          code: diagnostic.code,
          message: diagnostic.message,
        };
        for (const fix of computeActionsForDiagnostic(pureDiagnostic, documentText)) {
          const action = new vscode.CodeAction(fix.title, vscode.CodeActionKind.QuickFix);
          action.diagnostics = [diagnostic];
          const edit = new vscode.WorkspaceEdit();
          for (const e of fix.edits) {
            edit.replace(document.uri, new vscode.Range(e.line, e.startCol, e.line, e.endCol), e.newText);
          }
          action.edit = edit;
          actions.push(action);
        }
      }
      return actions;
    },
  };

  const disposable = vscode.languages.registerCodeActionsProvider({ language: 'n88basic' }, provider, {
    providedCodeActionKinds: [vscode.CodeActionKind.QuickFix],
  });
  context.subscriptions.push(disposable);
}

module.exports = {
  nearestLineCandidates,
  undefinedLineActions,
  lineOrderActions,
  computeActionsForDiagnostic,
  registerCodeActionProvider,
};
