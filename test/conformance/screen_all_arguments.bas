10 REM SCREEN.BASIC: all four slots are optional and an empty one is written
20 REM as a bare comma (printed p.140 / PDF p.151). The screen mode is 0 to
30 REM 3; the screen switch shows the graphics screen at 0 or 1 and blanks
40 REM it temporarily at 2 or 3; the active and display pages choose which
50 REM page graphics are written to and which one is shown.
60 REM This interpreter has one page and a 640x400 framebuffer whatever the
70 REM mode, so the three further arguments are recorded and have no visible
80 REM effect. What this case pins is that the forms are accepted at all --
90 REM until now a SCREEN carrying any of them was refused outright.
100 SCREEN 3
110 SCREEN 3,0
120 SCREEN 3,0,0,1
130 SCREEN ,,0,1
140 SCREEN
150 PRINT "ACCEPTED"
160 END
