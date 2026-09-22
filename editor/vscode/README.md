# N88-BASIC(86) extension for Visual Studio Code

[![MIT License](https://img.shields.io/badge/license-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Version](https://badgen.net/vs-marketplace/v/n88basic.n88basic)](https://marketplace.visualstudio.com/items?itemName=n88basic.n88basic)

N88-BASIC(86) is the BASIC that shipped in ROM on NEC's PC-9801. This
extension lets you write it in VS Code with live error checking, and run it
with a real interpreter behind the Run button.

![A short N88-BASIC program](https://raw.githubusercontent.com/sajonaro/n88basic/main/docs/images/hello-bas.png)

## Features

- Syntax highlighting for `.bas` and `.n88` files
- Red squiggles as you type: syntax errors, and statements this interpreter
  does not implement, each named
- Hover over any keyword for its meaning and the manual page it comes from
- Completion for keywords, and snippets for `for`, `if`, `circle` and more
- Quick fixes on the lightbulb for some errors
- Automatic line numbering, and renumbering that fixes every `GOTO`, `GOSUB`
  and `THEN` that points at a moved line
- Run the saved file in a terminal; drawings land beside it as a PNG
- Execute the buffer or a selection into an output panel, saved or not
- An immediate session that keeps variables alive between statements, like
  the machine's `Ok` prompt
- An Overview panel that shows which extension and interpreter versions you
  have, and says so when they are out of step

## Supported

| Piece                | Version                                             |
| -------------------- | --------------------------------------------------- |
| Interpreter (`n88`)  | 0.1.3 or newer, the version the Overview panel checks |
| VS Code              | 1.75 or later                                       |
| Platform             | Linux x86_64 binary; the container image anywhere   |

### Feature Contributions

- **Language:** N88-BASIC (`.bas`, `.n88`), with grammar and snippets
- **View:** an N88-BASIC icon in the Activity Bar with an Overview panel
- **Keybinding:** `Ctrl+K Ctrl+N` (`Cmd+K Cmd+N` on macOS) inserts the next
  numbered line; it is the only one
- **Commands** in the Command Palette under **N88-BASIC**: Run; Execute
  Buffer; Execute Selection as a Program; Immediate Statement…; End Immediate
  Session; Renumber Lines; Insert Next Numbered Line; Open Overview
- **Activation:** on opening a `.bas` or `.n88` file, or the Overview panel

## Getting Started

**You need the interpreter too.** The extension is the editor; `n88` does the
running. Get `n88-linux-x86_64` from the
[releases page](https://github.com/sajonaro/n88basic/releases/latest), put it
on your `PATH`, and check it:

```
n88 --version      # 0.1.3 or newer
```

The extension checks this when a window opens and says so if the interpreter
is behind or missing. It never installs or upgrades anything. To install or
upgrade both halves at once, fetch
[install.sh](https://raw.githubusercontent.com/sajonaro/n88basic/main/install.sh)
and run `sh install.sh --extension`.

Then:

1. Save a file as `hello.bas`. `.bas` and `.n88` are treated identically.
2. Type:

   ```basic
   10 CLS 3
   20 CIRCLE (320, 100), 60, 5
   30 PRINT "hello"
   ```

3. Press F1, choose **N88-BASIC: Run**, or click the ▷ in the editor title.

A terminal named `n88basic` opens with `wrote hello.png` and `hello`, and a
notification offers **Open PNG**. The picture is `hello.png`, next to your
source file. Programs that draw leave an image beside themselves; programs
that do not, do not.

## Usage

**Two things happen to your file, and they are separate.** The checker runs
as you type and never runs your program; it gives squiggles, hovers and
completions. The interpreter runs only when you ask, and gives text output
plus a PNG if the program draws. A squiggle is not a failed run, and a clean
file is not a program that works.

### Running

| Command                            | Runs                                          | Output goes to                       |
| ---------------------------------- | --------------------------------------------- | ------------------------------------ |
| **Run**                            | the saved file                                | a terminal, plus `yourfile.png`      |
| **Execute Buffer**                 | the editor's text, saved or not               | the N88-BASIC panel, plus `n88.png`  |
| **Execute Selection as a Program** | the selected lines, or the buffer if none     | the N88-BASIC panel, plus `n88.png`  |

The PNG names differ on purpose: Run knows your filename; the other two are
fed text through a pipe and have none to use.

### An immediate session

**Immediate Statement…** starts a session and asks for one statement. Numbered
lines are stored; unnumbered ones run now. Variables survive from one
statement to the next. `RUN`, `LIST` and `NEW` work, and `RUN` clears every
variable first, which is the real machine's behaviour. **End Immediate
Session** closes it; the next statement opens a fresh one.

```
Immediate Statement…   A = 7            Ok
Immediate Statement…   PRINT A * 2      14        (A is still there)
Immediate Statement…   10 PRINT "hi"    (stored, no output)
Immediate Statement…   RUN              hi
Immediate Statement…   LIST             10 PRINT "hi"
```

### Writing

**Renumber Lines** renumbers the program and repoints every jump. **Insert
Next Numbered Line** (`Ctrl+K Ctrl+N`) adds the next line number for you.
Hover a keyword for its meaning and its page in the manual; type `for`, `if`
or `circle` and press Tab for a snippet.

### The Overview panel

Click the N88-BASIC icon in the Activity Bar. The panel shows the extension
and interpreter versions, whether they match, and buttons for Execute Buffer,
Immediate Statement, Run in a terminal and the full guide. If the interpreter
is missing or behind, this is where it says so, with a **How to upgrade**
button. It works with no file open.

## Configuration

| Setting                    | Description                                                                                                                                   |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `n88basic.interpreterPath` | Path to the `n88` interpreter. Empty means `n88` on your `PATH`. Set it for a specific build, or a wrapper around [the container](https://github.com/sajonaro/n88basic#using-it-as-a-container). |
| `n88basic.languageServer`  | Run diagnostics through the language server instead of in-process. Defaults to `false`; everything works without it. Needs a window reload.    |

**In a remote window** (WSL, SSH, a dev container, Codespaces) the extension
runs where your files are, so install `n88` on the remote, not on the machine
showing the window.

## Not Yet

- **No text screen.** `LOCATE`, `CONSOLE` and `CLS 1` are accepted but have no
  character grid to act on; output is a stream, not a screen.
- **No files, sound, or machine-level access.** `OPEN`, `BEEP`, `PEEK`, `POKE`
  and friends are out of scope. A program using one is told so by name.
- **One screen mode**, in the default eight-colour palette.
- **`INPUT` needs a terminal.** Use Run; the panel-based commands cannot type
  back.
- **Nothing interrupts a running program.** There is no `INKEY$`, `ON KEY` or
  `TIMER`; Ctrl-C is your terminal killing the process.

## Troubleshooting

**No Activity Bar icon?** VS Code can register a new entry as hidden on a
crowded bar, with no error. F1, **N88-BASIC: Open Overview** always works;
right-click the Activity Bar and tick N88-BASIC(86) to bring the icon back.

**Commands work, but no icon and no Overview?** An older copy is shadowing
this one. Uninstall by id on both sides of a remote setup, reinstall on the
remote, then quit VS Code entirely; a window reload does not rebuild cached
manifests.

**Run says a directory does not exist**, or a session says `n88` is missing,
in a WSL or SSH window: upgrade. Extensions before 0.1.4 loaded on the wrong
machine.

**A squiggle you disagree with?** Hover it; the source is named. If it says
`n88basic`, [open an issue](https://github.com/sajonaro/n88basic/issues) with
the line.

**From the command line:**

```sh
code --install-extension n88basic.n88basic          # install or upgrade
code --uninstall-extension n88basic.n88basic        # remove
code --list-extensions --show-versions | grep n88   # what you have, per host
```

Never rename or delete the extension's directory to disable it; VS Code reads
the `package.json` inside and re-registers the copy. Uninstall by id.

## Developing the Extension

- Clone the repository; the extension lives in `editor/vscode`:

  ```sh
  git clone https://github.com/sajonaro/n88basic.git
  cd n88basic/editor/vscode && npm install
  ```

- Open `editor/vscode` in VS Code and press F5 for an Extension Development
  Host. `make vsix` at the repository root packages it through Docker.
- [DEVELOPING.md](https://github.com/sajonaro/n88basic/blob/main/editor/vscode/DEVELOPING.md)
  covers the modules, how diagnostics work, and the interpreter versions each
  feature needs.

Bugs and requests: [github.com/sajonaro/n88basic/issues](https://github.com/sajonaro/n88basic/issues).
