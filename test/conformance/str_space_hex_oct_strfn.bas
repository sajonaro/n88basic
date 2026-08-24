10 REM STR.SPACE / PRINT.SPC (implemented): SPACE$(n) builds a string of
20 REM n spaces; SPC(n) inserts n literal spaces into a PRINT list.
30 REM STR.HEX / STR.OCT / STR.STR-FN (implemented): base conversion and
40 REM STR$'s leading sign character.
50 PRINT "|"; SPACE$(3); "|"
60 PRINT "A"; SPC(3); "B"
70 PRINT HEX$(255)
80 PRINT HEX$(-1)
90 PRINT OCT$(8)
100 PRINT STR$(5)
110 PRINT STR$(-5)
120 PRINT STR$(0)
130 END
