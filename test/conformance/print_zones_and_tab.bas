10 REM PRINT.BASIC (partial): a number carries a sign column ahead of it
20 REM -- a space when positive, a minus when negative -- and a trailing
30 REM space. A comma moves to the next 14-character print zone; a
40 REM semicolon, a space, or a bare abutment write straight on.
50 PRINT 1
60 PRINT -1
70 PRINT "a","b"
80 PRINT "a";"b"
90 PRINT "a" "b"
100 REM A trailing separator suppresses the newline, so the next PRINT
110 REM carries on along the same line. A bare PRINT ends the line.
120 PRINT "x";
130 PRINT "y"
140 PRINT
150 REM PRINT.TAB (partial): moves the print position along the line,
160 REM measured from its start. A negative argument counts as 0.
170 PRINT "a";TAB(10);"b"
180 PRINT TAB(-5);"c"
190 END
