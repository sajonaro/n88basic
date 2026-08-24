10 REM PRINT.USING, ref-9801 printed p.128. A 注意 sits directly under the
20 REM string-format characters: 日本語を含む文字列を編集することはできません
30 REM -- a string containing Japanese cannot be edited. 編集 is the same verb
40 REM the entry's own 機能 line uses for what PRINT USING does.
50 REM
60 REM This case used to pin the OPPOSITE: the fields counted bytes, so a
70 REM multi-byte character was cut in half and the fragment emitted, silently
80 REM and with no error, producing output that was not valid in any encoding.
90 REM The case existed to freeze that corruption, not to bless it. Alex ruled
100 REM on 2026-08-18 that the edit should be refused, so it now pins the
110 REM refusal instead.
120 REM
130 REM Refusing is the page's rule. WHICH error is ours: Illegal function
140 REM call, the same one this interpreter already raises for an out-of-range
150 REM SCREEN mode, WIDTH, KEY number or COLOR palette argument. The page
160 REM says only that the edit cannot be done and names no error.
170 REM
180 REM The same fields edit ASCII exactly as before -- the fields themselves
190 REM were never the problem.
200 PRINT USING "&  &";"abc"
210 PRINT USING "!";"abc"
220 PRINT USING "@";"abc"
230 REM Japanese as LITERAL text in the format string is copied, not edited,
240 REM so it is untouched by the prohibition.
250 PRINT USING "あ###";7
260 REM And now the refusal itself, which ends the program.
270 PRINT USING "&  &";"あいう"
280 PRINT "not reached"
