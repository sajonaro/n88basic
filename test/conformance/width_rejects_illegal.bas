10 REM SCREEN.WIDTH: the manual allows 40 or 80 columns and 20 or 25 rows and
20 REM nothing else (printed p.158-159 / PDF p.169-170). It does not say what
30 REM an illegal value does, so refusing it with Illegal function call is
40 REM this interpreter's rule rather than the manual's, and this case pins
50 REM it as such.
60 WIDTH 40
70 PRINT "40 ACCEPTED"
80 WIDTH 132
90 PRINT "NOT REACHED"
100 END
