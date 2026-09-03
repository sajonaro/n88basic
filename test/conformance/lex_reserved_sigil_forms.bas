10 REM A reserved word this interpreter does not implement is reported BY
20 REM NAME, so a listing that uses one is told what it asked for. That worked
30 REM for INKEY$ and DSKI$ and not for INPUT$, because INPUT is itself an
40 REM implemented keyword: the run split into INPUT and a stray "$", and the
50 REM message became "Unexpected character" -- a typo's message for a
60 REM feature's absence. Same for the closed-up file forms, PRINT#1.
70 REM
80 REM A case cannot assert an error, so what this pins is the other half:
90 REM the sigils that ARE type suffixes still work, which is what a fix here
100 REM could plausibly break. test/cli covers the messages.
110 A# = 1.5
120 PRINT A#
130 B! = 2.5
140 PRINT B!
150 C% = 3
160 PRINT C%
170 D$ = "s"
180 PRINT D$
190 PRINT MID$("abc", 2, 1)
200 END
