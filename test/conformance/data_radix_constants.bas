10 REM DATA.BASIC, ref-9801 printed p.12-13 (section 5.3). An integer
20 REM constant has THREE forms -- octal, decimal and hexadecimal -- so
30 REM &H100 is as much a constant as 256 is, and DATA takes constants.
40 REM
50 REM DATA's own raw-item scanner did not know the radix forms. It
60 REM required a digit after an optional sign, so "&HFF" failed that test,
70 REM was classified as the STRING "&HFF", and only announced itself when a
80 REM READ tried to take it as a number -- reporting Syntax error on the
90 REM READ line rather than on the DATA line that actually held the fault.
100 REM The rest of the language read these literals correctly throughout.
110 REM
120 REM Octal takes &O or a bare &; hexadecimal takes &H (printed p.13, whose
130 REM own examples are &12345, &O7777, &H100 and &HCFFF).
140 DATA &H100,&HCFFF,&HFFFF,&O7777,&12345,42,-123
150 READ A,B,C,D,E,F,G
160 PRINT A;B;C;D;E;F;G
170 REM &HFFFF is -1 and &HCFFF is negative because the radix forms carry a
180 REM 16-bit signed integer, which is the range printed p.12 gives the
190 REM integer type. The same literals in an expression must agree.
200 PRINT &H100;&HCFFF;&HFFFF;&O7777;&12345
210 REM What is NOT a numeric constant stays a string, so a READ into a
220 REM string variable takes it verbatim. A sign is deliberately not part of
230 REM the radix forms: printed p.13 spells the sign rule out for the
240 REM decimal form alone.
250 DATA &HGG,&H,-&HFF
260 READ P$,Q$,R$
270 PRINT "["P$"]["Q$"]["R$"]"
