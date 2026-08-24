10 REM ERR.ERROR, untrapped: raises the manual's own wording for a
20 REM defined error number ("Division by Zero (/0)"), which is spelled
30 REM differently from this interpreter's own message for a literal
40 REM division by zero ("Division by zero") -- the two are aliases of
50 REM the same error code, not the same string.
60 PRINT "BEFORE";
70 ERROR 11
80 END
