10 REM PROG.LABELS, ref-9801 printed p.30: a name that opens more than one
20 REM line is "Duplicate label". The page says the check runs when RUN
30 REM begins, BEFORE any line executes, so a listing carrying one does not
40 REM run at all -- which is why the PRINT below produces nothing.
50 REM The page also says this error names no line number, and it does not.
60 REM
70 REM This replaced a "first definition wins" reading, adopted because the
80 REM manual was thought silent. Section 13 runs onto p.30, and the earlier
90 REM reading stopped at the page break.
100 PRINT "this line must not run"
110 *TWICE
120 PRINT "nor this"
130 *TWICE
