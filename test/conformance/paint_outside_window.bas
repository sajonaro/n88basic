10 REM GFX.PAINT: the manual's note under this entry states that PAINT works
20 REM only within the viewport, and that a start point outside the window
30 REM raises "Illegal function call" (printed p.117 / PDF p.128). This
40 REM interpreter used to do nothing at all in that case, which made it a
50 REM divergence rather than a gap -- the fifth found by reading a page.
60 PAINT (50,50),1
70 PRINT "INSIDE ACCEPTED"
80 PAINT (700,100),1
90 PRINT "NOT REACHED"
100 END
