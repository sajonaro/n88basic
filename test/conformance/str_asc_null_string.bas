10 REM STR.ASC (partial): the manual does not say what ASC does on the
20 REM null string; this interpreter raises Illegal function call there,
30 REM which this case pins as the documented (not manual-derived) rule.
40 PRINT ASC("")
50 END
