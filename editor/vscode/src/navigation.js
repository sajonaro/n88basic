'use strict';

// Go-to-definition and find-references over BASIC line numbers.
//
// In a language whose only names are line numbers, "definition" means the line
// that begins with that number and "reference" means every jump that names it.
// Both sets are already computed by renumber-scan.js, which excludes string
// literals and comments before any keyword pattern sees the text -- so
// PRINT "GOTO 100" is not a reference here either. Reusing it keeps one
// definition of what a jump is; a second scanner would be free to disagree
// with renumbering about which text is a jump, and the two would drift.
//
// No `require('vscode')` at load time: everything below is a plain function
// over document text, and only registerNavigation needs the editor.

const scan = require('./renumber-scan');

// The token under the cursor, when the cursor is on a line number -- either a
// line's own number or a jump target. Returns null anywhere else, so the
// providers stay silent rather than guessing at, say, a numeric literal in an
// expression.
function lineNumberAt(documentText, lineIndex, column) {
  const lines = scan.splitLines(documentText);
  const lineText = lines[lineIndex];
  if (lineText === undefined) return null;

  const def = scan.parseDefinition(lineText);
  if (def && column >= def.start && column <= def.end) {
    return { kind: 'definition', number: def.number, start: def.start, end: def.end };
  }
  for (const ref of scan.findReferencesInLine(lineText)) {
    if (column >= ref.start && column <= ref.end) {
      return { kind: 'reference', number: ref.number, start: ref.start, end: ref.end };
    }
  }
  return null;
}

// Where a line number is defined. A well-formed program has one such line;
// a malformed one may have several (the checker reports that separately as
// duplicate-line), so every match is returned rather than the first —
// silently picking one would hide the duplicate from the person navigating.
function definitionsOf(documentText, number) {
  return scan
    .collectDefinitions(documentText)
    .filter((d) => d.number === number)
    .map((d) => ({ lineIndex: d.lineIndex, start: d.start, end: d.end }));
}

function referencesTo(documentText, number) {
  return scan
    .collectReferences(documentText)
    .filter((r) => r.number === number)
    .map((r) => ({ lineIndex: r.lineIndex, start: r.start, end: r.end }));
}

// What go-to-definition should jump to from wherever the cursor is. On a jump
// target it is the line named; on a line's own number it is nothing, because
// the definition is already where the cursor sits -- jumping to the current
// position pretends to have done something.
function definitionTargets(documentText, lineIndex, column) {
  const token = lineNumberAt(documentText, lineIndex, column);
  if (!token || token.kind !== 'reference') return [];
  return definitionsOf(documentText, token.number);
}

// Every place a line number is named. Works from a jump target or from the
// line's own number, since both mean the same line. includeDeclaration follows
// the editor's convention of offering the definition alongside its uses.
function referenceTargets(documentText, lineIndex, column, options) {
  const token = lineNumberAt(documentText, lineIndex, column);
  if (!token) return [];
  const refs = referencesTo(documentText, token.number);
  if (options && options.includeDeclaration) {
    return definitionsOf(documentText, token.number).concat(refs);
  }
  return refs;
}

function registerNavigation(context) {
  const vscode = require('vscode');
  const selector = 'n88basic';

  const toLocation = (uri, hit) =>
    new vscode.Location(
      uri,
      new vscode.Range(
        new vscode.Position(hit.lineIndex, hit.start),
        new vscode.Position(hit.lineIndex, hit.end)
      )
    );

  context.subscriptions.push(
    vscode.languages.registerDefinitionProvider(selector, {
      provideDefinition(document, position) {
        return definitionTargets(document.getText(), position.line, position.character).map((h) =>
          toLocation(document.uri, h)
        );
      },
    }),
    vscode.languages.registerReferenceProvider(selector, {
      provideReferences(document, position, context_) {
        return referenceTargets(document.getText(), position.line, position.character, {
          includeDeclaration: context_ && context_.includeDeclaration,
        }).map((h) => toLocation(document.uri, h));
      },
    })
  );
}

module.exports = {
  lineNumberAt,
  definitionsOf,
  referencesTo,
  definitionTargets,
  referenceTargets,
  registerNavigation,
};
