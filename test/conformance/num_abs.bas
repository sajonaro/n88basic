10 REM NUM.ABS: the absolute value. Its result type does not follow its
20 REM argument's -- it is double precision when the argument carries a
30 REM double, and single precision in every other case, integers
40 REM included. Both lines below are the manual's own examples.
50 B=ABS(-2)
60 PRINT B
70 PRINT ABS(-1.000000000000001#)
80 REM The rule is observable, not bookkeeping: the absolute value of the
90 REM most negative integer does not fit the integer type, so a result
100 REM that kept the argument's type would overflow here instead of
110 REM printing 32768.
120 A%=-32768
130 PRINT ABS(A%)
140 REM A double argument keeps all sixteen digits; a single does not.
150 D#=-1.5
160 PRINT ABS(D#)
170 END
