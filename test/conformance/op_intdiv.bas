10 REM OP.INTDIV, ref-9801 printed p.20 (section 10.1) and p.25 (10.6).
20 REM The page states both halves of the semantics outright: real operands
30 REM are ROUNDED before the operation, and the quotient is then TRUNCATED.
40 REM Its own two worked examples are the case below.
50 PRINT "10\3   ="; 10 \ 3
60 PRINT "23.75\5 ="; 23.75 \ 5
70 REM The second is the one that pins both halves at once: 23.75 rounds to
80 REM 24, and 24/5 = 4.8 truncates to 4. A single rule cannot produce it --
90 REM truncating first would give 23/5 = 4.6 -> 4 by luck, but rounding the
100 REM QUOTIENT would give 5, so the case tells the two designs apart.
110 REM Level 6 in the manual's table: tighter than MOD at 7, looser than
120 REM * and / at 5.
130 PRINT "6\2*2   ="; 6 \ 2 * 2
140 PRINT "7 MOD 5\2 ="; 7 MOD 5 \ 2
150 PRINT "1+9\2   ="; 1 + 9 \ 2
160 REM Truncation is toward zero, so a negative quotient loses its fraction
170 REM the same way rather than going more negative. Ours: the page shows
180 REM no negative example.
190 PRINT "-9\2    ="; -9 \ 2
200 REM MOD, described in the same paragraph, is unchanged by any of this.
210 PRINT "13.3 MOD 4 ="; 13.3 MOD 4
220 PRINT "25.68 MOD 6.99 ="; 25.68 MOD 6.99
