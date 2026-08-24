10 REM PRINT USING edits values into a format string.
20 REM Numeric fields: # reserves a digit, . fixes the point, and a comma
30 REM groups thousands.
40 PRINT USING "###.##";3.14159
50 PRINT USING "#,###,###";1234567
60 REM A leading + shows the sign; a trailing - marks negatives only.
70 PRINT USING "+###";42
80 PRINT USING "###-";-42
90 REM ** fills the blank columns with asterisks, and the yen pair floats a
100 REM currency mark against the number.
110 PRINT USING "**###";7
120 PRINT USING "\\###";7
130 REM ^^^^ asks for exponential form.
140 PRINT USING "##.##^^^^";1234.5
150 REM String fields: ! is the first character, & a fixed-width field, and
160 REM @ the whole string.
170 A$="BASIC"
180 PRINT USING "!";A$
190 PRINT USING "&    &";A$
200 PRINT USING "@";A$
210 REM A literal in the format string is copied through.
220 PRINT USING "total ### units";12
