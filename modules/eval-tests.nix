# Pure-eval tests through the real entrypoint. `lib.runTests` → [] when all pass.
{
  lib,
  pkgs,
  evalEnnoix,
}:
let
  cfg =
    mods:
    evalEnnoix {
      inherit pkgs;
      modules = mods;
    };
  initOf = mods: (cfg mods).build.initText;
in
lib.runTests {
  testEmptyInit = {
    expr = initOf [ ];
    expected = "";
  };
  testEmptyIsDerivation = {
    expr = lib.isDerivation (cfg [ ]).build.package;
    expected = true;
  };
  testVerticoActivation = {
    expr = lib.hasInfix "(vertico-mode 1)" (initOf [ { plugins.vertico.enable = true; } ]);
    expected = true;
  };
}
