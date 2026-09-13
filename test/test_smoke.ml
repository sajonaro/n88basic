(* The version is asserted for SHAPE, not for a literal. A test comparing the
   constant to a copy of itself is a test that cannot fail for the reason it
   exists, and the previous one proved it: it froze at "0.1.0" and stayed
   green through five releases. What the release actually needs held is that
   the string is a version at all -- the workflow compares it against the git
   tag and refuses to publish on a mismatch, which is the check with teeth. *)
let test_version () =
  let v = N88basic.Version.string in
  Alcotest.(check bool) "version looks like a version" true
    (String.length v > 0
    && String.for_all (fun c -> (c >= '0' && c <= '9') || c = '.') v
    && String.contains v '.')

let () =
  Alcotest.run "n88basic"
    [ ("smoke", [ Alcotest.test_case "version" `Quick test_version ]) ]
