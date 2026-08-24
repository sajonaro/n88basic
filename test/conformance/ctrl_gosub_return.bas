10 REM CTRL.GOSUB / CTRL.RETURN: a subroutine call returns to the
20 REM statement after GOSUB, and subroutines nest.
30 PRINT "A";
40 GOSUB 100
50 PRINT "D"
60 END
100 PRINT "B";
110 GOSUB 200
120 PRINT "C";
130 RETURN
200 PRINT "b";
210 RETURN
