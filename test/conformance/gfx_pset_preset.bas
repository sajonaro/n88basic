10 REM GFX.PSET / GFX.PRESET: PSET lights a dot in the foreground colour
20 REM by default, PRESET paints over in the background colour by
30 REM default; both take an absolute or STEP-relative point and an
40 REM optional explicit colour that overrides the default.
50 SCREEN 3
60 CLS
70 PSET (10,10)
80 PSET (20,10),2
90 PSET STEP(5,0)
100 PRESET (30,10)
110 PRESET (40,10),4
120 END
