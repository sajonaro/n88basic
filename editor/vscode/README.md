# N88-BASIC(86) for VS Code

Write and run programs for the BASIC that shipped in ROM on NEC's PC-9801 —
with live error checking, and a real interpreter behind the Run button.

> **You need the interpreter too.** The extension is the editor; `n88` does the
> running. Get it from
> [the releases page](https://github.com/sajonaro/n88basic/releases/latest)
> (`n88-linux-x86_64`), put it on your `PATH`, and check it:
>
> ```
> n88 --version      # 0.1.3 or newer
> ```
>
> Older than 0.1.3 and the three interactive commands below will not work.
>
> **The extension checks this for you** when a window opens, and says so if the
> interpreter is behind or missing. It never installs or upgrades anything —
> if your fixtures depend on exact output, nothing here will move it under you.
>
> To upgrade:
> `curl -fsSL https://raw.githubusercontent.com/sajonaro/n88basic/main/install.sh | sh`

---

## The N88-BASIC icon in the left-hand bar

Click it for an **Overview** panel showing which versions you have and whether
they match:

```
  Versions
  Extension     0.1.4
  Interpreter   0.1.4
  n88 (from PATH)

  The extension and the interpreter are in step.

  [ Execute Buffer            ]
  [ Immediate Statement…      ]
  [ Run in a terminal         ]
  [ Open the full guide       ]
```

If the interpreter is missing or behind, this is where it says so, with a
**How to upgrade** button. It works with no file open — that is the point of
putting it there.

## Two things happen to your file, and they are separate

```
  your .bas file
        │
        ├─►  checker  ──►  red squiggles, hovers, completions   (as you type,
        │                                                        no command)
        │
        └─►  n88      ──►  text output  +  a .png if it draws   (only when you
                                                                 run something)
```

The left path is always on and never runs your program. The right path only
happens when you ask. A squiggle is not a failed run, and a clean file is not a
program that works.

---

## Your first program, exactly

1. Save a file as **`hello.bas`** — `.bas` and `.n88` both work, and are
   treated identically. Renaming to get highlighting is never necessary.
2. Type:

   ```basic
   10 CLS 3
   20 CIRCLE (320, 100), 60, 5
   30 PRINT "hello"
   ```

3. Press **F1**, type **`N88-BASIC: Run`**, press Enter.
   (Or click the **▷** button in the editor's title bar.)

**What you get:** a terminal named `n88basic` opens with

```
wrote hello.png
hello
```

and a notification offering **Open PNG**.

**Where the picture went:** `hello.png`, **next to your source file**. Programs
that draw leave an image beside themselves; programs that do not, do not. If a
stray `.png` appears in your folder, this is why.

---

## Everything it can do

### Running

| Command | What it does | Output appears in |
| --- | --- | --- |
| **Run** | runs the saved file | a terminal, plus `yourfile.png` |
| **Execute Buffer** | runs the editor's text, saved or not | the **N88-BASIC** output panel, plus `n88.png` |
| **Execute Selection as a Program** | runs only the selected lines; with nothing selected, the whole buffer | same panel, plus `n88.png` |

> The two PNG names differ on purpose: **Run** knows your filename, the other
> two are fed text through a pipe and have none to use.

### An immediate session

This is the one nobody guesses, and the one worth learning. It keeps variables
alive between statements, like typing at the machine's `Ok` prompt.

```
   F1 → "Immediate Statement…"          F1 → "End Immediate Session"
            │                                        │
            ▼                                        ▼
   ┌──────────────────┐   type one statement   ┌───────────┐
   │  session starts  │ ─────────────────────► │  closed   │
   └──────────────────┘   ◄── repeat ───┐      └───────────┘
            │                           │
            └──► output panel ──────────┘
```

```
Immediate Statement…   A = 7            Ok
Immediate Statement…   PRINT A * 2       14        ← A is still there
Immediate Statement…   10 PRINT "hi"    (stored, no output)
Immediate Statement…   RUN              hi
Immediate Statement…   LIST             10 PRINT "hi"
```

Numbered lines are **stored**; unnumbered ones **run now**. `RUN`, `LIST` and
`NEW` work at this prompt. **`RUN` clears every variable first** — that is the
real machine's behaviour, not a quirk. **End Immediate Session** closes it; the
next statement opens a fresh one.

### Writing

| | |
| --- | --- |
| **Renumber Lines** | renumbers the program and fixes every `GOTO`/`GOSUB`/`THEN` that points at a moved line |
| **Insert Next Numbered Line** | `Ctrl+K Ctrl+N` (`Cmd+K Cmd+N` on macOS) — the only keybinding; adds the next line number for you |

### Always on, no command needed

- **Red squiggles as you type** — syntax errors, and statements this
  interpreter does not implement, each naming the feature by name
- **Hover** over any keyword for its meaning and the manual page it comes from
- **Completion** for keywords
- **Quick fixes** on the lightbulb for some errors
- **Snippets** — type `for`, `if`, `circle` and press Tab

---

## Settings

| Setting | Default | Use it when |
| --- | --- | --- |
| `n88basic.interpreterPath` | empty → `n88` on your `PATH` | your interpreter lives somewhere unusual, or you want to run [the container](https://github.com/sajonaro/n88basic#using-it-as-a-container) |
| `n88basic.languageServer` | `false` | you want diagnostics from the language server rather than in-process. Everything works without it; needs a window reload |

**In a remote window** — WSL, SSH, a dev container, Codespaces — the extension
runs where your files are, so **install `n88` on the remote**, not on the
machine showing the VS Code window.

---

## What it does not do yet

Being straight about this is part of the design.

- **No text screen.** `LOCATE`, `CONSOLE` and `CLS 1` are accepted but have no
  character grid to act on — output is a stream, not a screen.
- **No files, sound, or machine-level access.** `OPEN`, `BEEP`, `PEEK`/`POKE`
  and friends are out of scope. A program using one is told so by name.
- **One screen mode**, in the default eight-colour palette.
- **`INPUT` needs a terminal.** Use **Run**; the panel-based commands cannot
  type back.
- **Nothing can interrupt a running program.** `stdin` is sequential input
  consumed at each `INPUT`, not a channel the program watches — typing while a
  program runs does not stop it, and Ctrl-C is your terminal killing the
  process rather than the program noticing anything. There is no `INKEY$`, no
  `ON KEY` and no `TIMER`, so a program responds to nothing but its own
  control flow.

---

## If something looks wrong

**Installed an early build?** Uninstall it first. Anything from before v0.1.1
registered as `undefined_publisher.n88basic`, which VS Code treats as a
*different* extension from today's `n88basic.n88basic` — it will not upgrade
one to the other, both stay loaded, and the old one can win. Check with
`code --list-extensions | grep n88basic`.

**Run says a directory does not exist**, or an immediate session says `n88` is
missing, in a WSL/SSH window: you are on v0.1.3 or older, which loaded on the
wrong machine. Upgrade, or set `"remote.extensionKind": {"n88basic.n88basic": ["workspace"]}`.

**A squiggle you disagree with?** Hover it — the source is named. If it says
`n88basic`, please
[open an issue](https://github.com/sajonaro/n88basic/issues) with the line.

---

Changing the extension rather than using it? See
[DEVELOPING.md](DEVELOPING.md).
