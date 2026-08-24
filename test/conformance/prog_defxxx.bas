10 REM PROG.DEFINT / PROG.DEFSNG / PROG.DEFDBL / PROG.DEFSTR
20 REM (implemented): a letter-range declaration sets the default type
30 REM for unsuffixed names starting with those letters; an explicit
40 REM suffix on the name always overrides it.
50 DEFINT I-N
60 I=3.5
70 PRINT I
80 PRINT I!
90 DEFSTR L
100 L="HELLO"
110 PRINT L
120 DEFDBL D
130 D=1/3
140 PRINT D
150 DEFSNG S
160 S=2
170 PRINT S
180 END
