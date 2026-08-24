10 REM PRINT.USING: the manual's own worked example (printed p.129, with its
20 REM output printed on p.130). It exercises three rules at once -- "@" takes
30 REM a whole string, the yen sign prints immediately before the number so it
40 REM floats right against the digits, and the template is applied again from
50 REM the start to each pair of values that follows.
60 PRINT USING "@=¥¥### ";"BOOKS",2500,"TICKETS",1440,"DRINKS",4300
70 END
