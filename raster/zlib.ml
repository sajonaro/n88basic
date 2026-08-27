(* A zlib stream (RFC 1950) carrying deflate (RFC 1951) with FIXED HUFFMAN
   codes and LZ77 matching. No external library: PNG writing is part of this
   project's own surface (design SS7), so the compressor is here too.

   IT USED TO EMIT STORED BLOCKS ONLY, and the reason recorded for that was
   "nothing that could fail to cross a js_of_ocaml boundary". That ground did
   not hold: the JavaScript bundle is built from n88lsp, which depends on
   n88basic alone -- raster/ is never compiled to JavaScript, so nothing here
   has ever crossed that boundary. The cost was severe and entirely paid by
   users: a 640x400 drawing came out at 768,544 bytes for an image whose
   content compresses to about 1,700. Roughly 450x, on every PNG the
   interpreter has ever written.

   Fixed Huffman rather than dynamic: it needs no code-length tables in the
   stream and no table construction here, and on this input -- screens with
   large flat regions -- almost all of the win comes from LZ77 matching
   rather than from a tuned alphabet. Dynamic blocks would add a few percent
   for a large amount of code.

   BIT ORDER IS THE TRAP, and the two rules are opposite. Huffman codes are
   written most-significant bit first; the extra bits that follow a length or
   distance code are written least-significant bit first. Getting this wrong
   produces a stream that decodes for a while and then fails, so the test
   suite checks round-trips against a real inflater rather than eyeballing
   sizes. *)

(* RFC 1951 SS3.2.5. Length codes 257..285, each with its extra-bit count and
   the smallest length it encodes. *)
let length_base =
  [| 3; 4; 5; 6; 7; 8; 9; 10; 11; 13; 15; 17; 19; 23; 27; 31; 35; 43; 51; 59;
     67; 83; 99; 115; 131; 163; 195; 227; 258 |]

let length_extra =
  [| 0; 0; 0; 0; 0; 0; 0; 0; 1; 1; 1; 1; 2; 2; 2; 2; 3; 3; 3; 3;
     4; 4; 4; 4; 5; 5; 5; 5; 0 |]

(* Distance codes 0..29. *)
let dist_base =
  [| 1; 2; 3; 4; 5; 7; 9; 13; 17; 25; 33; 49; 65; 97; 129; 193; 257; 385;
     513; 769; 1025; 1537; 2049; 3073; 4097; 6145; 8193; 12289; 16385; 24577 |]

let dist_extra =
  [| 0; 0; 0; 0; 1; 1; 2; 2; 3; 3; 4; 4; 5; 5; 6; 6; 7; 7;
     8; 8; 9; 9; 10; 10; 11; 11; 12; 12; 13; 13 |]

let window_size = 32768
let min_match = 3
let max_match = 258
let hash_bits = 15
let hash_size = 1 lsl hash_bits
(* How far back along a hash chain to look before settling for what we have.
   Unbounded search is quadratic on a screen of one flat colour, which is the
   common case here, not a corner one. *)
let max_chain = 128

type writer = {
  out : Buffer.t;
  mutable acc : int;   (* bits not yet flushed, low end first *)
  mutable nbits : int;
}

let put_bits (w : writer) (value : int) (n : int) : unit =
  w.acc <- w.acc lor ((value land ((1 lsl n) - 1)) lsl w.nbits);
  w.nbits <- w.nbits + n;
  while w.nbits >= 8 do
    Buffer.add_char w.out (Char.chr (w.acc land 0xff));
    w.acc <- w.acc lsr 8;
    w.nbits <- w.nbits - 8
  done

(* Huffman codes travel most-significant bit first, unlike everything else. *)
let put_code (w : writer) (code : int) (len : int) : unit =
  for i = len - 1 downto 0 do
    put_bits w ((code lsr i) land 1) 1
  done

let flush_writer (w : writer) : unit =
  if w.nbits > 0 then begin
    Buffer.add_char w.out (Char.chr (w.acc land 0xff));
    w.acc <- 0;
    w.nbits <- 0
  end

(* RFC 1951 SS3.2.6, the fixed literal/length alphabet. *)
let put_literal (w : writer) (lit : int) : unit =
  if lit <= 143 then put_code w (0x30 + lit) 8
  else if lit <= 255 then put_code w (0x190 + lit - 144) 9
  else if lit <= 279 then put_code w (lit - 256) 7
  else put_code w (0xc0 + lit - 280) 8

let length_code (len : int) : int =
  let c = ref 28 in
  (try
     for i = 0 to 28 do
       if length_base.(i) > len then begin c := i - 1; raise Exit end
     done
   with Exit -> ());
  !c

let dist_code (d : int) : int =
  let c = ref 29 in
  (try
     for i = 0 to 29 do
       if dist_base.(i) > d then begin c := i - 1; raise Exit end
     done
   with Exit -> ());
  !c

let put_match (w : writer) ~(len : int) ~(dist : int) : unit =
  let lc = length_code len in
  put_literal w (257 + lc);
  if length_extra.(lc) > 0 then
    put_bits w (len - length_base.(lc)) length_extra.(lc);
  let dc = dist_code dist in
  (* Distance codes use their own fixed alphabet: 5-bit values, MSB first. *)
  put_code w dc 5;
  if dist_extra.(dc) > 0 then
    put_bits w (dist - dist_base.(dc)) dist_extra.(dc)

let write_fixed_block (buf : Buffer.t) (data : bytes) : unit =
  let len = Bytes.length data in
  let w = { out = buf; acc = 0; nbits = 0 } in
  put_bits w 1 1;   (* BFINAL: one block for the whole stream *)
  put_bits w 1 2;   (* BTYPE = 01, fixed Huffman *)
  let head = Array.make hash_size (-1) in
  let prev = Array.make (max len 1) (-1) in
  let byte i = Char.code (Bytes.unsafe_get data i) in
  let hash i =
    ((byte i lsl 10) lxor (byte (i + 1) lsl 5) lxor byte (i + 2))
    land (hash_size - 1)
  in
  let pos = ref 0 in
  while !pos < len do
    let best_len = ref 0 and best_dist = ref 0 in
    if !pos + min_match <= len then begin
      let h = hash !pos in
      let cand = ref head.(h) in
      let chain = ref 0 in
      while
        !cand >= 0 && !chain < max_chain && !pos - !cand <= window_size
      do
        let limit = min max_match (len - !pos) in
        let l = ref 0 in
        while !l < limit && byte (!cand + !l) = byte (!pos + !l) do incr l done;
        if !l > !best_len then begin
          best_len := !l;
          best_dist := !pos - !cand
        end;
        if !best_len >= max_match then chain := max_chain
        else begin
          incr chain;
          cand := prev.(!cand)
        end
      done;
      (* Register this position before moving on. *)
      prev.(!pos) <- head.(h);
      head.(h) <- !pos
    end;
    if !best_len >= min_match then begin
      put_match w ~len:!best_len ~dist:!best_dist;
      (* Every position inside the match still has to enter the hash chains,
         or later matches cannot reach back past it. *)
      for k = 1 to !best_len - 1 do
        let p = !pos + k in
        if p + min_match <= len then begin
          let h = hash p in
          prev.(p) <- head.(h);
          head.(h) <- p
        end
      done;
      pos := !pos + !best_len
    end
    else begin
      put_literal w (byte !pos);
      incr pos
    end
  done;
  put_literal w 256;   (* end of block *)
  flush_writer w

(* Fixed Huffman EXPANDS incompressible input: a byte above 143 costs nine
   bits, so pure noise grows by about 5%. A stored block never does, costing
   five bytes per 65535. Both are produced and the smaller wins, so this can
   never be worse than the stored-only writer it replaced -- which matters
   because a screen of dithered noise is a real drawing, not a hypothetical
   one. *)
let max_block_len = 65535

let add_le16 (buf : Buffer.t) (n : int) : unit =
  Buffer.add_char buf (Char.chr (n land 0xff));
  Buffer.add_char buf (Char.chr ((n lsr 8) land 0xff))

let write_stored_blocks (buf : Buffer.t) (data : bytes) : unit =
  let len = Bytes.length data in
  let emit_block ~is_final ~pos ~block_len =
    Buffer.add_char buf (if is_final then '\001' else '\000');
    add_le16 buf block_len;
    add_le16 buf (lnot block_len land 0xffff);
    Buffer.add_subbytes buf data pos block_len
  in
  if len = 0 then
    (* An empty stream is still one final, empty stored block. *)
    emit_block ~is_final:true ~pos:0 ~block_len:0
  else begin
    let pos = ref 0 in
    while !pos < len do
      let remaining = len - !pos in
      let block_len = min max_block_len remaining in
      emit_block ~is_final:(block_len = remaining) ~pos:!pos ~block_len;
      pos := !pos + block_len
    done
  end


let compress (data : bytes) : bytes =
  let buf = Buffer.create (Bytes.length data + 64) in
  (* CMF=0x78 (deflate method, 32K window), FLG=0x01 (no preset dictionary,
     chosen so (CMF*256+FLG) mod 31 = 0 as RFC 1950 requires — 0x7801 =
     30721 = 991 * 31. FLEVEL is advisory and no inflater acts on it. *)
  Buffer.add_char buf '\x78';
  Buffer.add_char buf '\x01';
  let fixed = Buffer.create (Bytes.length data / 4 + 64) in
  write_fixed_block fixed data;
  let stored = Buffer.create (Bytes.length data + 64) in
  write_stored_blocks stored data;
  Buffer.add_buffer buf
    (if Buffer.length fixed <= Buffer.length stored then fixed else stored);
  let adler = Checksums.to_unsigned (Checksums.adler32 data) in
  Buffer.add_char buf (Char.chr ((adler lsr 24) land 0xff));
  Buffer.add_char buf (Char.chr ((adler lsr 16) land 0xff));
  Buffer.add_char buf (Char.chr ((adler lsr 8) land 0xff));
  Buffer.add_char buf (Char.chr (adler land 0xff));
  Buffer.to_bytes buf
