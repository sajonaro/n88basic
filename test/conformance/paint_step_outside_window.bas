10 REM GFX.PAINT: a STEP start is resolved against the last point referenced
20 REM before the window test is applied, so a relative start that lands
30 REM off-screen raises the same error (printed p.117 / PDF p.128).
40 PSET (600,100)
50 PAINT STEP(100,0),1
60 PRINT "NOT REACHED"
70 END
