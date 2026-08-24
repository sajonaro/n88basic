10 REM PRINT.LPRINT-USING: formats exactly like PRINT USING, but is
20 REM directed to the printer stream. As with PRINT.LPRINT, this harness
30 REM runs with no separate ~printer sink, so the formatted text lands
40 REM merged into the same stream as PRINT's own output.
50 LPRINT USING "###.##"; 3.5
60 END
