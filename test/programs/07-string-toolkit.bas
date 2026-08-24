10 REM The string library, on one worked example.
20 A$="N88-BASIC(86)"
30 PRINT "source      : ";A$
40 PRINT "LEN         :";LEN(A$)
50 PRINT "LEFT$(,3)   : ";LEFT$(A$,3)
60 PRINT "RIGHT$(,4)  : ";RIGHT$(A$,4)
70 PRINT "MID$(,5,5)  : ";MID$(A$,5,5)
80 PRINT "MID$(,5)    : ";MID$(A$,5)
90 REM INSTR's optional start position comes FIRST, before the string.
100 PRINT "INSTR 8     :";INSTR(A$,"8")
110 PRINT "INSTR from 4:";INSTR(4,A$,"8")
120 PRINT "INSTR absent:";INSTR(A$,"z")
130 REM ASC and CHR$ are inverses over one character.
140 PRINT "ASC(N)      :";ASC(A$)
150 PRINT "CHR$ back   : ";CHR$(ASC(A$))
160 REM MID$ also assigns, in place, and can neither lengthen nor shorten.
170 B$="ABCDEFG"
180 MID$(B$,3,3)="xyz"
190 PRINT "MID$ assign : ";B$
200 REM STRING$ and SPACE$ build padding.
210 PRINT "STRING$     : ";STRING$(5,"-")
220 PRINT "SPACE$      : [";SPACE$(5);"]"
