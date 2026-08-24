10 REM DATA.READ: a string constant must be read into a string variable,
20 REM but a numeric constant may be read into either kind. Reading 42
30 REM into A$ is therefore legal and gives the number's own digits --
40 REM no sign column and no trailing space, so "42." below closes up.
50 DATA 42, -7.5, CBA
60 READ A$
70 PRINT A$+"."
80 READ B$
90 PRINT B$+"."
100 REM A string constant into a string variable is the ordinary case.
110 READ C$
120 PRINT C$+"."
130 REM The same numeric constant read into a numeric variable is a
140 REM number, carrying PRINT's sign column and trailing space.
150 RESTORE
160 READ N
170 PRINT N
180 REM Where the kinds do not match, the manual is explicit that READ
190 REM raises Syntax error rather than Type mismatch. An unquoted item
200 REM that does not parse as a number is a string constant, so CBA
210 REM into a numeric variable lands here.
220 RESTORE 230
230 DATA CBA
240 READ Z
250 END
