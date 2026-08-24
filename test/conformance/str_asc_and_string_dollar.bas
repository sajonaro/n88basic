10 REM STR.ASC (partial): the character code of the first character.
20 REM STR.STRING (partial): STRING$(count,item) reads item's first
30 REM character when given a string, or a character code when given a
40 REM number.
50 PRINT ASC("A")
60 PRINT ASC("Zebra")
70 PRINT STRING$(5,"*")
80 PRINT STRING$(3,"HELLO")
90 PRINT STRING$(4,65)
100 END
