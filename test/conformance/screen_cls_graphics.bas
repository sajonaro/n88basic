10 REM SCREEN.CLS: 2 clears the graphics screen and 3 clears both
20 REM screens, so the box drawn on line 60 does not survive line 70 and
30 REM the one on line 80 does not survive line 90. Only the box drawn
40 REM after the last clear is left.
50 SCREEN 3
60 LINE (20,20)-(140,120),7,BF
70 CLS 2
80 LINE (180,20)-(300,120),4,BF
90 CLS 3
100 REM Clearing the graphics screen paints it in the background colour
110 REM [1] COLOR set, and leaves the last point referenced at the top
120 REM left, which is where this segment starts from.
130 COLOR ,1
140 CLS 2
150 LINE -(200,150),6
160 END
