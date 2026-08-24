10 REM ERR.ON-ERROR-GOTO / ERR.RESUME / ERR.FN / ERR.ERL: trapping an
20 REM ordinary runtime error, reading ERR (the error number) and ERL
30 REM (the line it happened on) inside the handler, and RESUME NEXT
40 REM continuing with the statement after the one that failed.
50 ON ERROR GOTO 200
60 A = 1/0
70 PRINT "AFTER"; A
80 END
200 PRINT "TRAPPED, ERR="; ERR; "ERL="; ERL
210 RESUME NEXT
