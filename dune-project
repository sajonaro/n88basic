(lang dune 3.17)
(name n88basic)

; Declared so `dune build -p n88basic` works, which is what opam invokes.
; The opam file itself is written by hand (n88basic.opam) rather than
; generated, so generate_opam_files is deliberately not set.
(package
 (name n88basic))
