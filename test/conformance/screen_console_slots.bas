10 REM SCREEN.CONSOLE: sets the text screen's mode. The first two slots
20 REM bound the scroll window -- the region a text clear acts on, so
30 REM CLS 1 and PRINT CHR$(12) work against it rather than the whole
40 REM screen. The third shows or hides the function-key strings along
50 REM the bottom line (shown at startup), and the fourth puts the text
60 REM screen into colour mode when 1, monochrome when 0 (monochrome at
70 REM startup). Both lines below are the manual's own examples, and the
80 REM second relies on empty slots written as bare commas.
90 CONSOLE 0,24,0,1
100 CONSOLE ,,1,0
110 REM Every slot is optional, so a bare CONSOLE is a legal statement.
120 CONSOLE
130 REM This interpreter has no text screen, so none of these changes
140 REM anything visible; that the four settings are recorded in the
150 REM manual's order is pinned by test_interp.ml's "CONSOLE slots are
160 REM each optional", which reads the display list directly.
170 PRINT "console forms accepted"
180 END
