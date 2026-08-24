(* Tile strings: the pattern PAINT, CIRCLE's F and LINE ,BF fill with
   (ref-9801 printed p.118-119 / PDF p.129-130, the [2] PAINT entry, which
   is where the tile string's meaning is defined -- the other two entries
   only refer to it).

   A tile is always 8 dots wide. Its height is however many rows the string
   describes, and the string is read differently by screen mode: in
   monochrome one character is one row, in the 8-colour mode this
   interpreter targets three characters are one row, and in 16-colour mode
   four. Only the 8-colour reading is implemented here, that being the mode
   spec/spec.md scopes the interpreter to.

   In colour mode the three characters of a row are BIT PLANES, not three
   separate rows: for each of the eight dot columns the three bits are read
   downward as a binary number, and that number is the dot's palette
   number. The manual states the order outright -- the first character of
   the group is the 2^0 digit, the second 2^1, the third 2^2 -- and works
   the example this module is tested against:

       CHR$(&HAA) + CHR$(&H55) + CHR$(&HFF)

       dot        1 2 3 4 5 6 7 8
       &HAA       1 0 1 0 1 0 1 0   <- 2^0
       &H55       0 1 0 1 0 1 0 1   <- 2^1
       &HFF       1 1 1 1 1 1 1 1   <- 2^2
       palette    5 6 5 6 5 6 5 6

   The most significant bit of each byte is the LEFTMOST dot, which the
   manual's monochrome example fixes by drawing &HAA as an alternating row
   beginning with a set dot. That is the same bit order LINE's line style
   uses. *)

(* One tile: [rows] of eight palette numbers each, top row first. *)
type t = { rows : int array array }

let width = 8

(* Characters per row in the 8-colour mode this interpreter targets. The
   manual gives 1 for monochrome and 4 for 16-colour; neither is reachable
   here, since spec/spec.md fixes the interpreter to one 8-colour palette. *)
let chars_per_row = 3

(* Decodes a tile string, or [None] when it is too short to describe even
   one row. The manual is exact about both ends of that: characters left
   over at the END of the string, when the length is not a multiple of
   three, are ignored; and a string shorter than one row's worth is
   "Illegal function call" -- which is the caller's to raise, since this
   module has no BASIC errors in it. *)
let decode (s : string) : t option =
  let usable = String.length s / chars_per_row in
  if usable = 0 then None
  else
    let rows =
      Array.init usable (fun row ->
          let byte i = Char.code s.[(row * chars_per_row) + i] in
          let plane0 = byte 0 and plane1 = byte 1 and plane2 = byte 2 in
          Array.init width (fun dot ->
              (* Bit 7 is dot 0: the leftmost dot is the most significant
                 bit, as the manual's own dot rows are drawn. *)
              let bit b = (b lsr (7 - dot)) land 1 in
              bit plane0 lor (bit plane1 lsl 1) lor (bit plane2 lsl 2)))
    in
    Some { rows }

(* The palette number this tile puts at a screen position. The tile repeats
   across the whole screen from the origin, rather than from wherever a
   particular fill happens to start: the manual describes tiling as a
   property of the pattern rather than of the region, and anchoring to the
   region would make two adjacent fills of one pattern fail to line up.
   That anchoring is our reading -- the page does not address it. *)
let palette_at (t : t) ~(x : int) ~(y : int) : int =
  let height = Array.length t.rows in
  let row = ((y mod height) + height) mod height in
  let col = ((x mod width) + width) mod width in
  t.rows.(row).(col)

let height (t : t) : int = Array.length t.rows
