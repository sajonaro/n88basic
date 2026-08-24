10 REM PRINT.BASIC, SCREEN.WIDTH: once WIDTH has set the column count the
20 REM writer breaks the line at the right-hand column, and a number that
30 REM will not fit in what is left of the line is written on a fresh line
40 REM rather than split across the break (printed p.125 / PDF p.136).
50 REM The manual states that rule of a numeric value and of nothing else,
60 REM so the long string on line 90 is NOT moved down -- it simply runs on
70 REM and breaks wherever the right-hand column falls.
80 WIDTH 40
90 PRINT "0123456789012345678901234567890123456";
100 PRINT 12345
110 PRINT "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNO"
120 END
