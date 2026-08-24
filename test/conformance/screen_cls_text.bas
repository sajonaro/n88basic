10 REM SCREEN.CLS: the function code is 1, 2 or 3, and 1 when it is left
20 REM out. 1 clears the text screen only, so neither the bare CLS on
30 REM line 60 nor the explicit CLS 1 on line 80 disturbs the graphics
40 REM screen -- all three boxes drawn here survive to the end.
50 SCREEN 3
60 CLS
70 LINE (20,20)-(140,120),7,B
80 CLS 1
90 LINE (180,20)-(300,120),4,B
100 CLS
110 LINE (340,20)-(460,120),6,B
120 END
