10 REM CTRL.GOTO / CTRL.IF / CTRL.RETURN / CTRL.NEXT: the documented forms
20 REM that stood beside the ones already implemented -- the two-word GO TO,
30 REM the THEN-less IF ... GOTO with its shared ELSE, one NEXT closing
40 REM several loops, and RETURN to a chosen line rather than to the caller.
50 GO TO 70
60 PRINT "SKIPPED";
70 IF 1 GOTO 90
80 PRINT "SKIPPED";
90 IF 0 GOTO 120 ELSE PRINT "ELSE";
100 PRINT
110 REM One NEXT closes both loops, the manual's own "NEXT K, J" example.
120 FOR J=1 TO 2
130 FOR K=1 TO 2
140 PRINT J*10+K;
150 NEXT K, J
160 PRINT
170 GOSUB 210
180 PRINT "SKIPPED";
190 PRINT "SKIPPED"
200 END
210 PRINT "SUB";
220 RETURN 230
230 PRINT "RESUMED"
240 END
