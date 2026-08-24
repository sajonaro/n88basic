(* A runtime value: a number tagged with which of the three BASIC numeric
   types it carries (basic/numtype.ml), or a string. The float underneath a
   [Num] is always an OCaml double -- this interpreter has no 32-bit float
   storage -- but [coerce] below keeps its magnitude and precision within
   whatever [Numtype.t] it is tagged with, so a [Single] never silently
   carries more than single precision can represent. *)
type t = Num of Numtype.t * float | Str of string

let is_string_name (name : string) : bool =
  String.length name > 0 && name.[String.length name - 1] = '$'

(* The integer range (ref-9801 printed p.12 / PDF p.25, section 5.3): every
   decimal integer constant, and the only range CINT and an integer
   assignment accept. *)
let int_lo = -32768.0
let int_hi = 32767.0

(* The single- and double-precision magnitude bounds (ref-9801 printed p.13
   and p.14 / PDF p.26 and p.27, sections 5.5 and 5.6). The manual states
   these as the range of a *constant*; this interpreter also enforces them as
   the overflow bound for any single- or double-precision value, constant or
   computed, since nothing in the manual suggests a computed value can hold
   more than a constant of the same type could -- a decision of ours where
   the manual is silent, not a stated rule. *)
let single_bound = 1.70141e38
let double_bound = 1.701411834604692e38

(* 四捨五入: round to the nearest integer, ties away from zero. Used
   everywhere the manual says a fractional value is rounded rather than
   truncated on its way to becoming an integer -- CINT, assigning a real to
   an integer variable, and a "%"-suffixed numeric literal (ref-9801 printed
   p.18 / PDF p.31, rule 4; printed p.44 / PDF p.55). [Float.round] already
   rounds ties away from zero, matching 四捨五入 exactly. *)
let round_half_away (x : float) : float = Float.round x

(* Round-trips [x] through a 32-bit IEEE-754 float, which is what "narrow to
   single precision" means bit-for-bit -- about 6-7 significant decimal
   digits -- rather than an approximation by decimal-digit truncation
   (spec/spec.md NUM.CSNG). *)
let narrow_to_single (x : float) : float = Int32.float_of_bits (Int32.bits_of_float x)

(* Converts [x] to the representation [t] can hold, raising "Overflow (OV)"
   (spec/errors.json #6) if [x] does not fit -- the manual's own outcome for
   every one of these three conversions (ref-9801 printed p.18 / PDF p.31
   rule 4 for integer; printed p.44 and p.57 / PDF p.55 and p.68 for CINT and
   CSNG, which this shares its bounds and rounding with). Double never
   overflows here since every value already lives in an OCaml double. *)
let coerce (t : Numtype.t) (x : float) : float =
  match t with
  | Numtype.Int ->
      let r = round_half_away x in
      if r < int_lo || r > int_hi then Error.raise_at 0 "Overflow (OV)" else r
  | Numtype.Single ->
      if Float.abs x > single_bound then Error.raise_at 0 "Overflow (OV)"
      else narrow_to_single x
  | Numtype.Double -> if Float.abs x > double_bound then Error.raise_at 0 "Overflow (OV)" else x

(* The smart constructor every numeric value in this interpreter should be
   built through: it tags [x] with [t] and brings its representation within
   what that type can hold, the same way every assignment and conversion the
   manual describes does (NUM.COERCION, NUM.OVERFLOW). *)
let make (t : Numtype.t) (x : float) : t = Num (t, coerce t x)

(* The zero value a variable holds before it is ever assigned, for a
   variable already known to be a string -- see basic/env.ml's
   [default_value] for the numeric case, which additionally needs to know
   the variable's declared numeric type (from a suffix or a DEFxxx range),
   information only Env carries. *)
let default_str : t = Str ""
