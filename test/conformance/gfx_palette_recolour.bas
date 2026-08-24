10 REM SCREEN.COLOR-PALETTE, ref-9801 printed p.51 -- the indirection itself,
20 REM pinned at the conformance layer by a digest rather than by output.
30 REM
40 REM WHY A DIGEST HERE, WHEN THIS PROJECT PREFERS A POINT READBACK.
50 REM Because the language cannot see this rule. Printed p.123 says [2]
60 REM POINT returns the dot's colour AS A PALETTE NUMBER, so it reports the
70 REM palette a dot was drawn through and does not move when that palette is
80 REM reassigned -- correctly. color_palette_form.bas pins exactly that.
90 REM No printed value can therefore change when a palette moves, and the
100 REM recolour is visible only in the rendered frame.
110 REM
120 REM The digest is over the RESOLVED picture (test_conformance.ml hashes
130 REM Framebuffer.to_rgb_bytes), so it does change when a palette moves.
140 REM Verified by rendering this program with and without line 190: the
150 REM two frames differ. That is the distinguishing input, and it is the
160 REM reason this case is not the usual "a digest only says unchanged".
170 REM
180 REM intro-8801 printed p.119's demonstration, as a program.
190 COLOR=(0,7)
200 PSET(100,100),0
210 CIRCLE(300,150),40,1
220 PAINT(300,150),3,1
230 REM Now move both palettes. Every dot drawn above recolours at once:
240 REM the dot at (100,100), the circle's outline, and its interior.
250 COLOR=(0,1)
260 COLOR=(1,6)
270 REM THE FRAME THIS DIGEST STANDS FOR, verified pixel by pixel rather than
280 REM taken from the implementation -- a digest is opaque, so the appearance
290 REM it pins is written down here where a reader can check it:
300 REM   (100,100) dot drawn via palette 0 ......... blue   (0,0,255)
310 REM   (300,110) circle outline, palette 1 ....... yellow (255,255,0)
320 REM   (300,150) interior, palette 3 untouched ... purple (255,0,255)
330 REM   (600,380) background, also palette 0 ...... blue   (0,0,255)
340 REM The background is the point worth noticing: the whole screen is
350 REM palette 0, so moving palette 0 recolours every pixel nobody drew on.
