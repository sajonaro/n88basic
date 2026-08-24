10 REM STR.VAL: every notation the manual lists is accepted -- octal,
20 REM decimal and hexadecimal integers, and decimal-point and exponent
30 REM reals. &H20 is the manual's own example.
40 PRINT VAL("&H20")
50 PRINT VAL("&O17")
60 PRINT VAL("&17")
70 PRINT VAL("1E3")
80 PRINT VAL("1.5E+2")
90 PRINT VAL("-42.5")
100 REM Scanning stops at the first character that is not a digit of the
110 REM base in hand, and what counts as one differs by base: A-F are
120 REM digits under &H, while 8 and 9 are not digits under octal, so
130 REM "&19" is one rather than nineteen.
140 PRINT VAL("&HFACE")
150 PRINT VAL("&19")
160 PRINT VAL("42X")
170 REM Spaces anywhere in the string are ignored, not merely trimmed
180 REM from its ends, so this is twelve and not one.
190 PRINT VAL("1 2")
200 PRINT VAL("- 5")
210 REM A string whose first character is none of a digit, "+", "-" or
220 REM "&" is zero, and so is a "&" with no digits after it.
230 PRINT VAL("XY")
240 PRINT VAL("&")
250 END
