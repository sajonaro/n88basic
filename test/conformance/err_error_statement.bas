10 REM ERR.ERROR (partial): ERROR <n> simulates error number <n>. A
20 REM defined code shows the manual's own message; a code the manual
30 REM assigns no message of its own shows "Unprintable error" while ERR
40 REM still reports the exact number given.
50 ON ERROR GOTO 100
60 ERROR 40
70 END
100 PRINT "ERR="; ERR
110 RESUME NEXT
