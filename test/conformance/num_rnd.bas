10 REM NUM.RND (implemented): RND is seeded from a fixed constant, never
20 REM the wall clock, so the same program draws the same sequence on
30 REM every run; RND(0) repeats the last value drawn; a negative
40 REM argument reseeds deterministically from that argument.
50 PRINT RND(1); RND(1); RND(1)
60 A=RND(1)
70 PRINT A=RND(0)
80 B=RND(-7)
90 C=RND(-7)
100 PRINT B=C
110 END
