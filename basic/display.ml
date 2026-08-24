(* The screen and graphics statements, recorded rather than rendered.

   Several chapter programs draw charts with SCREEN, WIDTH, CLS, KEY OFF,
   LOCATE and LINE. Recording the operations preserves exactly what the
   program asked for, lets a test assert against it, and leaves a renderer as
   a separate project consuming this list rather than a rewrite of the
   evaluator. Nothing here knows what a pixel is. *)

(* A graphics coordinate as PSET/PRESET record it: either absolute (world
   coordinates), or STEP-relative to the LP — the point the last graphics
   operation touched. Resolving [Step] needs that running point, which is
   state only the rasteriser keeps (raster/rasterize.ml's [current]); this
   type just carries the distinction through the display list unresolved. *)
type point = Abs of float * float | Step of float * float

(* Which of KEY's three forms the listing wrote. Kept as its own type rather
   than a bool, since STOP is a third state and not a shade of OFF: it holds
   the interrupt back and remembers the key was pressed, where OFF forbids it
   outright (ref-9801 printed p.87 / PDF p.98). *)
type key_action = Key_on | Key_off | Key_stop

(* CIRCLE's F (ref-9801 printed p.45 / PDF p.56): the interior is filled with
   the palette number written after the F, and with the colour the circle
   itself was drawn in when that is left out. A tile string is the third form
   the page offers and is out of scope ([2] PAINT, spec.md section 3.3), so it
   never reaches here -- the interpreter refuses it at the statement. *)
type circle_fill = Fill_current | Fill_palette of int | Fill_tile of Tile.t

(* What an area is filled with: one palette number, or a tile pattern
   ([2] PAINT, ref-9801 printed p.118-119). PAINT, CIRCLE's F and LINE ,BF
   all take the same choice, so they share the one type rather than each
   growing a tile case of its own. A [Tile.t] is a grid of palette numbers,
   which is the same currency the rest of this list deals in -- decoding the
   string is the interpreter's job, since the manual's Illegal function call
   for one too short is a BASIC error and this list holds none. *)
type paint_style = Solid of int | Tiled of Tile.t

type op =
  (* SCREEN's four slots, each absent when the listing left it out (ref-9801
     printed p.140 / PDF p.151). Carried separately rather than defaulted,
     because "SCREEN ,,0,1" says nothing about the mode and a renderer that
     grows pages must be able to tell that from "SCREEN 0,,0,1". *)
  | Screen of {
      mode : int option;
      switch : int option;
      active : int option;
      display : int option;
    }
  | Width of int * int option (* columns[, rows] *)
  (* CLS's function code, already defaulted to 1 by the interpreter
     (ref-9801 printed p.47 / PDF p.58): 1 clears the text screen alone, 2
     the graphics screen, 3 both. Carried as the code rather than as a
     "clears graphics" flag because the text screen is a real screen this
     project has simply not built yet -- a renderer that grows one needs to
     tell 1 from 3, and a flag would already have thrown that away. *)
  | Cls of int
  (* KEY[(n)] ON|OFF|STOP: the key it names, [None] meaning all ten, and which
     of the three it was (ref-9801 printed p.87 / PDF p.98). Recorded in full
     rather than collapsed to the old "KEY OFF happened" flag, because these
     govern function-key *interrupts* -- a thing this project has not built --
     and a renderer or an event loop that grows them needs to know which key
     and which of ON, OFF and STOP. *)
  | Key of { number : int option; action : key_action }
  (* LOCATE's destination, in character coordinates whose origin (0,0) is the
     screen's top-left corner (ref-9801 printed p.99 / PDF p.110). [column]
     is the manual's X, already defaulted to 0 by the interpreter when the
     slot was left empty. [row] is its Y, and stays optional all the way
     here because its default is not a constant: an omitted Y means "the
     line the cursor is already on", and this list carries no cursor. *)
  | Locate of { column : int; row : int option; cursor : int option }
  (* CONSOLE's four settings (ref-9801 printed p.54 / PDF p.65). Every one
     stays optional: the manual gives none of them a constant default, and an
     omitted slot leaves that setting as it stands, which only something
     holding the current text-screen state can resolve. [scroll_start] and
     [scroll_lines] together bound the scroll window -- the region a text
     clear (CLS 1, or PRINT CHR$(12)) acts on, which is why this op matters
     to a renderer even though it paints nothing itself. *)
  | Console of {
      scroll_start : int option;
      scroll_lines : int option;
      function_keys : int option;
      colour_mode : int option;
    }
  | Line of {
      from_point : point option;
          (* absent means "from the last point referenced"; [Step] is
             relative to it, the same as PSET's and PRESET's *)
      to_point : point;
      colour : int option;
      box : [ `None | `Frame | `Filled ]; (* the trailing ,B / ,BF forms *)
      (* The sixteen-bit line style, for a plain line or a ,B outline: bit
         15 is the first dot drawn and bit 0 the sixteenth, a set bit
         drawing its dot and a clear one leaving the background, the whole
         pattern repeating every sixteen dots (ref-9801 printed p.94-95 /
         PDF p.105-106). Absent means a solid line. Never set together with
         [fill], which belongs to ,BF alone -- the manual forbids a line
         style there. *)
      style : int option;
      (* ,BF's own trailing argument: the palette number or tile pattern its
         interior is filled with, where absent means the colour the rectangle
         was drawn in. *)
      fill : paint_style option;
    }
  (* The POINT statement -- ref-9801 printed p.122. It moves the LP and
     paints nothing: "実際に図形を描いたり、図形に変化を与えることはありません"
     -- it does not draw a figure or alter one. It is in this list rather
     than tracked in the interpreter because the LP lives here, moved by six
     different operations, and a second copy in basic/ would be a second
     definition of the same rule, free to drift from this one. *)
  | Point_lp of { point : point }
  | Pset of { point : point; colour : int option }
      (* absent colour means "the current foreground colour" *)
  | Preset of { point : point; colour : int option }
      (* absent colour means "the current background colour" *)
  | Color of {
      function_code : int option;
          (* text-screen character attribute; this interpreter draws no
             text, so it is recorded but has no rasterised effect *)
      background : int option;
      border : int option; (* outside the viewport; likewise not rasterised *)
      foreground : int option;
    }
  (* [2] COLOR = (<palette number>, <colour code>) -- ref-9801 printed p.51.
     A different statement from [1] COLOR above despite the shared keyword:
     that one sets which palette numbers drawing uses, this one sets which
     colour a palette number displays. Kept as its own op rather than as
     another optional field of [Color] because the two share no argument and
     the manual gives them separate entries.

     It draws nothing. All it does is change how the palette numbers already
     in the framebuffer resolve when the picture is written, which is what
     makes it recolour pixels drawn before it ran. *)
  | Color_palette of { palette : int; code : int }
  (* Bare COLOR, with the equals sign and both arguments omitted: put the
     palette back to its startup mapping. The manual marks this form valid in
     DISK mode only (printed p.51); this interpreter has no such modes, so it
     is accepted unconditionally -- refusing it would need a mode concept
     that does not exist here. *)
  | Color_palette_init
  | Circle of {
      center : point;
      radius : float;
      colour : int option; (* absent means "the current foreground colour" *)
      start_angle : float option;
          (* radians; absent means 0. A negative value means "draw a radius
             line from the centre to this endpoint, using its absolute
             value as the angle" (ref-9801 printed p.45) -- recorded as
             given, sign and all, so raster/ decides the line. *)
      end_angle : float option; (* radians; absent means 2*pi *)
      aspect : float option;
          (* (vertical radius)/(horizontal radius); absent means 1.0, a
             true circle on this interpreter's one supported mode *)
      fill : circle_fill option;
          (* absent means no F was written. With angles present the manual
             makes F draw a *sector* and fill it, so the radius lines close
             the shape even where their angles are positive. *)
    }
  | Paint of {
      point : point;
      area : paint_style option;
          (* absent means "the current foreground colour" *)
      border : int option;
          (* absent means "the same colour as area" -- and when the area is a
             tile rather than one colour, the manual gives no single colour
             for that default to name, so the interpreter resolves it; see
             GFX.PAINT *)
    }
