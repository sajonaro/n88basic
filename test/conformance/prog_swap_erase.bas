10 REM PROG.SWAP (implemented): exchanges two variables of the same
20 REM type in place -- scalars, array elements, and strings alike.
30 REM PROG.ERASE (implemented): frees an array entirely, so the same
40 REM name can be DIM'd again with different bounds afterward.
50 A=1: B=2
60 SWAP A,B
70 PRINT A;B
80 A$="HELLO": B$="WORLD"
90 SWAP A$,B$
100 PRINT A$;" ";B$
110 DIM X(3)
120 X(1)=9
130 ERASE X
140 DIM X(5)
150 PRINT X(1)
160 END
