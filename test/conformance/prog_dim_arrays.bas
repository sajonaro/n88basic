10 REM PROG.DIM (partial): fixes the largest subscript each dimension may
20 REM take. With no OPTION BASE the smallest subscript is 0, so DIM A(3)
30 REM holds four elements, and one DIM may declare several arrays.
40 DIM A(3), B$(2)
50 PRINT A(0)
60 PRINT B$(2)+"."
70 A(3)=7
80 PRINT A(3)
90 REM Several maximum subscripts declare that many dimensions.
100 DIM M(2,3)
110 M(2,3)=9
120 PRINT M(2,3)
130 REM An array may be used undeclared, and then its subscripts run to 10.
140 U(10)=5
150 PRINT U(10)
160 REM A numeric array's element count is capped by its own type: 32767
170 REM for integer, 16383 for single, 8191 for double. The three are one
180 REM limit seen three ways -- at 2, 4 and 8 bytes an element they all
190 REM land just under 64K -- so passing one is Out of memory. A string
200 REM array has no stated cap and is not given one.
210 DIM I%(32766)
220 DIM G!(16382)
230 DIM H#(8190)
240 DIM S$(40000)
250 PRINT "caps ok"
260 REM A subscript past the declared maximum raises Subscript out of range.
270 PRINT A(4)
280 END
