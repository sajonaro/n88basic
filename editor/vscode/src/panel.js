'use strict';

// The Activity Bar panel: what the extension is, what version each half is,
// and the few actions worth one click.
//
// DELIBERATELY NOT THE README. VSCode already shows the full readme and the
// version if you click the extension in the Extensions sidebar, so nothing
// here is information the editor lacks -- this is about where someone looks.
// Re-rendering 173 lines of guide into a 250px strip would be worse than the
// page that already exists; the panel carries the two version lines, a status
// sentence, the primary actions, and a link out.
//
// THE VERSION PAIR IS THE POINT. An interpreter a release behind produces
// failures that read as a broken extension, and until now the only way to
// discover that was a notification you may have dismissed. This is the screen
// you can open deliberately and look at.

const { verdict, MINIMUM } = require('./version-check');

const RELEASES = 'https://github.com/sajonaro/n88basic/releases/latest';
const GUIDE = 'https://github.com/sajonaro/n88basic/blob/main/editor/vscode/README.md';

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Pure, so it can be checked under plain node. `interpreter` is the string
// `n88 --version` printed, or null when it could not be run.
function renderHtml({ extensionVersion, interpreter, interpreterPath }) {
  const v = verdict(extensionVersion, interpreter);
  const shown = interpreter === null || interpreter === undefined
    ? 'not found'
    : escapeHtml(String(interpreter).trim());
  // No verdict means matched, or the interpreter is ahead: both are fine.
  const cls = !v ? 'ok' : v.level === 'error' ? 'bad' : v.level === 'warning' ? 'warn' : 'note';
  const status = !v
    ? 'The extension and the interpreter are in step.'
    : escapeHtml(v.message.replace(/^n88basic: /, ''));

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline';">
<style>
 body { font: 13px var(--vscode-font-family); color: var(--vscode-foreground);
        padding: 12px 14px; }
 h2 { font-size: 13px; margin: 18px 0 6px; text-transform: uppercase;
      letter-spacing: .06em; opacity: .7; font-weight: 600; }
 h2:first-child { margin-top: 0; }
 dl { display: grid; grid-template-columns: auto 1fr; gap: 4px 12px; margin: 0; }
 dt { opacity: .75; }
 dd { margin: 0; font-variant-numeric: tabular-nums; }
 .status { margin: 10px 0 0; padding: 8px 10px; border-radius: 4px; line-height: 1.45;
           border-left: 3px solid; }
 .ok   { border-color: var(--vscode-charts-green);  background: var(--vscode-textBlockQuote-background); }
 .note { border-color: var(--vscode-charts-blue);   background: var(--vscode-textBlockQuote-background); }
 .warn { border-color: var(--vscode-charts-yellow); background: var(--vscode-inputValidation-warningBackground); }
 .bad  { border-color: var(--vscode-charts-red);    background: var(--vscode-inputValidation-errorBackground); }
 button { display: block; width: 100%; text-align: left; margin: 4px 0; padding: 6px 10px;
          border: none; border-radius: 3px; cursor: pointer; font: inherit;
          color: var(--vscode-button-foreground); background: var(--vscode-button-background); }
 button:hover { background: var(--vscode-button-hoverBackground); }
 button.secondary { color: var(--vscode-button-secondaryForeground);
                    background: var(--vscode-button-secondaryBackground); }
 .path { opacity: .6; font-size: 11px; word-break: break-all; margin-top: 2px; }
</style></head><body>
 <h2>Versions</h2>
 <dl>
  <dt>Extension</dt><dd>${escapeHtml(extensionVersion)}</dd>
  <dt>Interpreter</dt><dd>${shown}</dd>
 </dl>
 <div class="path">${escapeHtml(interpreterPath || 'n88')}${interpreterPath ? '' : ' (from PATH)'}</div>
 <p class="status ${cls}">${status}</p>
 ${v ? `<button id="upgrade">How to upgrade</button>` : ''}

 <h2>Run something</h2>
 <button data-cmd="n88basic.executeBuffer">Execute Buffer</button>
 <button data-cmd="n88basic.immediateStatement">Immediate Statement…</button>
 <button data-cmd="n88basic.run" class="secondary">Run in a terminal</button>

 <h2>Help</h2>
 <button id="guide" class="secondary">Open the full guide</button>

<script>
 const api = acquireVsCodeApi();
 for (const b of document.querySelectorAll('button[data-cmd]'))
   b.addEventListener('click', () => api.postMessage({ command: b.dataset.cmd }));
 const up = document.getElementById('upgrade');
 if (up) up.addEventListener('click', () => api.postMessage({ open: '${RELEASES}' }));
 document.getElementById('guide')
   .addEventListener('click', () => api.postMessage({ open: '${GUIDE}' }));
</script>
</body></html>`;
}

function registerPanel(context) {
  const vscode = require('vscode');
  const { execFile } = require('child_process');
  const { interpreterCommand } = require('./session');

  const provider = {
    resolveWebviewView(view) {
      view.webview.options = { enableScripts: true };
      const cfg = vscode.workspace.getConfiguration('n88basic');
      const cmd = interpreterCommand(cfg);
      const mine = (context.extension && context.extension.packageJSON
        && context.extension.packageJSON.version) || '0.0.0';

      const paint = (reported) => {
        view.webview.html = renderHtml({
          extensionVersion: mine,
          interpreter: reported,
          interpreterPath: cfg.get('interpreterPath') || '',
        });
      };
      paint(null); // something to look at before the spawn returns
      execFile(cmd, ['--version'], { timeout: 5000 }, (err, stdout) =>
        paint(err ? null : String(stdout)));

      view.webview.onDidReceiveMessage((m) => {
        if (m.command) vscode.commands.executeCommand(m.command);
        else if (m.open) vscode.env.openExternal(vscode.Uri.parse(m.open));
      });
    },
  };

  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('n88basic.home', provider),

    // A Command Palette route to the panel, because the Activity Bar entry can
    // be INVISIBLE through no fault of the manifest. VSCode stores per-user
    // workbench state in workbench.activity.pinnedViewlets2, and on a crowded
    // bar a newly contributed container can land there as
    // {"pinned": true, "visible": false} -- registered, ordered 22nd, and
    // never drawn. Observed on a real install: the view itself was not hidden,
    // everything contributed was correct, and there was no icon and no error.
    //
    // It fails for experienced users with many extensions, which is not the
    // population anyone would guess, and "click the icon" is a dead end with
    // nothing to search for. VSCode generates <viewId>.focus for a contributed
    // view; this wraps it under a name a person can find by typing "n88".
    vscode.commands.registerCommand('n88basic.openOverview', () =>
      vscode.commands.executeCommand('n88basic.home.focus'))
  );
}

module.exports = { renderHtml, registerPanel, MINIMUM };
