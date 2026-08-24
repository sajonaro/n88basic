10 REM GFX.PAINT (partial): fills the region containing the given point
20 REM outward until the border colour is met. An omitted border
30 REM defaults to the area colour, so an outline drawn in the fill
40 REM colour still stops the flood correctly.
50 SCREEN 3
60 CLS
70 LINE (50,50)-(150,150),2,B
80 PAINT (100,100),4,2
90 LINE (250,50)-(350,150),6,B
100 PAINT (300,100),6
110 END
