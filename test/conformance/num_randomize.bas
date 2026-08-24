10 REM NUM.RANDOMIZE: the same seed, given twice, reseeds RND to the same
20 REM point, and a bare RANDOMIZE reads its seed from the input source
30 REM instead of an interactive prompt (this interpreter's own decision
40 REM for a non-interactive runner -- see spec/clauses.json).
50 RANDOMIZE 7
60 A = RND(1)
70 RANDOMIZE 7
80 B = RND(1)
90 PRINT A = B
100 RANDOMIZE
110 C = RND(1)
120 RANDOMIZE 7
130 D = RND(1)
140 PRINT C = D
150 END
