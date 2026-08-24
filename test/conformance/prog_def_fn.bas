10 REM PROG.DEF-FN (partial): defines a function the program can call.
20 REM The parameters are in effect only while the definition expression
30 REM is evaluated, so the program's own X and Y keep their values
40 REM across the call. The parameter list may be left off entirely,
50 REM defining a function of no arguments, called with no parentheses.
60 DEF FNA(X,Y)=X*2+Y*3
70 X=100
80 Y=200
90 PRINT FNA(1,2)
100 PRINT X
110 PRINT Y
120 DEF FNB$(S$)=S$+"!"
130 PRINT FNB$("hi")
140 DEF FNC=7
150 PRINT FNC
160 END
