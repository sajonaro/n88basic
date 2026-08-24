(* A zlib stream (RFC 1950) carrying deflate (RFC 1951) "stored" blocks only
   — no compression, no Huffman tables, nothing that could fail to cross a
   js_of_ocaml boundary (design §7). A stored block's payload is capped at
   65535 bytes, so anything longer is split across several.

   A stored block's header is exactly 3 bits: BFINAL then a 2-bit BTYPE of
   00, after which the format pads out to the next byte boundary. Since the
   deflate bitstream always starts at a byte boundary of its own — right
   after zlib's 2-byte header — that first byte's low bit is BFINAL, the
   next two are BTYPE=00, and the remaining five padding bits are zero.
   That collapses the whole header to one literal byte: 0x00 for "more
   blocks follow", 0x01 for "this is the last one". *)

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
     fastest level; chosen so (CMF*256+FLG) mod 31 = 0 as RFC 1950
     requires — 0x7801 = 30721 = 991 * 31). *)
  Buffer.add_char buf '\x78';
  Buffer.add_char buf '\x01';
  write_stored_blocks buf data;
  let adler = Checksums.to_unsigned (Checksums.adler32 data) in
  Buffer.add_char buf (Char.chr ((adler lsr 24) land 0xff));
  Buffer.add_char buf (Char.chr ((adler lsr 16) land 0xff));
  Buffer.add_char buf (Char.chr ((adler lsr 8) land 0xff));
  Buffer.add_char buf (Char.chr (adler land 0xff));
  Buffer.to_bytes buf
