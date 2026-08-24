10 REM IN.INPUT, ref-9801 printed p.82. A typed field must match its
20 REM variable's type or INPUT shows "?Redo from start" and asks again.
30 REM The page does not say which NOTATIONS a numeric field may use.
40 REM
50 REM Until 2026-08-18 INPUT converted a field with OCaml's own float
60 REM parser rather than a BASIC one, so it accepted literals N88-BASIC
70 REM never had -- "1_000" as 1000, "0x10" as 16, and "nan" and "inf",
80 REM which put a NaN or an overflow into a numeric variable from a typed
90 REM line. It also rejected "1D3", a double-precision constant the manual
100 REM defines (printed p.14), while accepting its single-precision sibling
110 REM "1E3" (p.13) -- an asymmetry no reading of the manual supports.
120 REM
130 REM It now shares DATA's whole-field reader, so one definition of "a
140 REM typed number" serves both. Accepting the radix forms follows from
150 REM that sharing and is OUR reading, the manual being silent.
160 REM
170 REM The stdin for this case supplies, in order: the decimal forms, the
180 REM exponent forms, a type-suffixed real, and the three radix forms.
190 INPUT A,B,C
200 PRINT "decimal:";A;B;C
210 INPUT D,E,F
220 PRINT "exponent and suffix:";D;E;F
230 INPUT G,H,I
240 PRINT "radix:";G;H;I
250 REM Anything that is not a BASIC number is refused, and the refusal is
260 REM the page's own "?Redo from start" -- the next line supplies "nan",
270 REM which is rejected, and then 7, which is taken.
280 INPUT J
290 PRINT "after a refused answer:";J
