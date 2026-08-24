10 REM SCREEN.COLOR (partial): COLOR sets the foreground/background used
20 REM by PSET/PRESET when no explicit colour is given.
30 REM GFX.POINT (partial, function form): POINT(x,y) reads back the
40 REM palette index of the pixel actually drawn there.
50 SCREEN 3
60 CLS
70 COLOR ,,,5
80 PSET (10,10)
90 PRINT POINT(10,10)
100 PRINT POINT(200,200)
110 END
