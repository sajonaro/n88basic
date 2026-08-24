10 REM INPUT splits one typed line on commas, one field per variable, and
20 REM the types must match or it asks for the whole line again.
30 INPUT "name and age";N$,A
40 PRINT "name: ";N$
50 PRINT "age :";A
60 REM A numeric field may use any BASIC numeric notation.
70 INPUT "a number in any form";V
80 PRINT "read as:";V
90 REM LINE INPUT takes the whole line, commas and quotes included.
100 LINE INPUT "a whole line: ";L$
110 PRINT "got [";L$;"]"
120 PRINT "length:";LEN(L$)
