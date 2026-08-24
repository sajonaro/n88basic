10 REM PROG.LINE-NUMBERS, ref-9801 printed p.9 (chapter 2 section 3):
20 REM 行番号は1から65529までの整数で指定します -- line numbers are integers
30 REM from 1 to 65529. The manual states the range outright, so refusing one
40 REM outside it enforces the manual's rule rather than inventing ours.
50 REM
60 REM Nothing cited printed p.9 until tools/citation_coverage.py reported
70 REM it, and both limits that page states were unenforced: line 0, 65530
80 REM and 99999 all ran.
90 PRINT "lines 1 to 65529 load"
65530 PRINT "this line number is out of range"
