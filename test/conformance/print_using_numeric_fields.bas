10 REM PRINT.USING: the 8-column right-justified numeric field, and
20 REM half-up rounding (ties away from zero, not banker's rounding).
30 PRINT USING "#####.##"; 172.0083
40 PRINT USING "##.##"; 41.3849
50 PRINT USING "##.#"; 41.054
60 PRINT USING "##"; 2.5
70 PRINT USING "#.##"; .125
80 PRINT USING "##.#"; 30.039
90 PRINT USING "#####"; 3000
100 PRINT USING "#####"; 0
110 END
