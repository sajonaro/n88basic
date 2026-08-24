10 REM GFX.LINE (partial): draws the segment joining two points. An
20 REM omitted first point starts from the last point referenced, and
30 REM after the statement runs that last point is the second point --
40 REM so line 80 starts where line 70 finished.
50 SCREEN 3
60 CLS
70 LINE (10,10)-(100,10),7
80 LINE -(100,90),7
90 REM An omitted palette number draws in the foreground colour COLOR set.
100 COLOR ,,,2
110 LINE (10,90)-(10,10)
120 REM GFX.LINE.BF (partial): the two points are opposite corners of a
130 REM rectangle, and its interior is filled. With no second palette
140 REM number the fill takes the colour the rectangle was drawn in.
150 LINE (200,20)-(320,120),4,BF
160 REM ,B draws the outline only, for contrast (GFX.LINE.B).
170 LINE (360,20)-(480,120),6,B
180 END
