10 REM LINE, and the sixteen-bit style mask.
20 REM Bit 15 is the first dot drawn and bit 0 the sixteenth, the pattern
30 REM repeating every sixteen dots. &HFFFF is solid.
40 CLS 3
50 LINE(0,0)-(639,199),7
60 LINE(0,90)-(639,90),7,,&HFFFF
70 LINE(0,100)-(639,100),7,,&HF0F0
80 LINE(0,110)-(639,110),7,,&HAAAA
90 REM Read the first sixteen dots of each back: solid, four-on-four-off,
100 REM and alternating.
110 FOR Y=90 TO 110 STEP 10
120   PRINT "y=";Y;":";
130   FOR X=0 TO 15:PRINT POINT(X,Y);:NEXT X
140   PRINT
150 NEXT Y
