10 REM CTRL.FOR / CTRL.NEXT: counting up, counting down with STEP, a
20 REM fractional STEP, a loop that never enters because the initial
30 REM test already fails, and nested loops with NEXT-by-name.
40 FOR I=1 TO 3
50 PRINT I;
60 NEXT I
70 PRINT
80 FOR I=3 TO 1 STEP -1
90 PRINT I;
100 NEXT I
110 PRINT
120 FOR V=1 TO 2 STEP .5
130 PRINT V;
140 NEXT V
150 PRINT
160 FOR I=1 TO 0
170 PRINT "NEVER"
180 NEXT I
190 FOR I=1 TO 2
200 FOR J=1 TO 2
210 PRINT I*10+J;
220 NEXT J
230 NEXT I
240 PRINT
250 END
