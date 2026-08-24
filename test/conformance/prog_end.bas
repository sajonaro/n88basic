10 REM PROG.END: ends execution and returns to command level. It may sit
20 REM wherever execution should stop, and a program may hold any number
30 REM of them -- the END on line 60 stops this program, so line 70's
40 REM PRINT and the second END on line 80 are never reached.
50 PRINT "before"
60 END
70 PRINT "after"
80 END
