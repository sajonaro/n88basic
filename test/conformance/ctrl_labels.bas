10 REM CTRL.GOTO / CTRL.GOSUB / CTRL.IF: the manual's own labelled program
20 REM (ref-9801 printed p.29 / PDF p.42, section 13), which rewrites a
30 REM line-numbered original to use label names. INPUT is replaced by a
40 REM loop over the three cases so the program needs no console, and a
50 REM labelled GOSUB is added -- the manual's other labelled example.
60 FOR I=-1 TO 1
70 A=I
80 IF A<0 THEN *MINUS
90 IF A>0 THEN *PLUS
100 PRINT "zero"
110 GOTO *AGAIN
120 *PLUS : PRINT "plus"
130 GOTO *AGAIN
140 *MINUS : PRINT "minus"
150 *AGAIN : NEXT I
160 GOSUB *SUB
170 PRINT "back"
180 END
190 *SUB : PRINT "in sub"
200 RETURN
