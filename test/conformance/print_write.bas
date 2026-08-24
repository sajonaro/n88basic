10 REM PRINT.WRITE: items are always comma-separated on output regardless
20 REM of whether the source used "," or ";", strings are quoted, and
30 REM numbers carry none of PRINT's free-format padding.
40 A$ = "HELLO"
50 WRITE A$, 42, -7
60 WRITE 1; 2; 3
70 WRITE -3.5
80 END
