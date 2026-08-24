10 REM PROG.LABELS, ref-9801 printed p.30 -- section 13's rules, which run
20 REM onto the page AFTER the one the clause used to cite. Nothing cited
30 REM p.30 until tools/citation_coverage.py reported it, and two of its
40 REM rules were recorded here as "ours, because the manual is silent".
50 REM The manual is not silent; the earlier reading stopped at the page break.
60 REM
70 REM Rule (7): a statement following a label on one line is separated from
80 REM it by a colon OR BY A SPACE. The space form was refused before.
90 GOTO *SPACED
100 PRINT "not reached"
110 *SPACED PRINT "rule 7: a space separates a label from its statement"
120 REM The colon form keeps working, and is the manual's own example shape.
130 GOSUB *COLON
140 GOTO *ALONE
150 *COLON : PRINT "rule 7: so does a colon"
160 RETURN
170 REM A label may also sit alone on its line.
180 *ALONE
190 PRINT "a label may sit alone on its line"
200 REM Rule (3): letters, digits and periods, matched case-insensitively.
210 GOTO *a.b1
220 PRINT "not reached"
230 *A.B1
240 PRINT "rule 3: digits and periods, matched without regard to case"
250 REM Rule (4): a reserved word may not BE a label, but may be contained
260 REM in one -- *MYFOR is legal where *FOR is not.
270 GOSUB *MYFOR
280 END
290 *MYFOR
300 PRINT "rule 4: a label may contain a reserved word"
310 RETURN
