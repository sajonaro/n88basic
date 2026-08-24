10 REM OP.MOD, OP.XOR, OP.IMP, OP.EQV. Every value asserted below is the
20 REM manual's own, not this interpreter's: printed p.23 works six
30 REM examples out in sixteen-bit binary, and three of them are these
40 REM operators. A case written from the code could not disagree with
50 REM the code, so the page is what the numbers come from.
60 PRINT 15 XOR 60
70 PRINT 17 EQV 12
80 PRINT 28 IMP 9
90 REM The three are bitwise, on two's-complement integers -- 17 EQV 12
100 REM being -30 is only explicable per bit -- and they share AND and
110 REM OR's conversion rule: printed p.21 converts operands to
120 REM -32768..+32767 and makes a value outside that range on conversion
130 REM an Overflow.
140 PRINT 5 XOR 3
150 PRINT 0 IMP 0
160 PRINT -1 EQV -1
170 REM MOD is the integer remainder, at level 7: tighter than + and -
180 REM at 8, looser than * and / at 5. So 2+3 MOD 2 is 2+(3 MOD 2) = 3,
190 REM and 2*3 MOD 4 is (2*3) MOD 4 = 2.
200 PRINT 7 MOD 3
210 PRINT 2+3 MOD 2
220 PRINT 2*3 MOD 4
230 REM XOR is looser than OR, IMP looser than XOR, EQV loosest of all,
240 REM so this groups as ((1 OR 0) XOR 1) with no parentheses needed.
250 PRINT 1 OR 0 XOR 1
260 REM Out of range on conversion is Overflow, per printed p.21.
270 PRINT 40000 XOR 1
280 END
