'use strict';

// The vscode-facing half of renumbering: n88basic.renumber and
// n88basic.insertNextLine. Split from src/renumber.js (which holds every
// pure function these two commands call) purely to keep each file under
// the 300-line limit -- `require('vscode')` is still deferred into each
// register* function so src/renumber.js's pure functions stay testable
// without it, matching every other feature module (see extension.js).

const { computeRenumberPlan, computeNextLineInsertion } = require('./renumber');

function registerRenumberCommand(context) {
  const vscode = require('vscode');
  const disposable = vscode.commands.registerCommand('n88basic.renumber', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'n88basic') {
      vscode.window.showWarningMessage('n88basic: open a .bas or .n88 file to renumber it.');
      return;
    }
    const startInput = await vscode.window.showInputBox({
      prompt: 'Renumber: starting line number',
      value: '10',
      validateInput: (v) => (/^\d+$/.test(v.trim()) ? null : 'Enter a non-negative integer.'),
    });
    if (startInput === undefined) return;
    const incInput = await vscode.window.showInputBox({
      prompt: 'Renumber: increment',
      value: '10',
      validateInput: (v) => (/^\d+$/.test(v.trim()) && Number(v) > 0 ? null : 'Enter a positive integer.'),
    });
    if (incInput === undefined) return;

    const document = editor.document;
    const plan = computeRenumberPlan(document.getText(), { start: Number(startInput), increment: Number(incInput) });
    if (!plan.ok) {
      vscode.window.showErrorMessage(`n88basic: renumber ${plan.reason}`);
      return;
    }

    const workspaceEdit = new vscode.WorkspaceEdit();
    for (const e of plan.edits) {
      workspaceEdit.replace(document.uri, new vscode.Range(e.lineIndex, e.start, e.lineIndex, e.end), e.newText);
    }
    const applied = await vscode.workspace.applyEdit(workspaceEdit);
    if (!applied) {
      vscode.window.showErrorMessage('n88basic: the renumbering edit could not be applied.');
      return;
    }
    vscode.window.showInformationMessage(
      `n88basic: renumbered ${plan.mapping.size} line(s), starting at ${startInput} step ${incInput}.`
    );
  });
  context.subscriptions.push(disposable);
}

function registerInsertNextLineCommand(context) {
  const vscode = require('vscode');
  const disposable = vscode.commands.registerCommand('n88basic.insertNextLine', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'n88basic') {
      vscode.window.showWarningMessage('n88basic: open a .bas or .n88 file to insert a numbered line.');
      return;
    }
    const document = editor.document;
    const cursorLine = editor.selection.active.line;
    const next = computeNextLineInsertion(document.getText(), cursorLine);
    if (next === null) {
      vscode.window.showErrorMessage('n88basic: no room for another line number here -- renumber first.');
      return;
    }
    const insertText = `${next} `;
    const lineEnd = document.lineAt(cursorLine).range.end;
    await editor.edit((builder) => builder.insert(lineEnd, '\n' + insertText));
    const newPos = new vscode.Position(cursorLine + 1, insertText.length);
    editor.selection = new vscode.Selection(newPos, newPos);
  });
  context.subscriptions.push(disposable);
}

module.exports = { registerRenumberCommand, registerInsertNextLineCommand };
