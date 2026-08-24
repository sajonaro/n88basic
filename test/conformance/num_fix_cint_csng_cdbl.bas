10 REM NUM.FIX (implemented): truncates toward zero, unlike INT's floor.
20 REM NUM.CINT / NUM.CSNG / NUM.CDBL (implemented): explicit numeric
30 REM type conversion, with CINT rounding ties away from zero.
40 PRINT FIX(-1.5)
50 PRINT FIX(1.5)
60 PRINT CINT(2.5)
70 PRINT CINT(-2.5)
80 PRINT CSNG(1)
90 PRINT CDBL(1)
100 END
