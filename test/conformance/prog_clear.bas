10 REM PROG.CLEAR (partial): resets every numeric variable to 0, every
20 REM string variable to the null string, and array bounds to
30 REM undimensioned. Its memory-layout arguments are parsed and
40 REM evaluated but otherwise ignored.
50 A=42
60 A$="HELLO"
70 DIM X(3)
80 X(1)=9
90 CLEAR
100 PRINT A
110 PRINT A$;"|"
120 DIM X(5)
130 PRINT X(1)
140 CLEAR ,1000
150 PRINT A
160 END
