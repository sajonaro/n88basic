10 REM PRINT.USING. Two format characters the manual documents and no case
20 REM reached: a "+" at the END of the format, and the combined "**¥".
30 REM
40 REM Printed p.128: a "+" written at the beginning OR THE END of the format
50 REM string puts the sign before or after the number respectively. Only the
60 REM leading form was covered.
70 PRINT USING "###+";42
80 PRINT USING "###+";-42
90 REM Printed p.129 gives the three fill forms separately, and they reserve
100 REM different widths: "**" reserves two digit positions; "¥¥" reserves two
110 REM OF WHICH ONE carries the yen itself; "**¥" reserves THREE, again with
120 REM one for the yen. "**" and "¥¥" each had a case and the combination did
130 REM not, which is where a width mistake would hide.
140 PRINT USING "**###";25
150 PRINT USING "¥¥###";25
160 PRINT USING "**¥###";25
170 REM The yen sits immediately before the number rather than at the field's
180 REM left edge, so a value filling every digit position leaves no fill.
190 PRINT USING "**¥###";12345
