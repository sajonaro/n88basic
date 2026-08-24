10 REM GFX.POINT, ref-9801 printed p.122. The POINT statement sets the LP and
20 REM draws nothing; [1] POINT(<function>) reads the LP back.
30 REM
40 REM The page's own worked equivalence is the centrepiece:
50 REM   ex1) LINE(-200,30)-(100,120),3
60 REM   ex2) POINT(-200,30) : LINE -STEP(300,90),3
70 REM   "例1と例2は、まったく同じ図形を描きます" -- they draw exactly the
80 REM same figure. It is checked here by drawing each in turn and reading
90 REM the same samples back with [2] POINT, so the two blocks must print
100 REM identical lines. On-screen coordinates are used so the samples are
110 REM not all clipped away; the shape and the STEP are the page's.
120 LINE(100,30)-(400,120),3
130 GOSUB 1000
140 CLS 2
150 POINT(100,30)
160 LINE -STEP(300,90),3
170 GOSUB 1000
180 CLS 2
190 REM The statement moves the LP and paints NOTHING -- printed p.122 says
200 REM so in as many words. Nothing is lit at (50,50) after POINT(50,50).
210 POINT(50,50)
220 PRINT "after POINT(50,50), dot there is";POINT(50,50)
230 PRINT "LP world  X,Y:";POINT(0);POINT(1)
240 PRINT "LP screen X,Y:";POINT(2);POINT(3)
250 REM STEP is relative to the previous LP.
260 POINT STEP(10,-20)
270 PRINT "after POINT STEP(10,-20):";POINT(0);POINT(1)
280 REM Every graphics statement moves the LP too, so PSET then a STEP-less
290 REM read shows the LP following the drawing.
300 PSET(200,150)
310 PRINT "after PSET(200,150):";POINT(0);POINT(1)
320 END
1000 REM Sample the figure at four points that lie exactly ON it: the line
1010 REM runs (100,30)-(400,120), a slope of 90/300 = 0.3, so x=100+I*100
1020 REM gives y=30+I*30 with no rounding. Samples off the figure would only
1030 REM assert that both blocks drew nothing there, which is a much weaker
1040 REM claim than that both drew the SAME figure.
1050 FOR I=0 TO 3
1060 PRINT POINT(100+I*100,30+I*30);
1070 NEXT
1080 PRINT
1090 RETURN
