10 REM IN.LINE-INPUT: reads a whole line verbatim into a string variable,
20 REM with no INPUT-style comma/quote splitting and no "? " appended
30 REM after a prompt (unlike INPUT).
40 LINE INPUT "NAME:"; N$
50 LINE INPUT L$
60 PRINT N$
70 PRINT L$
80 END
