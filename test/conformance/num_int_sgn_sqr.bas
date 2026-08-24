10 REM NUM.INT (partial): the largest integer not exceeding the value, so
20 REM it floors toward negative infinity rather than truncating. Compare
30 REM num_fix_cint_csng_cdbl, where FIX truncates toward zero instead.
40 PRINT INT(1.123)
50 PRINT INT(-2.7)
60 PRINT INT(3)
70 REM NUM.SGN (partial): 1, 0 or -1 by the sign of the value.
80 PRINT SGN(12.5)
90 PRINT SGN(0)
100 PRINT SGN(-0.001)
110 REM NUM.SQR (partial): the square root. A double-precision argument
120 REM gives a double-precision result, anything else single precision.
130 PRINT SQR(9)
140 PRINT SQR(2)
150 PRINT SQR(2#)
160 END
