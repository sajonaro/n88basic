10 REM STR.LEFT / STR.RIGHT / STR.LEN (implemented); STR.INSTR
20 REM (partial): a substring search with and without a start position,
30 REM and the not-found case.
40 A$ = "HELLO WORLD"
50 PRINT LEFT$(A$,5)
60 PRINT LEFT$(A$,99)
70 PRINT RIGHT$(A$,5)
80 PRINT RIGHT$(A$,0)
90 PRINT LEN(A$)
100 PRINT LEN("")
110 PRINT INSTR(A$,"WORLD")
120 PRINT INSTR(7,A$,"O")
130 PRINT INSTR(A$,"XYZ")
140 END
