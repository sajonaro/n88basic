10 REM CTRL.ON-GOTO / CTRL.ON-GOSUB (partial): the manual's three
20 REM stated cases for the selector -- in range, zero falls through,
30 REM and past the end also falls through (both with no error) -- plus
40 REM ON...GOSUB choosing and returning.
50 ON 2 GOTO 200,210,220
60 PRINT "NEVER"
70 END
200 PRINT "ONE": GOTO 900
210 PRINT "TWO": GOTO 900
220 PRINT "THREE": GOTO 900
900 ON 0 GOTO 950
910 PRINT "ZERO FELL THROUGH"
920 ON 9 GOTO 950,960
930 PRINT "PAST THE END FELL THROUGH"
940 ON 1 GOSUB 990
945 PRINT "BACK"
950 END
960 END
990 PRINT "IN SUB";
995 RETURN
