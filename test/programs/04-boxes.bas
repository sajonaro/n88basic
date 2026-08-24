10 REM LINE's box forms. ,B outlines the rectangle whose diagonal the two
20 REM points give; ,BF fills it. A style mask is allowed with B and not
30 REM with BF.
40 CLS 3
50 LINE(10,20)-(110,120),5,B
60 LINE(130,20)-(230,120),5,B,&HAAAA
70 LINE(250,20)-(350,120),5,BF
80 REM An outline is hollow and a fill is not; the centre of each says so.
90 PRINT "outline centre (want 0):";POINT(60,70)
100 PRINT "outline edge   (want 5):";POINT(10,70)
110 PRINT "filled centre  (want 5):";POINT(300,70)
