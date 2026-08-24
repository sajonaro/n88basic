10 REM GFX.LINE: either endpoint may be written STEP(dx,dy). The first is
20 REM relative to the last point referenced, the second to the first --
30 REM so line 70 draws from (10,10) to (110,60), and line 80, having no
40 REM start point of its own, carries on from where line 70 finished.
50 SCREEN 3
60 CLS 2
70 LINE (10,10)-STEP(100,50),7
80 LINE -STEP(100,0),4
90 REM The slot after B or BF is a line style: sixteen bits over sixteen
100 REM dots, a set bit drawing its dot, the pattern repeating. The B/BF
110 REM slot may be left empty to reach it, which is how the manual's own
120 REM worked example is written. &HF99F is that example's chain line.
130 LINE (10,100)-(400,100),7,,&HF99F
140 LINE (10,140)-(400,140),4,,&HFF00
150 REM A ,B outline may carry one too; BF may not, which is why the same
160 REM slot after BF means something else entirely.
170 LINE (10,180)-(300,300),2,B,&HF0F0
180 REM GFX.LINE.BF: the trailing slot is a second palette number, the
190 REM colour the interior is filled with. Without it the interior takes
200 REM the colour the rectangle was drawn in.
210 LINE (360,180)-(560,300),1,BF,5
220 LINE (360,320)-(560,380),6,BF
230 END
