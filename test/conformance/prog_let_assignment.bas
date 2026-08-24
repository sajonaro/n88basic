10 REM PROG.LET: LET is optional, and the bare assignment is the usual
20 REM form. Both are written here to show they mean the same thing.
30 LET I=1
40 I=(I+1)*3
50 PRINT I
60 LET A$="ab"
70 A$=A$+"cd"
80 PRINT A$
90 REM Between numeric types the value is converted to the precision of
100 REM the variable on the left rather than being refused.
110 LET N%=3.7
120 PRINT N%
130 D#=N%
140 PRINT D#
150 END
