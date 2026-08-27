10 REM PROG.COMMENT-MARK. Printed p.134's syntax box for REM is an
20 REM alternation -- REM or the apostrophe -- followed by optional comment
30 REM text, so the apostrophe is a STATEMENT form. It is accepted wherever
40 REM a statement may begin, and these are the two such places.
50 ' at the start of a line
60 PRINT "one" : ' after a colon
70 REM The consequence, which is OURS and not stated on the page: an
80 REM apostrophe cannot follow a statement directly, exactly as REM cannot.
90 REM A case cannot assert a syntax error, so what it pins is the accepted
100 REM forms; test/cli covers the rejection.
110 PRINT "two"
120 END
