10 REM PRINT.USING: literal text passes through untouched, a bare "#"
20 REM inside prose still starts a one-digit field, the format string is
30 REM reused from the start while values remain, and output stops the
40 REM instant a field has no value left to fill -- the trailing literal
50 REM after a starved field is never emitted.
60 PRINT USING "X = ##.# UNITS"; 41.054
70 PRINT USING "GROUP # = ##.#"; 3; 41.054
80 PRINT USING "###"; 1; 2; 3
90 PRINT USING "## ##"; 1
100 END
