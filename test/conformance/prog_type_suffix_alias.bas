10 REM PROG.VARIABLE-NAMES, ref-9801 printed p.15 (section 6.2). The page
20 REM prints A!, A#, A% and A$ as four variables that ARE distinguished
30 REM from one another, and says of them: A!とAは同じ -- A! and A are the
40 REM SAME variable. A bare name is not a fifth cell; it is the same name
50 REM carrying whichever suffix its default kind implies, "!" until a
60 REM DEFxxx statement changes it for that letter (printed p.60).
70 REM
80 REM This printed 0 before 2026-08-18: the two spellings hashed to two
90 REM cells, a silent wrong answer rather than an error. Nothing cited
100 REM p.15 until tools/citation_coverage.py reported it.
110 A=5
120 PRINT "A=5, so A! is";A!
130 B!=7
140 PRINT "B!=7, so B is";B
150 REM The four suffixed spellings remain four separate variables.
160 C!=1:C#=2:C%=3:C$="s"
170 PRINT "C! C# C% distinct:";C!;C#;C%;" and C$ is ";C$
180 REM An array name follows the same rule.
190 D(1)=4
200 PRINT "D(1)=4, so D!(1) is";D!(1)
210 REM DEFINT moves which suffix a bare name carries, so E and E% become
220 REM one variable while a letter outside the range keeps single.
230 DEFINT E
240 E=9
250 PRINT "DEFINT E, E=9, so E% is";E%
260 L=2.5
270 PRINT "L is outside the DEFINT range:";L
