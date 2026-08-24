10 REM DATA.BASIC (partial): constants embedded for READ, comma
20 REM separated. A string constant needs quotes only when it holds a
30 REM comma or period, keeps leading spaces, or is Japanese text.
40 REM DATA lines may sit anywhere and are read in line-number order.
50 DATA 1, CBA, 1465
60 READ N, S$, M
70 PRINT N
80 PRINT S$
90 PRINT M
100 REM One READ runs on across several DATA lines.
110 READ P, Q
120 PRINT P
130 PRINT Q
140 DATA 10, 20, 30
150 REM DATA.RESTORE: with a line number, reading resumes from that DATA
160 REM line; with none, from the first DATA line in the program.
170 RESTORE 140
180 READ R
190 PRINT R
200 RESTORE
210 READ T
220 PRINT T
230 REM Asking for more than the DATA lines hold raises Out of DATA.
240 RESTORE 140
250 READ A, B, C, D
260 END
