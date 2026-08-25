10 REM NUM.TYPES / NUM.DISPLAY: the type rules that decide how a large value
20 REM prints apply to a CONSTANT's notation. A VARIABLE with no suffix and no
30 REM DEFxxx in effect is single precision (printed p.14 section 6.2), so the
40 REM same value reaches PRINT as a different type depending on how it got
50 REM there. num_literal_typing.bas pins the constant path; this pins the one
60 REM a real program actually takes, which no case reached before.
70 REM
80 REM An eight-digit CONSTANT is double, so it shows in full.
90 PRINT "constant  :";10000000
100 REM Assigned to a plain variable it is single, whose display budget is
110 REM six digits, so the identical value shows in exponent form.
120 A = 10000000
130 PRINT "variable  :";A
140 REM Reached by accumulation -- how a program totalling a column gets
150 REM there -- it is single for the same reason.
160 T = 0
170 FOR I = 1 TO 10 : T = T + 1000000 : NEXT I
180 PRINT "aggregate :";T
190 REM Spelling the type restores the full form, by suffix...
200 B# = 10000000
210 PRINT "suffixed  :";B#
220 REM ...or by declaring the letter's type for the whole program.
230 DEFDBL S
240 S = 0
250 FOR I = 1 TO 10 : S = S + 1000000 : NEXT I
260 PRINT "DEFDBL    :";S
