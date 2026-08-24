10 REM SCREEN.KEY-OFF: KEY[(<key number>)] ON|OFF|STOP permits, forbids or
20 REM suspends the function-key interrupts (printed p.87 / PDF p.98). The
30 REM key number is 1 to 10, and leaving it off -- parentheses and all --
40 REM means every function key.
50 REM There are no function-key interrupts in this interpreter, so each
60 REM form is recorded and does nothing. What this pins is that all six
70 REM forms parse, where until now only the bare KEY OFF did.
80 KEY ON
90 KEY OFF
100 KEY STOP
110 KEY(3) ON
120 KEY(10) OFF
130 KEY(1) STOP
140 PRINT "ACCEPTED"
150 END
