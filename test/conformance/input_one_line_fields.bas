10 REM IN.INPUT: one typed line answers the whole statement. With several
20 REM variables the line is split on commas, one field per variable, and
30 REM the counts must agree.
40 INPUT "SIZE"; W, H
50 PRINT W; H
60 REM A "," after the prompt shows the prompt and nothing else -- no
70 REM question mark, no space. A ";" shows both.
80 INPUT "NAME", N$
90 PRINT "["+N$+"]"
100 REM A quoted field keeps commas and the end spaces that would
110 REM otherwise separate fields and be trimmed. The quotes themselves
120 REM are not part of the value.
130 INPUT A$, B$
140 PRINT "["+A$+"]["+B$+"]"
150 REM Return on an empty field is 0 or the null string, but the commas
160 REM still have to be typed, so a line of just commas is an answer.
170 INPUT C$, K, D$
180 PRINT "["+C$+"]"; K; "["+D$+"]"
190 REM A field that does not fit its variable shows "?Redo from start"
200 REM and asks for the whole line again rather than stopping.
210 INPUT M
220 PRINT M
230 END
