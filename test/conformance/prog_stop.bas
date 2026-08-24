10 REM PROG.STOP: suspends execution, so line 60 does not run, and names
20 REM the line it stopped at on the way out -- which is what tells it
30 REM apart from END, since there is no CONT here to resume with.
40 PRINT "before"
50 STOP
60 PRINT "after"
70 END
