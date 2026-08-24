10 REM DATA holds constants for READ to consume, in line-number order.
20 REM A numeric constant may be written in any of its three forms:
30 REM decimal, octal (&O or a bare &) and hexadecimal (&H).
40 DATA 42,-7,3.5
50 DATA &H10,&O17,&12345
60 DATA "quoted, with a comma",unquoted
70 FOR I=1 TO 3:READ N:PRINT "decimal:";N:NEXT I
80 FOR I=1 TO 3:READ N:PRINT "radix  :";N:NEXT I
90 READ A$:PRINT "quoted : [";A$;"]"
100 READ B$:PRINT "bare   : [";B$;"]"
110 REM RESTORE winds the cursor back so the same data can be read again.
120 RESTORE
130 READ N
140 PRINT "after RESTORE:";N
150 REM RESTORE can also name the line to start from.
160 RESTORE 50
170 READ N
180 PRINT "after RESTORE 50:";N
