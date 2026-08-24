10 REM PRINT.LPRINT: formats exactly like PRINT, but is directed to the
20 REM printer stream. This harness runs every case through
30 REM N88basic.Interp.run_source with no separate ~printer sink, so per
40 REM Interp.run's own documented default, LPRINT output lands merged
50 REM into the same stream PRINT uses -- which is how this case can see
60 REM it at all.
70 PRINT "SCREEN"
80 LPRINT "PAPER", 7
90 END
