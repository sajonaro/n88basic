(* The 8 digital-RGB colours a colour number selects in the default 8-of-8
   ("8色中8色") palette mode — see spec/clauses.json's "SCREEN.COLOR", grounded
   against ref-9801 printed p.49 (the identity and order: black, blue, red,
   purple, green, light blue, yellow, white) and printed p.50 (the same
   palette's 4096-colour codes, one per entry, from which the RGB triples
   below are read off: each &Hgrb code's nibbles are green, red, blue, so
   e.g. &H0F0 — "bright red" — is (0xF,0x0,0x0) in (R,G,B) once the nibbles
   are reordered).

   This table maps a *colour code* to RGB. It is fixed: ref-9801 printed p.49
   gives these eight colours, and nothing in the language changes what colour
   code 4 looks like.

   What [2] COLOR moves is the other hop — which colour code a *palette
   number* stands for (printed p.51). That mapping is mutable, lives in a
   Framebuffer alongside the pixels it applies to, and starts as
   [initial_mapping] below.

   A colour code here is 0-7 because this interpreter has only the 8-of-8
   palette mode. The 4096-colour and 16-colour modes are NOT out of scope —
   spec.md §3.3 put palette mode in scope on 2026-08-17 — they are simply
   unbuilt, and reaching them needs [1] COLOR's palette-mode slot, which is
   still refused. See SCREEN.COLOR-PALETTE. *)

let colours : (int * int * int) array =
  [|
    (0, 0, 0); (* 0 black / &H000 *)
    (0, 0, 255); (* 1 blue / &H00F *)
    (255, 0, 0); (* 2 red / &H0F0 *)
    (255, 0, 255); (* 3 purple / &H0FF *)
    (0, 255, 0); (* 4 green / &HF00 *)
    (0, 255, 255); (* 5 light blue / &HF0F *)
    (255, 255, 0); (* 6 yellow / &HFF0 *)
    (255, 255, 255); (* 7 white / &HFFF *)
  |]

(* The startup foreground colour: white, "the brightest, most visible
   default". Not read from any source — a reasonable choice, like
   rasterize.ml's (0,0) starting point, standing in until COLOR sets one. *)
let default_foreground_index = 7

(* The startup background colour: black, matching a framebuffer's own
   cleared state (Framebuffer.create). Also not read from any source. *)
let default_background_index = 0

let count = Array.length colours

(* Palette numbers and colour codes are both 0-7 here, and both wrap.

   This is a total-function guard, not the language's rule. A program cannot
   reach it: basic/interp.ml refuses an out-of-range argument to [2] COLOR
   with Illegal function call before one gets here, precisely so that a
   listing written for a 4096-colour machine is told rather than quietly
   given a folded colour. What wrapping buys is that every internal caller —
   [to_rgb], [set_pixel], [fill] — is total, so no path can raise on a stray
   index. If you are looking for the rule a program sees, it is in interp. *)
let wrap (n : int) : int = ((n mod count) + count) mod count
let to_rgb (code : int) : int * int * int = colours.(wrap code)

(* The startup mapping: palette number n shows colour code n.
   ref-9801 printed p.51 sends the reader to [1] COLOR for the initial state,
   and book intro-8801 printed p.119 states it outright -- at power-on the
   palette numbers and the colour numbers coincide, which is why the two look
   interchangeable until a program moves one.

   Returns a fresh array every call: it is the initialiser for mutable
   per-framebuffer state, and handing out a shared one would let two
   framebuffers alias the same palette. *)
let initial_mapping () : int array = Array.init count (fun i -> i)
