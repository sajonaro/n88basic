10 REM [2] COLOR reassigns which colour a palette number displays, and it
20 REM applies to dots ALREADY on the screen: nothing is redrawn, the
30 REM numbers already in the frame simply resolve to a different colour.
40 REM POINT keeps reporting the palette a dot was drawn THROUGH, so the
50 REM recolour is visible in the picture and not in these numbers.
60 CLS 3
70 COLOR=(1,7)
80 CIRCLE(160,100),50,1
90 PAINT(160,100),1,1
100 PRINT "drawn through palette 1, showing white";
110 PRINT " - POINT says";POINT(160,100)
120 REM Now move palette 1. The disc turns blue without being touched.
130 COLOR=(1,1)
140 PRINT "palette 1 moved to blue - POINT still says";POINT(160,100)
150 REM Bare COLOR puts every palette back to its own number.
160 COLOR
170 PRINT "after bare COLOR, palette 1 shows colour 1"
