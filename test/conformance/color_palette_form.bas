10 REM SCREEN.COLOR-PALETTE, ref-9801 printed p.51. [2] COLOR sets which
20 REM colour a palette number displays. Both forms are built now: the
30 REM assignment COLOR=(<palette>,<code>), and bare COLOR, which the page
40 REM says initialises the mapping.
50 REM
60 REM WHAT THIS CASE CAN AND CANNOT SEE, because it is the whole reason the
70 REM rule is also tested in OCaml (test/test_palette_indirection.ml).
80 REM Reassigning a palette recolours dots already on the screen. That is
90 REM invisible from inside the language: POINT reports the palette number a
100 REM dot was drawn THROUGH, not the colour it currently shows, so no
110 REM printed value here can change when a palette moves. A .bas case can
120 REM pin that POINT holds still; only a pixel readback can see the colour
130 REM move. Asserting the recolour here would need a .digest, and a digest
140 REM says "unchanged" whether the recolour happened or not -- the trap
150 REM this case's earlier version was written to warn about.
160 REM
170 REM So what is pinned here is the half the language does expose: the
180 REM forms are accepted, and POINT's answer is stable across a palette
190 REM reassignment. Both would have failed before this feature landed --
200 REM the assignment form was refused at run time.
210 PSET(10,10),3
220 PRINT "POINT after PSET through palette 3:";POINT(10,10)
230 REM Move palette 3 to a different colour. The dot on screen changes
240 REM colour; the number POINT reports does not.
250 COLOR=(3,5)
260 PRINT "POINT after COLOR=(3,5):";POINT(10,10)
270 REM Bare COLOR puts the mapping back. Still no change to POINT, and this
280 REM is the form every listing in the book's chapter 4 uses to reset the
290 REM palette after experimenting (intro-8801 printed pp.114, 120, 129).
300 COLOR
310 PRINT "POINT after bare COLOR:";POINT(10,10)
320 REM A palette number may be given any legal code, and the same code may
330 REM go to several palette numbers at once -- the page says so outright.
340 COLOR=(1,7)
350 COLOR=(2,7)
360 PRINT "two palettes sharing one code: accepted"
370 REM COLOR ,,, is still [1] COLOR setting nothing, NOT the initialising
380 REM form: only a COLOR with no arguments at all is that.
390 COLOR ,,,
400 PRINT "COLOR ,,, : accepted as [1] COLOR"
