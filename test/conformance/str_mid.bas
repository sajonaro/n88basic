10 REM STR.MID (partial): the function form (2- and 3-argument) and the
20 REM statement form, which replaces characters in place without ever
30 REM growing the field.
40 A$ = "HELLO WORLD"
50 PRINT MID$(A$,7)
60 PRINT MID$(A$,7,3)
70 PRINT MID$(A$,7,99)
80 B$ = "ABCDE"
90 MID$(B$,2,2) = "XY"
100 PRINT B$
110 MID$(B$,2) = "Z"
120 PRINT B$
130 END
