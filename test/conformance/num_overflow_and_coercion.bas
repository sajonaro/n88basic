10 REM NUM.OVERFLOW (implemented): an assignment outside the target
20 REM type's range raises Overflow (OV) rather than silently wrapping.
30 REM NUM.COERCION (implemented): a mixed-precision expression prints
40 REM at the more precise operand's own significant-digit budget.
50 A%=32767
60 B%=-32768
70 PRINT A%; B%
80 C%=4
90 PRINT C%+1#/3#
100 D%=32768
110 END
