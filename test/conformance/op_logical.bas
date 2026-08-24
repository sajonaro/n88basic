10 REM Every expected value below is the manual's own, not this program's.
20 REM p.21 section 10.3: operands convert to 16-bit two's complement first,
30 REM and a value outside -32768..32767 raises Overflow on conversion.
40 REM p.22 gives the per-bit truth tables; p.23 works these expansions.
50 PRINT 48 AND 24
60 PRINT NOT 23
70 PRINT -1 OR 0
80 PRINT 12 AND 10
90 PRINT 12 OR 10
100 PRINT NOT 5
110 REM the conversion boundaries hold rather than overflowing
120 PRINT 32767 AND 1
130 PRINT -32768 OR 0
140 REM NOT is level 10, below relational at 9, so this is NOT (1 = 2)
150 A = 1 : B = 2 : PRINT NOT A = B
