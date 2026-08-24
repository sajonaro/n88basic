10 REM NUM.RADIX-LITERALS: an integer constant may be written in octal or
20 REM hexadecimal as well as decimal. Hexadecimal takes &H and digits 0
30 REM to F; octal takes &O -- or a bare & on its own, which the manual
40 REM gives as an equal alternative, so &12345 below is octal and not a
50 REM decimal number with a stray sigil. All four are the manual's own
60 REM examples.
70 PRINT &H100
80 PRINT &HCFFF
90 PRINT &O7777
100 PRINT &12345
110 REM Both ranges are sixteen bits, and the sixteen bits are read as a
120 REM signed integer, so the top of each range is -1 rather than 65535.
130 PRINT &HFFFF
140 PRINT &177777
150 REM A value entered in either form is output in decimal; HEX$ and
160 REM OCT$ are what put it back into its own notation.
170 PRINT HEX$(&H100)
180 PRINT OCT$(&O7777)
190 REM They are ordinary integer constants, usable wherever one is.
200 A=&HFF+1
210 PRINT A
220 END
