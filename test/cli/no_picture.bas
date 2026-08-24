10 REM Records display ops but paints nothing: WIDTH, CONSOLE, COLOR and
20 REM LOCATE are all carried on the display list and none puts ink down.
30 CONSOLE 0,25,0,1
40 WIDTH 80,25
50 COLOR 7,0,0,7
60 LOCATE 5,5
70 PRINT "text only"
80 END
