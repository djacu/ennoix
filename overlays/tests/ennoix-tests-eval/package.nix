# Realizes modules/eval-tests.nix: a non-empty failure list throws at
# evaluation (a per-attr eval error in the jobset); success is touch $out.
{
  lib,
  runCommand,
  ennoixEval,
  hello,
}:
let
  failures = import ../../../modules/eval-tests.nix { inherit lib ennoixEval hello; };
in
if failures == [ ] then
  runCommand "ennoix-tests-eval" { } "touch $out"
else
  throw "ennoix eval tests failed:\n${lib.generators.toPretty { } failures}"
