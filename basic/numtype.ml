(* The three numeric types N88-BASIC(86) distinguishes for every numeric
   constant, variable, and expression result (ref-9801 printed p.12-14 / PDF
   p.25-27, sections 5.2-5.6 "数値型定数"): integer, single-precision real,
   and double-precision real -- never one undifferentiated "number", which is
   what this interpreter had before this module existed. *)
type t = Int | Single | Double

(* When two differently-typed operands meet in one arithmetic expression, the
   result takes the more precise operand's type (ref-9801 printed p.18 / PDF
   p.31: mixing numbers of different precision converts the less precise one
   to match the more precise one before the operation runs). This ordering is
   exactly that precision ordering, Int being least precise. *)
let widen (a : t) (b : t) : t =
  match (a, b) with
  | Double, _ | _, Double -> Double
  | Single, _ | _, Single -> Single
  | Int, Int -> Int

(* The one type-declaration character a variable name or numeric literal can
   end in (ref-9801 printed p.14 / PDF p.27, section 6.2 "変数の型"):
   "%" for integer, "!" for single precision, "#" for double precision. *)
let of_suffix : char -> t option = function
  | '%' -> Some Int
  | '!' -> Some Single
  | '#' -> Some Double
  | _ -> None

let suffix_char : t -> char = function Int -> '%' | Single -> '!' | Double -> '#'
