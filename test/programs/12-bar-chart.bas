10 REM A whole small program rather than a feature demonstration: twelve
20 REM readings drawn as a bar chart, with the scale worked out from the
30 REM data instead of assumed.
40 DIM V(12)
50 DATA 470,80,1235,1450,1640,1780,1920,2010,1580,1560,1660,1680
60 REM Read the readings and find the largest, to scale the bars by.
70 M=0
80 FOR I=1 TO 12
90   READ V(I)
100   IF V(I)>M THEN M=V(I)
110 NEXT I
120 CLS 3
130 REM Axes.
140 LINE(40,10)-(40,180),7
150 LINE(40,180)-(620,180),7
160 REM One bar per reading, its height scaled to the largest.
170 FOR I=1 TO 12
180   X=40+I*44
190   H=INT(V(I)*160/M)
200   LINE(X-16,180-H)-(X+16,179),I MOD 7+1,BF
210 NEXT I
220 REM A dashed line at the mean, to show a styled line in use.
230 T=0
240 FOR I=1 TO 12:T=T+V(I):NEXT I
250 A=INT(T/12)
260 Y=180-INT(A*160/M)
270 LINE(40,Y)-(620,Y),7,,&HF0F0
280 PRINT "largest reading:";M
290 PRINT "mean reading   :";A
300 REM Read a few bars back to prove they were drawn where intended.
310 PRINT "bar 8 top lit  :";POINT(392,180-INT(V(8)*160/M)+1)
320 PRINT "above bar 8    :";POINT(392,180-INT(V(8)*160/M)-4)
