(* Splitting one typed line into INPUT's fields (ref-9801 printed p.82 / PDF
   p.93).

   The manual's rule is short but has two halves that pull against each
   other. Fields are separated by commas -- with several variables, "the
   input data must also be separated by commas, as many as there are
   variables". But a string field may need to contain a comma, or to keep
   spaces at its ends that would otherwise be trimmed, and for that it is
   written in double quotes; the quotes themselves are not part of the value.

   So a comma inside quotes is data, and a comma outside them is a
   separator. That is the whole of what this module decides. It lives apart
   from interp.ml because it is a pure function over a string with its own
   edge cases, and those are worth testing without an interpreter around
   it. *)

(* Only a quote in the FIRST position of a field opens a quoted field: the
   manual describes enclosing the whole string, not embedding quotes in the
   middle of one, so a quote appearing after other characters is data rather
   than the start of an unterminated field. *)
let split (line : string) : string list =
  let n = String.length line in
  let buf = Buffer.create 32 in
  let fields = ref [] in
  let in_quotes = ref false in
  let quoted = ref false in
  (* [at_field_start] is true until this field has taken a character that is
     not leading whitespace -- which is what makes the opening quote
     recognisable, and what lets unquoted fields be trimmed. *)
  let at_field_start = ref true in
  let finish () =
    (* An unquoted field is trimmed at both ends: the manual gives quoting
       as the way to keep spaces that matter, which only means anything if
       spaces are otherwise dropped. A quoted one is kept exactly. *)
    let text = Buffer.contents buf in
    fields := (if !quoted then text else String.trim text) :: !fields;
    Buffer.clear buf;
    quoted := false;
    in_quotes := false;
    at_field_start := true
  in
  for i = 0 to n - 1 do
    let c = line.[i] in
    if !in_quotes then
      if c = '"' then in_quotes := false (* the closing quote is not data *)
      else Buffer.add_char buf c
    else if c = ',' then finish ()
    else if c = '"' && !at_field_start && Buffer.length buf = 0 then begin
      in_quotes := true;
      quoted := true;
      at_field_start := false
    end
    else begin
      if not (c = ' ' || c = '\t') then at_field_start := false;
      Buffer.add_char buf c
    end
  done;
  finish ();
  List.rev !fields
