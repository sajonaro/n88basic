10 REM NUM.DIV-BY-ZERO is DIVERGENT: the manual says dividing by zero
20 REM prints a short "/0" notice and continues with the largest value
30 REM the result type can hold, signed as the true result would be.
40 REM This interpreter instead raises Division by zero and halts, same
50 REM as any other runtime error. This case pins THAT behaviour -- the
60 REM day the manual's print-and-continue rule is implemented, this
70 REM case must fail and be rewritten deliberately, not patched quietly.
80 PRINT "BEFORE";
90 PRINT 1/0
100 END
