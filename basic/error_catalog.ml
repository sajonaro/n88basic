(* The fixed table of N88-BASIC(86) error numbers and messages
   (spec/errors.json, ref-9801 printed p.181-187 / PDF p.190-196), used only
   to answer two questions basic/interp.ml cannot answer on its own:

   - ERR's numeric code, for an error trapped by ON ERROR GOTO whose raise
     site did not already attach one via Error.t's [code] (see error.ml) --
     recovered here from the message text instead.
   - ERROR <n>'s message, for a defined <n>.

   Pure data and pure lookups, no I/O — kept in sync with spec/errors.json by
   hand, since the two describe the same 52 facts for different readers (a
   human/spec-checker there, this interpreter here). *)

let table : (int * string) list =
  [
    (1, "NEXT without FOR");
    (2, "Syntax error");
    (3, "RETURN without GOSUB");
    (4, "Out of DATA");
    (5, "Illegal function call");
    (6, "Overflow (OV)");
    (7, "Out of memory");
    (8, "Undefined line number");
    (9, "Subscript out of range");
    (10, "Duplicate Difinition");
    (11, "Division by Zero (/0)");
    (12, "Illegal direct");
    (13, "Type mismatch");
    (14, "Out of string space");
    (15, "String too long");
    (16, "String formula too complex");
    (17, "Can't continue");
    (18, "Undefined user function");
    (19, "No RESUME");
    (20, "RESUME without error");
    (21, "Unprintable error");
    (22, "Missing operand");
    (23, "Line buffer overflow");
    (24, "Unprintable error");
    (25, "Unprintable error");
    (26, "FOR without NEXT");
    (27, "Tape read error");
    (28, "Unprintable error");
    (29, "WHILE without WEND");
    (30, "WEND without WHILE");
    (31, "Duplicate label");
    (32, "Undefined label");
    (33, "Feature not available");
    (50, "FIELD overflow");
    (52, "Bad file number");
    (53, "File not found");
    (54, "File already open");
    (55, "Input past end");
    (56, "Bad file name");
    (57, "Direct statement in file");
    (59, "Sequential I/O only");
    (60, "File not open");
    (61, "File write protected");
    (62, "Disk offline");
    (64, "Disk I/O error");
    (65, "File already exist");
    (68, "Disk full");
    (69, "Bad allocation table");
    (70, "Bad drive number");
    (71, "Bad track/sector");
    (73, "Rename across disks");
    (74, "Illegal operation");
  ]

(* A handful of messages this interpreter actually raises differ cosmetically
   from the manual's own wording for the same error -- e.g. this interpreter's
   "Division by zero" for error 11, whose manual text (and [table] entry
   above) is "Division by Zero (/0)". Fixing that wording is out of scope for
   this task (it is unrelated existing behaviour many tests already pin), so
   this alias list maps what the interpreter actually says to the number it
   means, for ERR's sake only. *)
let aliases : (string * int) list = [ ("Division by zero", 11) ]

let number_of_message (msg : string) : int option =
  match List.find_opt (fun (_, m) -> m = msg) table with
  | Some (n, _) -> Some n
  | None -> List.assoc_opt msg aliases

let message_of_number (n : int) : string option =
  List.find_map (fun (num, m) -> if num = n then Some m else None) table

(* The message ERROR <n> raises for a code the manual does not assign a
   message of its own -- what its appendix heads "Unprintable error" (the
   printed codes 21, 24, 25 and 28, "and others" per that heading;
   spec/errors.json #21's note). ERROR can raise any code in this bucket
   deliberately, "which leaves it free for a program's own error
   conditions" (same note) -- so this is not a fallback for an unhandled
   case, it is the manual's own designed behaviour for an undefined code. *)
let unprintable = "Unprintable error"
