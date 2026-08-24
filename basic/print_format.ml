let zone_width = 14

let strip_trailing_zeros (s : string) : string =
  if not (String.contains s '.') then s
  else begin
    let n = ref (String.length s) in
    while !n > 0 && s.[!n - 1] = '0' do decr n done;
    if !n > 0 && s.[!n - 1] = '.' then decr n;
    String.sub s 0 !n
  end

let drop_leading_zero (s : string) : string =
  let len = String.length s in
  if len > 1 && s.[0] = '0' && s.[1] = '.' then String.sub s 1 (len - 1)
  else if len > 2 && s.[0] = '-' && s.[1] = '0' && s.[2] = '.' then
    "-" ^ String.sub s 2 (len - 2)
  else s

(* [sig_digits] significant mantissa digits, in an exponent form using
   [exp_char] ("E" for single precision, "D" for double -- ref-9801 printed
   p.13-14 / PDF p.26-27, sections 5.5-5.6). Printf's "%E" always writes
   "E"; the digits either side of it mean the same thing for "D", so only
   the letter itself is swapped in. *)
let scientific (sig_digits : int) (exp_char : char) (x : float) : string =
  let s = Printf.sprintf "%.*E" (sig_digits - 1) x in
  match String.index_opt s 'E' with
  | None -> s
  | Some i ->
      let mantissa = strip_trailing_zeros (String.sub s 0 i) in
      let exponent = String.sub s (i + 1) (String.length s - i - 1) in
      mantissa ^ String.make 1 exp_char ^ exponent

(* Count of digit characters from the first non-zero digit onward, ignoring
   sign, decimal point, and any leading zeros — the integer-part "0." and
   any placeholder zeros at the head of the fraction (e.g. "0.0123456") are
   not significant, but trailing zeros are (100000 is six digits wide). *)
let significant_digit_count (s : string) : int =
  let len = String.length s in
  let is_digit c = c >= '0' && c <= '9' in
  let rec first_nonzero i =
    if i >= len then len
    else if is_digit s.[i] && s.[i] <> '0' then i
    else first_nonzero (i + 1)
  in
  let start = first_nonzero 0 in
  let count = ref 0 in
  for i = start to len - 1 do
    if is_digit s.[i] then incr count
  done;
  !count

let fixed (sig_digits : int) (exp_char : char) (x : float) : string =
  let exponent = int_of_float (Float.floor (Float.log10 (Float.abs x))) in
  (* An exponent this large means the integer part alone has more digits
     than [sig_digits] allows; fixed notation cannot honour that many
     significant digits here, so fall back to scientific rather than print
     extra digits. *)
  if exponent >= sig_digits then scientific sig_digits exp_char x
  else
    let decimals = max 0 (sig_digits - 1 - exponent) in
    let candidate = Printf.sprintf "%.*f" decimals x |> strip_trailing_zeros |> drop_leading_zero in
    (* Rounding can carry into an extra digit (999999.5 rounds to 1000000 at
       0 decimals), silently exceeding the significant-digit budget even
       after trimming. Detect that and fall back to scientific instead of
       printing the extra digit. *)
    if significant_digit_count candidate > sig_digits then scientific sig_digits exp_char x
    else candidate

(* Whether a value is small enough that even an in-budget fixed form gives
   way to exponent form. The BOUNDARY is ours -- printed p.125 states only
   that a value showable in the digit budget without losing precision is
   shown in ordinary decimal form, and says nothing about a floor -- but
   WHERE it is asked mattered and was wrong.

   It used to be "Float.abs x >= 0.01", a comparison against the stored
   float, and it misfired at its own edge: single-precision 0.01 is
   0.00999999977, which is not >= 0.01, so PRINT .01 gave "1E-02" where
   ".01" is required under any reading of the page -- one significant digit
   and two digit characters, comfortably inside a budget of six.

   Asked instead of the RENDERED digits: how many zeros stand between the
   point and the first significant digit. That is the same boundary -- one
   such zero is a hundredth -- but it cannot misfire, because it reads the
   text actually about to be printed rather than a float that rounds just
   below a literal written in decimal. *)
let small_magnitude (sig_digits : int) (exp_char : char) (x : float) : bool =
  let candidate = fixed sig_digits exp_char x in
  let body =
    if String.length candidate > 0 && candidate.[0] = '-' then
      String.sub candidate 1 (String.length candidate - 1)
    else candidate
  in
  (* An integer part is present, so the value is at least 1 -- not small. *)
  if String.length body = 0 || body.[0] <> '.' then false
  else begin
    let i = ref 1 in
    while !i < String.length body && body.[!i] = '0' do incr i done;
    (* One zero after the point is a hundredth, which stays in fixed form;
       two or more is smaller than that and takes exponent form. *)
    !i - 1 > 1
  end

(* The body of a printed number, before the leading sign column and
   trailing space [format_number] adds -- driven by [t], per NUM.DISPLAY:

   - Integer never uses exponent form (ref-9801 printed p.12 / PDF p.25:
     every integer constant is a whole number in -32768..32767, far short of
     needing one) and carries no decimal point.
   - Single precision switches to fixed (ordinary decimal) notation once it
     fits within 6 significant digits without losing precision, and to
     scientific ("E") notation otherwise (ref-9801 printed p.125 / PDF
     p.136, the PRINT entry's own note).
   - Double precision follows the identical rule at 16 significant digits,
     with "D" in place of "E" (same source, extended by the same note to
     double precision explicitly).

   The 0.01 lower threshold below which even an in-budget fixed form gives
   way to scientific is not stated anywhere found in the manual; it is
   carried over unchanged from this interpreter's pre-existing behaviour
   for very small magnitudes, applied to both single and double precision
   alike -- a decision of ours, not a manual rule. *)
let format_body (t : Numtype.t) (x : float) : string =
  if x = 0.0 then "0"
  else
    match t with
    | Numtype.Int -> Printf.sprintf "%.0f" x
    | Numtype.Single -> if small_magnitude 6 'E' x then scientific 6 'E' x else fixed 6 'E' x
    | Numtype.Double -> if small_magnitude 16 'D' x then scientific 16 'D' x else fixed 16 'D' x

(* A leading column for the sign (space for non-negative, "-" for negative)
   and a trailing space follow every printed number, regardless of type
   (ref-9801 printed p.125 / PDF p.136, the PRINT entry: "a number is always
   followed by a space; before it sits a column reserved for the sign,
   blank when positive"). No trailing "!"/"#" is ever added -- the manual's
   own PRINT examples never show one on a real number's output, only on a
   literal in source text. *)
let format_number (t : Numtype.t) (x : float) : string =
  let body = format_body t x in
  let sign = if x >= 0.0 then " " else "" in
  sign ^ body ^ " "

(* [row] counts newlines this writer has put, 0 at the top -- what CSRLIN
   reads (spec/spec.md PRINT.CSRLIN). It does not know about LOCATE, which
   this interpreter parses but does not wire to any cursor state; a program
   that LOCATEs and then reads CSRLIN will not see the move reflected here. *)
type writer = {
  emit : string -> unit;
  mutable col : int;
  mutable row : int;
  (* Columns per line, which WIDTH sets (ref-9801 printed p.158-159 / PDF
     p.169-170) and which TAB and SPC divide by. 80 to begin with: the manual
     gives WIDTH's legal values as 40 or 80 but does not say which the machine
     starts in, so the wider of the two is this interpreter's choice, made
     here rather than left implicit. *)
  mutable width : int;
}

let default_width = 80

let make ?(width = default_width) (emit : string -> unit) : writer =
  { emit; col = 0; row = 0; width }

let column (w : writer) : int = w.col
let row (w : writer) : int = w.row
let width (w : writer) : int = w.width
let set_width (w : writer) (n : int) : unit = w.width <- n

(* Emit [s] a character at a time, breaking the line whenever the cursor
   reaches the right-hand column. The PRINT entry's own note takes the break
   for granted -- it describes a number that "would run over onto the next
   line" as the thing to be avoided by moving down first, which only makes
   sense on a screen that runs over by itself (printed p.125 / PDF p.136). *)
let put (w : writer) (s : string) : unit =
  String.iter
    (fun c ->
      if c = '\n' then begin
        w.emit "\n";
        w.col <- 0;
        w.row <- w.row + 1
      end
      else begin
        if w.col >= w.width then begin
          w.emit "\n";
          w.col <- 0;
          w.row <- w.row + 1
        end;
        w.emit (String.make 1 c);
        w.col <- w.col + 1
      end)
    s

let newline (w : writer) : unit = put w "\n"

(* Write [s] without letting the line break fall inside it: if what is left of
   the line cannot hold the whole of it, start a fresh line first. This is the
   PRINT entry's stated rule, and the manual states it of a *number* -- 数値 --
   so [print_value] applies it to numbers and not to strings. Extending it to
   strings would be a guess, and a string longer than the whole width has to
   break somewhere regardless. *)
let put_unbroken (w : writer) (s : string) : unit =
  if w.col > 0 && w.col + String.length s > w.width then newline w;
  put w s

let tab_to_zone (w : writer) : unit =
  let target = ((w.col / zone_width) + 1) * zone_width in
  put w (String.make (target - w.col) ' ')
