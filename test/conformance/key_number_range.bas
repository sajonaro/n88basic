10 REM SCREEN.KEY-OFF: the manual gives the key number as 1 to 10 (printed
20 REM p.87 / PDF p.98). It does not say what a number outside that does, so
30 REM refusing it with Illegal function call is this interpreter's rule
40 REM rather than the manual's, and this case pins it as such.
50 KEY(10) ON
60 PRINT "10 ACCEPTED"
70 KEY(11) ON
80 PRINT "NOT REACHED"
90 END
