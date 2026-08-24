10 REM Points, and the eight colours a palette number selects.
20 REM Exercises: CONSOLE, [1] COLOR's four slots, PSET with and without an
30 REM explicit colour, and [2] COLOR = (palette, code).
40 REM Checks itself with POINT rather than trusting the picture.
50 CONSOLE 0,25,0,1
60 COLOR 7,0,0,7
70 REM Put every palette back on the colour of the same number.
80 FOR I=0 TO 7:COLOR=(I,I):NEXT
90 REM A dot in each colour, then read every one of them back.
100 FOR I=1 TO 7
110   PSET(20,I*8+4),I
120 NEXT I
130 PRINT "palette numbers read back:";
140 FOR I=1 TO 7:PRINT POINT(20,I*8+4);:NEXT I
150 PRINT
160 REM With no colour given, PSET uses COLOR's fourth slot.
170 COLOR 7,0,0,4
180 PSET(40,4)
190 PRINT "PSET with no colour uses COLOR's 4th slot:";POINT(40,4)
