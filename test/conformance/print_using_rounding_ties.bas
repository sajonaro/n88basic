10 REM PRINT.USING rounds half-up (ties away from zero). Two different things
20 REM can look like a tie in a decimal listing, and only one of them is one.
30 REM
40 REM A GENUINE tie: .875 and .125 and .625 are exact in binary, so the value
50 REM really does sit halfway and the rule has to decide it. Half-up carries;
60 REM half-to-even would not, on the two whose preceding digit is even -- so
70 REM these are what distinguish this dialect's rule from the one C's printf
80 REM applies by default, and 221.875 alone does not, its preceding digit
90 REM being odd and both rules agreeing.
100 PRINT USING "###.##";221.875
110 PRINT USING "#.##";0.125
120 PRINT USING "#.##";0.625
130 PRINT USING "##";2.5
140 REM A NEAR tie: 2.675 is not exact. The single-precision value is
150 REM 2.6749999523, which is BELOW the halfway point, so half-up on the true
160 REM stored value gives 2.67 and not 2.68. An implementation that nudges
170 REM by an epsilon before rounding gets 2.68 here while still passing the
180 REM genuine ties above, which is why this line is worth its own case.
190 PRINT USING "#.##";2.675
