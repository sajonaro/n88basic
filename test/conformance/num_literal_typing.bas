10 REM NUM.TYPES: a written constant takes its type from its NOTATION, and
20 REM the digit count alone is enough to change it.
30 REM
40 REM Printed p.13 section 5.5 -- single precision: a real of seven digits
50 REM or fewer, a trailing "!", or the "E" exponent form.
60 REM Printed p.14 section 5.6 -- double precision: a real of EIGHT digits
70 REM or more, a trailing "#", or the "D" exponent form.
80 REM
90 REM The boundary, with nothing else written differently:
100 PRINT "7 digits:";1234567
110 PRINT "8 digits:";12345678
120 REM The seven-digit value is single, so it exceeds a six-digit display
130 REM budget and shows in exponent form. The eight-digit value is double,
140 REM whose budget is sixteen, so it shows in full. This reads as an
150 REM inconsistency and is not one: the display rule is the same, and what
160 REM differs is the type the constant was written into.
170 PRINT "1000000 :";1000000
180 PRINT "10000000:";10000000
190 REM Spelling the type explicitly settles it either way.
200 PRINT "10000000! :";10000000!
210 PRINT "1000000#  :";1000000#
220 REM The manual's own three double-precision examples.
230 PRINT "1234567.890  :";1234567.890
240 PRINT "56789.0#     :";56789.0#
250 PRINT "-1.09432D-58 :";-1.09432D-58
