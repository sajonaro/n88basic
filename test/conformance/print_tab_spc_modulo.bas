10 REM PRINT.TAB, PRINT.SPC, SCREEN.WIDTH: the TAB and SPC entries state one
20 REM rule in identical words (printed p.149 / PDF p.160 and printed p.146 /
30 REM PDF p.157) -- an argument at or above the column count WIDTH has set is
40 REM replaced by its remainder modulo that count. A remainder, not a clamp:
50 REM at WIDTH 40, TAB(45) means column 5, not column 40.
60 WIDTH 40
70 PRINT "AB";TAB(45);"C"
80 PRINT "AB";SPC(42);"D"
90 END
