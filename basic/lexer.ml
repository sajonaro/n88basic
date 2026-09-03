(* Whitespace-insensitive, maximal-munch tokenizer. At every letter-starting
   position the scanner reads the whole identifier run first (PROG.VARIABLE-
   NAMES: up to 40 letters/digits/periods, letter-first, plus a trailing
   type-suffix sigil) and only then asks whether that whole run -- never a
   prefix of it -- is a reserved word. A run equal to one is that keyword;
   any other run, including one merely containing a reserved word as a
   substring (`TOTAL` contains `TO`), is an identifier. This is also the
   manual's own rule for recognising a reserved word at all (ref-9801
   printed p.17 / PDF p.30, §8 予約語): a delimiter -- space, quote, "#",
   colon, or other punctuation -- must set it off on both sides. Nothing
   delimits `FOR` from the `I` in `FORI`, so `FORI=1TO10` scans as the
   identifier `FORI`, `=`, `1`, the identifier `TO10` -- not, as classic
   Microsoft BASICs read it, `FOR I = 1 TO 10`; unspaced keyword runs are
   therefore unsupported, per the manual's rule rather than our inference. *)

let is_digit c = c >= '0' && c <= '9'
let is_letter c = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
let is_sigil c = c = '$' || c = '%' || c = '!' || c = '#'
let is_blank c = c = ' ' || c = '\t'
let is_ident_char c = is_letter c || is_digit c || c = '.'

(* PROG.VARIABLE-NAMES: a name is at most 40 characters, not counting a
   trailing type-suffix sigil (checked separately by the caller). *)
let max_name_len = 40

let starts_with_at (s : string) (pos : int) (prefix : string) : bool =
  let n = String.length prefix in
  pos + n <= String.length s
  && String.uppercase_ascii (String.sub s pos n) = prefix

(* The maximal run of identifier characters starting at [start], which the
   caller has already confirmed begins with a letter. Returns the position
   just past everything consumed. *)
let scan_ident_run (s : string) (start : int) : int =
  let n = String.length s in
  let pos = ref start in
  let count = ref 0 in
  while !pos < n && !count < max_name_len && is_ident_char s.[!pos] do
    incr pos;
    incr count
  done;
  !pos

let is_keyword_text (s : string) : bool = List.mem s Token.keywords

(* N88-BASIC accepts relational operators in both character orders: `=<` and
   `<=` are the same operator, likewise `=>` and `>=`. *)
let two_char_puncts = [ "<="; ">="; "<>"; "=>"; "=<"; "><" ]
(* "\\" is integer division (ref-9801 printed p.20, section 10.1). The
   manual prints it as a yen sign, because on a PC-9801 the byte 0x5C is
   drawn that way -- it is the same character as the ASCII backslash a file
   holds today, not a different one. *)
let one_char_puncts = "+-*/^()=<>,;:\\"

(* Scans one unsigned numeric literal starting at [s.[start]], which the
   caller has already confirmed is a digit, or a '.' followed by a digit.
   Returns the position just past everything consumed -- digits, an optional
   "E"/"D" exponent, and an optional "%"/"!"/"#" type suffix -- together with
   the literal's BASIC numeric type and its (unsigned) magnitude.

   The type comes from, in order: an explicit suffix; a "D" exponent
   (double) or "E" exponent (single) (ref-9801 printed p.13-14 / PDF p.26-27,
   sections 5.5-5.6); or, for a literal with neither, the manual's own
   classification by written form (same pages, sections 5.3, 5.5, 5.6): a
   whole number in -32768..32767 is an integer constant; any other real
   literal defaults to single precision if written with 7 digits or fewer,
   double if written with 8 or more. A literal outside the integer range but
   written with no decimal point (e.g. "40000") is not a form the manual
   gives a decimal integer constant, so it falls through to that same
   digit-count rule instead -- a decision of ours where the manual is
   silent, not a stated rule. *)
(* An integer constant written in octal or hexadecimal (ref-9801 printed
   p.13 / PDF p.26, section 5.3). The octal form is a run of 0-7 introduced
   by "&O" -- or by a bare "&", which the manual gives as an equal
   alternative, so &12345 is octal and not a decimal number with a stray
   sigil. The hexadecimal form is a run of 0-F introduced by "&H". The
   manual's ranges are &0..&177777 and &H0..&HFFFF, both of which are
   exactly sixteen bits.

   Those sixteen bits are read as a SIGNED integer, so &HFFFF is -1. The
   manual does not say so outright; it says these are integer constants,
   and it gives ranges reaching 65535, and the integer type it defined two
   pages earlier stops at 32767 -- reading the bit pattern as signed is
   what makes those two statements consistent, and is recorded as our
   reading in spec/clauses.json NUM.RADIX-LITERALS.

   Answers None when what follows the "&" is not a digit of the right base
   at all, leaving the "&" to be lexed as whatever else it may be. *)
let scan_radix (s : string) (start : int) : (int * Numtype.t * float) option =
  let n = String.length s in
  let base, digits_start =
    if start + 1 < n then
      match Char.uppercase_ascii s.[start + 1] with
      | 'H' -> (16, start + 2)
      | 'O' -> (8, start + 2)
      | _ -> (8, start + 1)
    else (8, start + 1)
  in
  let value_of c =
    let c = Char.uppercase_ascii c in
    if is_digit c then Some (Char.code c - Char.code '0')
    else if c >= 'A' && c <= 'F' then Some (Char.code c - Char.code 'A' + 10)
    else None
  in
  let pos = ref digits_start in
  let acc = ref 0 in
  let continue_ = ref true in
  while !continue_ && !pos < n do
    match value_of s.[!pos] with
    | Some v when v < base ->
        (* Masked to sixteen bits as it goes, so a listing with more digits
           than the manual's range allows keeps the low word rather than
           overflowing an OCaml int silently. *)
        acc := (((!acc * base) + v) land 0xFFFF);
        incr pos
    | _ -> continue_ := false
  done;
  if !pos = digits_start then None
  else
    let signed = if !acc >= 0x8000 then !acc - 0x10000 else !acc in
    Some (!pos, Numtype.Int, float_of_int signed)

let scan_number (s : string) (start : int) : int * Numtype.t * float =
  let n = String.length s in
  let pos = ref start in
  let digit_count = ref 0 in
  let has_dot = ref false in
  while !pos < n && (is_digit s.[!pos] || s.[!pos] = '.') do
    (if is_digit s.[!pos] then incr digit_count else has_dot := true);
    incr pos
  done;
  let mantissa_end = !pos in
  let exp_kind =
    if !pos < n && (let c = Char.uppercase_ascii s.[!pos] in c = 'E' || c = 'D') then begin
      let letter = Char.uppercase_ascii s.[!pos] in
      let mark = !pos in
      incr pos;
      if !pos < n && (s.[!pos] = '+' || s.[!pos] = '-') then incr pos;
      let digits_start = !pos in
      while !pos < n && is_digit s.[!pos] do incr pos done;
      if !pos = digits_start then (pos := mark; None) else Some letter
    end
    else None
  in
  let exp_end = !pos in
  let suffix = if exp_kind = None && !pos < n then Numtype.of_suffix s.[!pos] else None in
  (match suffix with Some _ -> incr pos | None -> ());
  (* OCaml's [float_of_string] has no "D" exponent syntax, so a "D" is
     normalized to "e" here; the digits either side of it mean the same
     thing regardless of which letter the source used. *)
  let numeric_text =
    let mantissa = String.sub s start (mantissa_end - start) in
    match exp_kind with
    | None -> mantissa
    | Some _ -> mantissa ^ "e" ^ String.sub s (mantissa_end + 1) (exp_end - mantissa_end - 1)
  in
  let magnitude = float_of_string numeric_text in
  let ntype =
    match (suffix, exp_kind) with
    | Some t, _ -> t
    | None, Some 'E' -> Numtype.Single
    | None, Some 'D' -> Numtype.Double
    | None, Some _ -> assert false (* [exp_kind] is only ever 'E' or 'D' *)
    | None, None ->
        if (not !has_dot) && magnitude >= -32768.0 && magnitude <= 32767.0 then Numtype.Int
        else if !digit_count <= 7 then Numtype.Single
        else Numtype.Double
  in
  (!pos, ntype, magnitude)

(* Parses [text] as one signed numeric literal in full -- every character
   consumed, none left over -- or answers [None] if it is not one. The one
   difference from [scan_number] is the optional leading sign, since a DATA
   item is classified as a whole raw span rather than scanned token-by-token
   the way the rest of a line is (a leading "-" elsewhere is always its own
   Punct token, handled by the parser's unary minus, never part of a Number
   token). *)
let parse_number_literal (text : string) : (Numtype.t * float) option =
  let len = String.length text in
  if len = 0 then None
  else if text.[0] = '&' then
    (* A RADIX constant. ref-9801 printed p.12 SS5.3 classifies an integer
       constant into three forms -- octal, decimal and hexadecimal -- so
       "&H100" is as much a constant as "256" is, and DATA takes constants.
       This branch was missing, and a DATA item like "&HFF" therefore failed
       the digit test below, was classified as the STRING "&HFF", and only
       announced itself when a READ tried to take it as a number, reporting
       Syntax error on the READ line rather than on the DATA line holding it.
       The rest of the language read these literals correctly throughout; only
       DATA's own raw-item scanner did not.

       No sign is accepted here, deliberately: printed p.13 spells the sign
       rule out for the decimal form alone ("a negative integer must be
       preceded by a minus sign"), while the octal and hexadecimal forms are
       defined only as the prefix followed by digits. *)
    match scan_radix text 0 with
    | Some (end_pos, ntype, value) when end_pos = len -> Some (ntype, value)
    | _ -> None
  else
    let start = if text.[0] = '+' || text.[0] = '-' then 1 else 0 in
    if start >= len || not (is_digit text.[start] || (text.[start] = '.' && start + 1 < len && is_digit text.[start + 1]))
    then None
    else
      match scan_number text start with
      | end_pos, ntype, magnitude when end_pos = len ->
          Some (ntype, (if text.[0] = '-' then -.magnitude else magnitude))
      | _ -> None

(* Classify one raw DATA item. A quoted item is always a Str, matching how
   quoted strings elsewhere in this lexer are never reinterpreted as
   numbers regardless of what their contents look like. An unquoted item is
   a Number when it parses as one in full, a Str otherwise. *)
let classify_datum ~quoted (text : string) : Token.kind =
  if quoted then Token.Str text
  else
    match parse_number_literal text with
    | Some (t, f) -> Token.Number (t, f)
    | None -> Token.Str text

let tokenize ~(line : int) (src : string) : Token.t list =
  let n = String.length src in
  let out = ref [] in
  let push kind start_col end_col =
    out := { Token.kind; span = Span.make ~line ~start_col ~end_col } :: !out
  in
  let pos = ref 0 in
  let stop = ref false in
  (* Raw DATA-item scanning, entered once `Keyword "DATA"` has been emitted:
     split the remainder of the line on top-level commas (commas inside a
     quoted item don't split it), trim unquoted items, and classify each.
     Quoted items keep their quotes' contents verbatim, commas included. *)
  let scan_data () =
    while not !stop do
      while !pos < n && is_blank src.[!pos] do incr pos done;
      if !pos >= n then stop := true
      else if src.[!pos] = '"' then begin
        let open_q = !pos in
        let close =
          try String.index_from src (open_q + 1) '"' with Not_found -> n
        in
        let content = String.sub src (open_q + 1) (close - open_q - 1) in
        let consumed_end = min n (close + 1) in
        push (classify_datum ~quoted:true content) open_q consumed_end;
        pos := consumed_end;
        while !pos < n && is_blank src.[!pos] do incr pos done;
        if !pos < n && src.[!pos] = ',' then begin
          push (Token.Punct ",") !pos (!pos + 1);
          incr pos
        end
        else if !pos >= n then stop := true
        else
          (* Anything other than a comma or end of line after a quoted item
             is malformed. Silently dropping the rest of the line would let a
             program run to completion on quietly missing data (DATA.BASIC)
             instead of failing loudly. The offending position is right
             here, so the error carries a token-precise span rather than
             leaving that to a caller who no longer has it. *)
          Error.raise_at
            ~span:(Span.make ~line ~start_col:!pos ~end_col:(!pos + 1))
            0 "Malformed DATA item: expected ',' or end of line after quoted item"
      end
      else begin
        let item_start = !pos in
        let comma = try String.index_from src item_start ',' with Not_found -> n in
        let raw = String.sub src item_start (comma - item_start) in
        let trimmed = String.trim raw in
        let leading_blanks =
          let i = ref 0 in
          while !i < String.length raw && is_blank raw.[!i] do incr i done;
          !i
        in
        let start_col = item_start + leading_blanks in
        let end_col = start_col + String.length trimmed in
        push (classify_datum ~quoted:false trimmed) start_col end_col;
        if comma < n then begin
          push (Token.Punct ",") comma (comma + 1);
          pos := comma + 1
        end
        else begin
          pos := comma;
          stop := true
        end
      end
    done
  in
  while (not !stop) && !pos < n do
    let start = !pos in
    let c = src.[!pos] in
    if is_blank c then incr pos
    else if c = '\'' then begin
      (* ' performs the same function as REM (spec/spec.md PROG.COMMENT-MARK).
         The synthesized Keyword "REM" token's span covers only the
         apostrophe itself — that is the one source character which stands
         for the keyword here. The trailing Str token's span covers
         everything after it, verbatim, through end of line. *)
      push (Token.Keyword "REM") start (start + 1);
      push (Token.Str (String.sub src (start + 1) (n - start - 1))) (start + 1) n;
      stop := true
    end
    else if c = '"' then begin
      (* A quoted string's span covers the whole consumed text, opening and
         closing quote included (or through end of line if unterminated) —
         that is where the token's scan started and stopped, even though the
         Str payload itself holds only the inner content. *)
      let close = try String.index_from src (start + 1) '"' with Not_found -> n in
      let consumed_end = min n (close + 1) in
      push (Token.Str (String.sub src (start + 1) (close - start - 1))) start consumed_end;
      pos := consumed_end
    end
    else if c = '&' && scan_radix src start <> None then begin
      match scan_radix src start with
      | Some (end_pos, ntype, magnitude) ->
          pos := end_pos;
          push (Token.Number (ntype, magnitude)) start end_pos
      | None -> assert false (* guarded by the test above *)
    end
    else if is_digit c || (c = '.' && start + 1 < n && is_digit src.[start + 1]) then begin
      let end_pos, ntype, magnitude = scan_number src start in
      pos := end_pos;
      push (Token.Number (ntype, magnitude)) start end_pos
    end
    else if is_letter c then begin
      (* Maximal munch: the whole identifier run first, then ask whether it
         is a reserved word -- see the module comment. A run whose own
         spelling ends in a sigil (CHR$, STRING$, ...) is checked with the
         sigil included, since that punctuation is part of the keyword
         itself, not a type suffix; only when that fails is the bare run
         (without a trailing suffix that happens to sit next to it, e.g.
         PRINT immediately before "#1") tried on its own. *)
      let base_end = scan_ident_run src start in
      let base = String.uppercase_ascii (String.sub src start (base_end - start)) in
      let has_sigil = base_end < n && is_sigil src.[base_end] in
      let with_sigil = if has_sigil then base ^ String.make 1 src.[base_end] else base in
      (* "GO TO" is GOTO's second spelling, and the manual is exact about the
         gap: one space between GO and TO means exactly the same statement,
         but two or more are explicitly not read as GOTO at all (ref-9801
         printed p.79 / PDF p.90). The delimiter test after "TO" is the same
         reserved-word rule the rest of this scanner obeys (printed p.17), and
         it is what keeps "GO TOTAL" a GO followed by the variable TOTAL
         rather than a jump. *)
      let go_to_end =
        if
          base = "GO" && (not has_sigil)
          && starts_with_at src base_end " TO"
          && (base_end + 3 >= n || not (is_ident_char src.[base_end + 3]))
        then Some (base_end + 3)
        else None
      in
      let keyword =
        match go_to_end with
        | Some kw_end -> Some ("GOTO", kw_end)
        | None ->
            if has_sigil && is_keyword_text with_sigil then Some (with_sigil, base_end + 1)
              (* A reserved word this interpreter does not implement, whose
                 own spelling ends in a sigil, must be kept whole even though
                 its prefix IS an implemented keyword. "INPUT$" would otherwise
                 lex as INPUT followed by a stray "$" and report `Unexpected
                 character '$'`, which reads as a typo -- while INKEY$ and
                 DSKI$, whose prefixes are not keywords, got the message that
                 names the word and says it is not implemented. Two members of
                 one family, two different experiences. Returning None makes
                 the run an Ident, so the parser's reserved-word check answers
                 it. *)
            else if has_sigil && List.mem with_sigil Token.reserved_unimplemented
            then None
            else if is_keyword_text base then Some (base, base_end)
            else None
      in
      match keyword with
      | Some ("REM", kw_end) ->
          (* Keyword REM's span covers just the three letters; the trailing
             Str token's span covers everything after them, verbatim,
             through end of line — mirroring the apostrophe case above. *)
          push (Token.Keyword "REM") start kw_end;
          push (Token.Str (String.sub src kw_end (n - kw_end))) kw_end n;
          stop := true
      | Some ("DATA", kw_end) ->
          push (Token.Keyword "DATA") start kw_end;
          pos := kw_end;
          scan_data ()
      | Some (kw, kw_end) ->
          push (Token.Keyword kw) start kw_end;
          pos := kw_end
      | None ->
          let end_pos = if has_sigil then base_end + 1 else base_end in
          push (Token.Ident with_sigil) start end_pos;
          pos := end_pos
    end
    (* "?" is PRINT's short form, and the manual is explicit that it is the
       same statement rather than a related one: LIST writes it back out as
       PRINT (ref-9801 printed p.125 / PDF p.136). Turning it into the
       keyword here, rather than into a token the parser translates, is what
       makes that true of everything downstream at once -- the parser, the
       checker and the editor all see PRINT and none of them needs to know
       the source said otherwise. *)
    else if c = '?' then begin
      push (Token.Keyword "PRINT") start (start + 1);
      incr pos
    end
    else begin
      match List.find_opt (starts_with_at src start) two_char_puncts with
      | Some p ->
          push (Token.Punct p) start (start + 2);
          pos := start + 2
      | None ->
          if String.contains one_char_puncts c then begin
            push (Token.Punct (String.make 1 c)) start (start + 1);
            incr pos
          end
          else
            (* The bad character's position is right here in scope, so
               the error carries a token-precise span. *)
            Error.raise_at
              ~span:(Span.make ~line ~start_col:start ~end_col:(start + 1))
              0 (Printf.sprintf "Unexpected character %C" c)
    end
  done;
  List.rev !out
