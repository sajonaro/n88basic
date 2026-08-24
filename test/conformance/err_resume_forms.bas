10 REM ERR.RESUME's three forms: RESUME <line> skips ahead to a given
20 REM line (past the rest of the handler), and a bare RESUME retries
30 REM the exact statement that failed.
40 D = 0
50 ON ERROR GOTO 200
60 A = 1/D
70 PRINT "RESULT"; A
80 GOTO 300
200 D = 1
210 RESUME
300 ON ERROR GOTO 400
310 B = 1/0
320 PRINT "SKIPPED"
330 END
400 PRINT "HANDLED"
410 RESUME 500
420 PRINT "NEVER"
500 PRINT "TARGET"
510 END
