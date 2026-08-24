(* CRC-32 (every PNG chunk) and Adler-32 (the zlib stream) — the two
   checksums the container formats require, standard-library bit and modulo
   arithmetic only. *)

let crc_table : int array Lazy.t =
  lazy
    (Array.init 256 (fun n ->
         let c = ref n in
         for _ = 1 to 8 do
           if !c land 1 <> 0 then c := 0xedb88320 lxor (!c lsr 1)
           else c := !c lsr 1
         done;
         !c))

let crc32 (data : bytes) : int32 =
  let table = Lazy.force crc_table in
  let c = ref 0xffffffff in
  for i = 0 to Bytes.length data - 1 do
    let byte = Char.code (Bytes.get data i) in
    c := table.((!c lxor byte) land 0xff) lxor (!c lsr 8)
  done;
  Int32.of_int (!c lxor 0xffffffff)

let adler_modulo = 65521

let adler32 (data : bytes) : int32 =
  let a = ref 1 and b = ref 0 in
  for i = 0 to Bytes.length data - 1 do
    let byte = Char.code (Bytes.get data i) in
    a := (!a + byte) mod adler_modulo;
    b := (!b + !a) mod adler_modulo
  done;
  Int32.of_int ((!b lsl 16) lor !a)

(* Both checksums return [int32] so callers cannot forget these are 32-bit
   values; this recovers the unsigned magnitude as a native int for byte
   packing (safe: OCaml's native int is at least 63 bits). *)
let to_unsigned (v : int32) : int = Int32.to_int v land 0xffffffff
