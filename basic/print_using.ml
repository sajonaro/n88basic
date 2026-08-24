(* PRINT USING / LPRINT USING formatting (spec/spec.md PRINT.USING), the whole
   format language of ref-9801 printed pp.128-129 / PDF pp.139-140.

   The template is a sequence of fields and literal text. Numeric fields are
   "#" digit positions with an optional "." and fraction, right-justified and
   rounded half-up; they may carry a sign character, an asterisk fill or a yen
   sign in front, "," among the digits to group by thousands, and "^^^^" behind
   to switch to exponential form. String fields are "!", "&...&" and "@". A "_"
   makes the next character literal, and a number too wide for its field prints
   whole behind a "%" rather than being cut down.

   Two readings are this interpreter's rather than the manual's, and both are
   marked where they are made: the manual anchors the prefixes and the sign to
   the head of the *format string*, but its own worked example puts a yen pair
   mid-string, so they are read as belonging to the field; and the manual names
   exponential form without describing it, so the mantissa/exponent split here
   is ours. *)

(* The string fields, all three from ref-9801 printed p.128 / PDF p.139:
   "!" is the first character alone, "&" with n spaces before a closing "&"
   is a left-justified field of n+2 characters (the two "&" count towards the
   width), and "@" is the whole string however long it is. *)
type str_field = First_char | Fixed of int | Whole

(* Where a numeric field's sign goes, from the same page. A leading "+" shows
   the sign in front and a trailing "+" behind; a trailing "-" marks negatives
   only and leaves a blank column for positives, which is what keeps a column
   of figures aligned. With none of them the minus sign, when there is one,
   has to live inside the digit positions instead. *)
type sign = No_sign | Leading | Trailing_plus | Trailing_minus

(* The two field prefixes of ref-9801 printed p.129 / PDF p.140. "**" reserves
   two digit positions and fills the blank left of the number with asterisks;
   "¥¥" reserves two of which one carries the sign itself; "**¥" reserves three
   on the same terms and does both jobs. [currency] is the spelling the format
   string used, because the yen sign is 0x5C on the machine -- the byte a
   modern keyboard types as a backslash -- so a listing may write either, and
   echoing back what was written beats picking one for the author. Either way
   it occupies a single column, as it does on the screen it was written for. *)
type prefix = { reserved : int; asterisk : bool; currency : string option }

let no_prefix = { reserved = 0; asterisk = false; currency = None }

type segment =
  | Literal of string
  | Field of {
      int_digits : int;
      frac_digits : int option;
      sign : sign;
      prefix : prefix;
      (* How many "," sat among the "#" (ref-9801 printed p.129 / PDF p.140).
         Any at all turns on grouping every three digits, and each one carries
         a column of its own, so "##,###" is six columns wide. A "," to the
         right of the point is a different rule and never reaches here: it
         falls outside the field and prints as the ordinary character it is,
         which is precisely the trailing comma without grouping the manual
         asks for. *)
      commas : int;
      (* "^^^^" after the digits (ref-9801 printed p.129 / PDF p.140). The
         manual says only that it switches the field to exponential form and
         stops there, so the shape below is this interpreter's reading, not
         the manual's rule: the mantissa is normalised to fill the "#" ahead
         of the point, and the four carets are the four columns "E+nn" takes. *)
      exponential : bool;
    }
  | Str_field of str_field

(* Parse the format string once into literal runs and numeric fields. A run
   of '#' with an optional '.' and further '#' is one field; every other
   character, including a '#' that appears mid-run of ordinary text, is
   literal except that a '#' itself always starts a field. *)
let parse (fmt : string) : segment list =
  let len = String.length fmt in
  let segments = ref [] in
  let buf = Buffer.create 16 in
  let flush_literal () =
    if Buffer.length buf > 0 then begin
      segments := Literal (Buffer.contents buf) :: !segments;
      Buffer.clear buf
    end
  in
  let i = ref 0 in
  (* The yen sign, in either spelling: the 0x5C byte the machine shows as ¥,
     or the UTF-8 ¥ a listing typed on a modern editor would carry. *)
  let yen_at at =
    if at < len && fmt.[at] = '\\' then Some ("\\", 1)
    else if at + 1 < len && fmt.[at] = '\xc2' && fmt.[at + 1] = '\xa5' then
      Some ("\xc2\xa5", 2)
    else None
  in
  (* A prefix at [at], if there is one: "**¥" is tried before "**" so that the
     longer of the two wins. Returns where the digits start. *)
  let prefix_at at =
    let stars = at + 1 < len && fmt.[at] = '*' && fmt.[at + 1] = '*' in
    let after_stars = if stars then at + 2 else at in
    match (stars, yen_at after_stars) with
    | true, Some (y, n) -> Some ({ reserved = 3; asterisk = true; currency = Some y }, after_stars + n)
    | true, None -> Some ({ reserved = 2; asterisk = true; currency = None }, after_stars)
    | false, Some (y, n) -> (
        match yen_at (at + n) with
        | Some (_, n2) ->
            Some ({ reserved = 2; asterisk = false; currency = Some y }, at + n + n2)
        | None -> None)
    | false, None -> None
  in
  (* A numeric field begins at a '#', or at a prefix with digits behind it. The
     sign characters are only control characters when they sit against such a
     field, which is what tells a signing '+' from a '+' that is just a
     character. *)
  let field_start at =
    match prefix_at at with
    | Some (p, next) when next < len && fmt.[next] = '#' -> Some (p, next)
    | _ -> if at < len && fmt.[at] = '#' then Some (no_prefix, at) else None
  in
  let starts_numeric_field at = field_start at <> None in
  (* Read the field at [!i], whose leading sign (if any) has been consumed
     already, and take any trailing sign with it. *)
  let parse_numeric_field ?(prefix = no_prefix) (sign : sign) =
    let int_digits = ref 0 and commas = ref 0 in
    while !i < len && (fmt.[!i] = '#' || fmt.[!i] = ',') do
      if fmt.[!i] = '#' then incr int_digits else incr commas;
      incr i
    done;
    let frac_digits =
      if !i < len && fmt.[!i] = '.' then begin
        incr i;
        let count = ref 0 in
        while !i < len && fmt.[!i] = '#' do
          incr count;
          incr i
        done;
        Some !count
      end
      else None
    in
    (* Exactly four carets are the control sequence; a shorter run is text. *)
    let exponential =
      !i + 3 < len
      && fmt.[!i] = '^' && fmt.[!i + 1] = '^' && fmt.[!i + 2] = '^'
      && fmt.[!i + 3] = '^'
    in
    if exponential then i := !i + 4;
    let sign =
      if sign <> No_sign then sign
      else if !i < len && fmt.[!i] = '+' then begin
        incr i;
        Trailing_plus
      end
      else if !i < len && fmt.[!i] = '-' then begin
        incr i;
        Trailing_minus
      end
      else No_sign
    in
    segments :=
      Field
        { int_digits = !int_digits; frac_digits; sign; prefix; commas = !commas;
          exponential }
      :: !segments
  in
  (* Move to the digits of the field starting at [!i] and read it. *)
  let parse_field_at start sign =
    match field_start start with
    | Some (prefix, digits_at) ->
        i := digits_at;
        parse_numeric_field ~prefix sign
    | None -> assert false
  in
  while !i < len do
    if starts_numeric_field !i then begin
      flush_literal ();
      parse_field_at !i No_sign
    end
    (* A '+' directly against a field signs it. Two in a row leave the outer
       one with no field to sign, so it stays an ordinary character -- which
       is exactly the manual's rule for the extras. *)
    else if fmt.[!i] = '+' && starts_numeric_field (!i + 1) then begin
      flush_literal ();
      incr i;
      parse_field_at !i Leading
    end
    else if fmt.[!i] = '!' then begin
      flush_literal ();
      incr i;
      segments := Str_field First_char :: !segments
    end
    else if fmt.[!i] = '@' then begin
      flush_literal ();
      incr i;
      segments := Str_field Whole :: !segments
    end
    else if fmt.[!i] = '&' then begin
      (* "&" opens a fixed field only if a closing "&" follows with nothing
         but spaces between; a lone "&" is an ordinary character, since the
         manual gives it no meaning on its own. *)
      let j = ref (!i + 1) in
      while !j < len && fmt.[!j] = ' ' do
        incr j
      done;
      if !j < len && fmt.[!j] = '&' then begin
        flush_literal ();
        segments := Str_field (Fixed (!j - !i + 1)) :: !segments;
        i := !j + 1
      end
      else begin
        Buffer.add_char buf '&';
        incr i
      end
    end
    (* "_" strips the control meaning from exactly one following character
       (ref-9801 printed p.129 / PDF p.140), so it goes straight to the literal
       buffer without ever being looked at as a field. A "_" at the very end of
       the format has nothing to escape and is itself the literal. *)
    else if fmt.[!i] = '_' then begin
      if !i + 1 < len then begin
        Buffer.add_char buf fmt.[!i + 1];
        i := !i + 2
      end
      else begin
        Buffer.add_char buf '_';
        incr i
      end
    end
    else begin
      Buffer.add_char buf fmt.[!i];
      incr i
    end
  done;
  flush_literal ();
  List.rev !segments

(* Round half-up, not half-to-even: Printf's "%.*f" rounds half-to-even on
   some inputs, which would silently break the dialect's rounding rule.
   Float.round ties away from zero, which is exactly "half-up" for the
   non-negative quantities PRINT USING formats in this chapter. *)
let round_half_up (x : float) (decimals : int) : float =
  let scale = 10. ** float_of_int decimals in
  Float.round (x *. scale) /. scale

(* Group a run of digits every three from the right. Only the digits: a minus
   that had nowhere else to go still leads, and the fraction is untouched. *)
let group_thousands (s : string) : string =
  let lead = if String.length s > 0 && s.[0] = '-' then 1 else 0 in
  let digits = String.sub s lead (String.length s - lead) in
  let n = String.length digits in
  let buf = Buffer.create (n + (n / 3)) in
  String.iteri
    (fun k c ->
      if k > 0 && (n - k) mod 3 = 0 then Buffer.add_char buf ',';
      Buffer.add_char buf c)
    digits;
  String.sub s 0 lead ^ Buffer.contents buf

(* Split [x] into a mantissa carrying [int_digits] digits ahead of its point
   and the matching power of ten, rounding the mantissa to [decimals] first so
   that a carry out of the rounding (9.99 to 10.0 at two digits) moves the
   exponent rather than widening the mantissa. Zero has no exponent to find and
   is given 0, which prints as E+00. *)
let normalise_exponential (x : float) (int_digits : int) (decimals : int) :
    float * int =
  if x = 0.0 then (0.0, 0)
  else begin
    let e = ref (int_of_float (Float.floor (Float.log10 (Float.abs x))) - int_digits + 1) in
    let mant () = x /. (10. ** float_of_int !e) in
    (* log10 is not exact at the decade boundaries, so settle the range by
       looking at the mantissa itself rather than trusting the logarithm. *)
    let low = 10. ** float_of_int (int_digits - 1) and high = 10. ** float_of_int int_digits in
    while Float.abs (mant ()) >= high do
      incr e
    done;
    while Float.abs (mant ()) < low do
      decr e
    done;
    let scale = 10. ** float_of_int decimals in
    let rounded = Float.round (mant () *. scale) /. scale in
    if Float.abs rounded >= high then (rounded /. 10., !e + 1) else (rounded, !e)
  end

let render_field (int_digits : int) (frac_digits : int option) (sign : sign)
    (prefix : prefix) (commas : int) (exponential : bool) (value : Value.t) :
    string =
  let x =
    match value with
    | Value.Num (_, n) -> n
    | Value.Str s -> invalid_arg (Printf.sprintf "Print_using.format: string %S given to a numeric # field" s)
  in
  let decimals = Option.value frac_digits ~default:0 in
  (* With a sign character the digits are formatted from the magnitude, since
     the sign has a column of its own outside them; with none, the minus has
     nowhere to go but among the digit positions. *)
  let negative = x < 0.0 in
  let magnitude = if sign = No_sign then x else Float.abs x in
  (* In exponential form the digits are the mantissa and the exponent is a
     four-column suffix that no padding may come between. *)
  let exponent_suffix =
    if not exponential then ""
    else
      let _, e = normalise_exponential magnitude int_digits decimals in
      Printf.sprintf "E%c%02d" (if e < 0 then '-' else '+') (abs e)
  in
  let rounded =
    if exponential then fst (normalise_exponential magnitude int_digits decimals)
    else round_half_up magnitude decimals
  in
  let body = Printf.sprintf "%.*f" decimals rounded in
  let body =
    if commas = 0 then body
    else
      match String.index_opt body '.' with
      | None -> group_thousands body
      | Some at ->
          group_thousands (String.sub body 0 at)
          ^ String.sub body at (String.length body - at)
  in
  (* The prefix's reserved columns widen the field, but the currency sign
     spends one of them on itself, so it buys only [reserved - 1] digits. *)
  let currency_width = match prefix.currency with None -> 0 | Some _ -> 1 in
  let width =
    int_digits + commas + prefix.reserved - currency_width
    + (match frac_digits with None -> 0 | Some d -> 1 + d)
  in
  let pad = width - String.length body in
  let pad_char = if prefix.asterisk then '*' else ' ' in
  let currency = match prefix.currency with None -> "" | Some y -> y in
  (* Too many digits for the field: the manual does not truncate, it prints the
     number whole with a "%" immediately in front, so a line that will not fit
     is visibly wrong instead of quietly wrong. Because the check is made after
     rounding, it also catches the case the manual calls out separately, where
     it is the rounding itself that pushes the number over -- 99.96 into "##.#"
     becomes 100.0, which no longer fits.

     The manual puts the currency sign directly against the number, so it goes
     inside the padding rather than at the field's left edge; that is why the
     fill is emitted first, and why an overflow keeps it against the digits. *)
  let digits =
    if pad < 0 then "%" ^ currency ^ body
    else (if pad > 0 then String.make pad pad_char else "") ^ currency ^ body
  in
  let digits = digits ^ exponent_suffix in
  match sign with
  | No_sign -> digits
  | Leading -> (if negative then "-" else "+") ^ digits
  | Trailing_plus -> digits ^ if negative then "-" else "+"
  | Trailing_minus -> digits ^ if negative then "-" else " "

(* Raised when a string field is asked to edit a string containing a
   multi-byte character. ref-9801 printed p.128 sets a note directly under the
   string-format characters -- 日本語を含む文字列を編集することはできません, a
   string containing Japanese cannot be edited -- 編集 being the same verb the
   entry's own 機能 line uses for what PRINT USING does.

   Its own exception rather than [Invalid_argument], which this module already
   raises for a number handed to a string field and which the interpreter
   turns into "Type mismatch": a different fault deserves a different message. *)
exception Japanese_in_string_field

(* A byte at or above 0x80 opens a multi-byte character in either encoding
   that matters here, so this tests for "contains Japanese" without decoding.
   The manual means Shift-JIS; source files here are UTF-8. Either way the
   prohibition is about a character these byte-counting fields would cut in
   half, and either way such a character has a high byte. *)
let has_multibyte (s : string) : bool =
  let rec go i = i < String.length s && (Char.code s.[i] >= 0x80 || go (i + 1)) in
  go 0

let render_str_field (field : str_field) (value : Value.t) : string =
  let s =
    match value with
    | Value.Str s -> s
    | Value.Num _ ->
        invalid_arg "Print_using.format: a number was given to a string field"
  in
  (* Refused for EVERY string field, including "@", which alone could not
     corrupt anything -- it copies the string whole. The page draws no
     exception, and 編集 is what its 機能 line calls all three, so taking
     one would be our rule rather than its. Recorded on PRINT.USING so a
     later reader can revisit it with the reasoning in view. *)
  if has_multibyte s then raise Japanese_in_string_field;
  match field with
  | Whole -> s
  | First_char -> if s = "" then "" else String.sub s 0 1
  | Fixed width ->
      if String.length s >= width then String.sub s 0 width
      else s ^ String.make (width - String.length s) ' '

(* The format string is consumed once per pass over the values, and reused from
   the start while values remain: `PRINT USING "###";1;2;3` prints all three
   through the one field, as the dialect does, rather than dropping the tail.

   The two ends of that rule:
   - a format with no field at all can never consume a value, so it is emitted
     once and the reuse stops — otherwise it would loop forever;
   - when the values run out at a field, output stops there. Carrying on would
     emit the text around a field that silently produced nothing. Literal text
     *before* a satisfied field's end still prints, which is what leaves the
     trailing prose of "X = ##.# UNITS" in place. *)
let format (fmt : string) (values : Value.t list) : string =
  let segments = parse fmt in
  let consumes_a_value =
    List.exists
      (function Field _ | Str_field _ -> true | Literal _ -> false)
      segments
  in
  let buf = Buffer.create (String.length fmt) in
  let rec go remaining values =
    match remaining with
    | [] -> if values <> [] && consumes_a_value then go segments values
    | Literal s :: rest ->
        Buffer.add_string buf s;
        go rest values
    | Field { int_digits; frac_digits; sign; prefix; commas; exponential } :: rest -> (
        match values with
        | [] -> ()
        | v :: values_rest ->
            Buffer.add_string buf (render_field int_digits frac_digits sign prefix commas exponential v);
            go rest values_rest)
    (* "@" is the one field the manual says what to do with when the values
       have run out: the leftover ones are ignored (printed p.128). Ignored,
       not fatal to the rest of the line -- so the walk carries on, unlike
       every other starved field, where the manual is silent and this
       interpreter keeps its existing stop-here behaviour. *)
    | Str_field Whole :: rest when values = [] -> go rest values
    | Str_field field :: rest -> (
        match values with
        | [] -> ()
        | v :: values_rest ->
            Buffer.add_string buf (render_str_field field v);
            go rest values_rest)
  in
  go segments values;
  Buffer.contents buf
