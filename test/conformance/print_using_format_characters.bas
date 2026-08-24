10 REM PRINT.USING: the format characters of printed p.128-129. The string
20 REM fields "!" and "&...&"; sign control; the asterisk fill; thousands
30 REM grouping; exponential form; the underscore escape; and the "%" a
40 REM number too wide for its field is printed behind.
50 REM Brackets sit around the fields whose width is the point, so that the
60 REM padding is visible in the expected output rather than trailing off.
70 PRINT USING "!";"BOOKS"
80 PRINT USING "[&  &]";"AB"
90 PRINT USING "[&  &]";"ABCDEFG"
100 PRINT USING "+###";-42
110 PRINT USING "[###-]";-42
120 PRINT USING "[###-]";42
130 PRINT USING "**###";42
140 PRINT USING "##,###";12345
150 PRINT USING "#.###^^^^";123400
160 PRINT USING "_### UNITS";42
170 PRINT USING "###";12345
180 END
