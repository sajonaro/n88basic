10 REM How numbers are written out, and the arithmetic that is easy to get
20 REM wrong.
30 PRINT "PRINT's zones are 14 characters wide:"
40 PRINT "one","two","three"
50 REM A number carries a sign column in front and a space behind.
60 PRINT "signs:";1;-1;0
70 REM Fixed point while the value fits the digit budget, exponent beyond.
80 PRINT "small:";.1;.01;.001;.0001
90 PRINT "large:";123456;1234567
100 REM STR$ is PRINT's rendering as a string; MID$(...,2) drops the sign
110 REM column that STR$ keeps.
120 X=12.3456
130 PRINT "STR$        : [";STR$(X);"]"
140 PRINT "MID$(STR$,2): [";MID$(STR$(X),2);"]"
150 PRINT "VAL back    :";VAL(STR$(X))
160 REM Radix: HEX$ and OCT$ write them, &H and &O read them.
170 PRINT "HEX$(255)   : ";HEX$(255)
180 PRINT "OCT$(15)    : ";OCT$(15)
190 PRINT "&HFF, &O17  :";&HFF;&O17
200 REM Integer division rounds its operands, then truncates the quotient.
210 REM MOD is the remainder, and rounds its operands the same way.
220 PRINT "10\3, 23.75\5:";10\3;23.75\5
230 PRINT "13.3 MOD 4   :";13.3 MOD 4
240 REM The operators are bitwise, not merely true/false.
250 PRINT "48 AND 24, NOT 23:";48 AND 24;NOT 23
