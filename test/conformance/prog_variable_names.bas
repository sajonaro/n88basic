10 REM PROG.VARIABLE-NAMES: a name may contain a reserved word (TOTAL,
20 REM LINEAR, FORM, ANDY, IFS below all contain TO, LINE, FOR, AND, IF)
30 REM without itself being one -- the fix for the bug where the lexer
40 REM matched a keyword as a prefix at every position (TOTAL as TO+TAL,
50 REM LINEAR as LINE+AR, FORM as FOR+M, ANDY as AND+Y, IFS as IF+S).
60 TOTAL=5:LINEAR=3:FORM=1:ANDY=2:IFS=7
70 PRINT TOTAL;LINEAR;FORM;ANDY;IFS
80 REM FOR/TO/THEN/ELSE are unaffected by names that merely contain them.
90 FOR I=1 TO 3:NEXT I
100 IF TOTAL>1 THEN PRINT "OK" ELSE PRINT "NO"
110 REM Periods are legal inside a name, and names are case-insensitive.
120 A.B=9:PRINT A.B
130 Total=Total+1:PRINT TOTAL
140 END
