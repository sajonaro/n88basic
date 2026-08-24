10 REM CIRCLE, and PAINT bounded by a colour.
20 REM PAINT takes the point to start from, the colour to fill with, and
30 REM the colour that stops it. The boundary itself keeps its own colour.
40 CLS 3
50 CIRCLE(160,100),60,7
60 PAINT(160,100),5,7
70 PRINT "centre, filled  (want 5):";POINT(160,100)
80 PRINT "just inside rim (want 5):";POINT(160,42)
90 PRINT "the rim itself  (want 7):";POINT(160,40)
100 PRINT "outside         (want 0):";POINT(160,20)
110 REM A second circle left unpainted, to show the fill stopped.
120 CIRCLE(400,100),60,4
130 PRINT "unpainted centre (want 0):";POINT(400,100)
