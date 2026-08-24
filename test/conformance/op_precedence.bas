10 REM Expected values come from ref-9801 printed p.19-20, not from a run.
20 REM p.19 section 10.1 orders ^ above the sign row, so -2^2 is -(2^2).
30 REM p.20 example 6 writes (X^Y) squared bare as X^Y^2, so ^ groups left;
40 REM example 5 writes X^(Y^2) with parentheses, and example 7 has Y*-X.
50 PRINT -2^2
60 PRINT 2^3^2
70 PRINT -2^2+1
80 PRINT (-2)^2
90 PRINT 2^(3^2)
100 PRINT 2*-3
110 REM ^ never yields an integer: p.20 prints 0^-1 as 1.70141E+38, a
120 REM single-precision value, from two integer operands. So an integer
130 REM base with a negative exponent keeps its fraction.
140 PRINT 2^-1
150 PRINT 2^-2
160 PRINT 3^-1
