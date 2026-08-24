10 REM GFX.PAINT, GFX.CIRCLE and GFX.LINE.BF all fill with a tile string
20 REM as well as a palette number, and all three read it the same way --
30 REM the meaning is defined once, under [2] PAINT.
40 REM
50 REM A tile is 8 dots wide and as many rows tall as the string
60 REM describes. In this screen mode three characters make ONE row and
70 REM they are bit planes: for each dot column the three bits read
80 REM downward as a binary number give that dot's palette number. The
90 REM string below is the manual's own worked example, whose answer it
100 REM prints as 5 6 5 6 5 6 5 6.
110 SCREEN 3
120 CLS 2
130 T$=CHR$(&HAA)+CHR$(&H55)+CHR$(&HFF)
140 LINE (24,24)-(200,120),7,BF,T$
150 REM Read the filled dots back off the screen: the row must be the
160 REM manual's, and it must repeat every eight dots.
170 PRINT POINT(24,24); POINT(25,24); POINT(26,24); POINT(27,24)
180 PRINT POINT(28,24); POINT(29,24); POINT(30,24); POINT(31,24)
190 PRINT POINT(32,24); POINT(33,24)
200 REM One row of tile repeats down the screen as well as across.
210 PRINT POINT(24,25); POINT(24,26)
220 REM PAINT fills a bounded region with the same pattern, and CIRCLE's
230 REM F fills its interior with it.
240 LINE (24,160)-(300,340),2,B
250 PAINT (100,200),T$,2
260 PRINT POINT(100,200); POINT(101,200)
270 CIRCLE (460,240),80,6,,,,F
280 REM A tile string too short to describe even one row is refused.
290 LINE (400,20)-(500,60),7,BF,"AB"
300 END
