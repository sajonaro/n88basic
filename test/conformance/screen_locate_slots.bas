10 REM SCREEN.LOCATE: X is the horizontal coordinate and comes first, Y
20 REM the vertical one, both in character coordinates with the screen's
30 REM top-left corner as (0,0). All three slots are optional and an
40 REM empty one is written as a bare comma, so every LOCATE below is a
50 REM legal statement -- each was a syntax error here until the page was
60 REM read, which is the divergence this case now guards.
70 LOCATE 10,5
80 LOCATE 10
90 LOCATE ,5
100 LOCATE ,,0
110 LOCATE 10,5,1
120 LOCATE
130 REM This interpreter has no text screen, so none of the above moves
140 REM anything and nothing is printed by them. That the arguments are
150 REM recorded in the manual's order -- X, then Y, then the cursor
160 REM switch -- is pinned by test_interp.ml's "LOCATE slots are each
170 REM optional", which reads the display list directly; a conformance
180 REM case has no cursor to observe.
190 PRINT "locate forms accepted"
200 END
