let test_version () =
  Alcotest.(check string) "version string" "0.1.0" N88basic.Version.value

let () =
  Alcotest.run "n88basic"
    [ ("smoke", [ Alcotest.test_case "version" `Quick test_version ]) ]
