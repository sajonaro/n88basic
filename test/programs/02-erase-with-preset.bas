10 REM Erasing a dot. PRESET with no colour uses COLOR's SECOND slot, the
20 REM background, which is what makes it an eraser; PSET would need the
30 REM background colour spelled out.
40 COLOR 7,0,0,7
50 PSET(30,10)
60 PRINT "drawn:  ";POINT(30,10)
70 PRESET(30,10)
80 PRINT "erased: ";POINT(30,10)
90 REM PRESET can also take a colour, and then behaves like PSET.
100 PRESET(30,10),5
110 PRINT "PRESET with a colour paints it:";POINT(30,10)
120 REM A non-black background makes the difference visible.
130 COLOR 7,2,0,7
140 PSET(50,10)
150 PRESET(50,10)
160 PRINT "PRESET onto a red background:";POINT(50,10)
