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
  testOrderlessCompletionStyles = {
    expr = lib.hasInfix "completion-styles '(orderless basic)" (initOf [
      { plugins.orderless.enable = true; }
    ]);
    expected = true;
  };
  testOrderlessFileOverrides = {
    expr = lib.hasInfix "completion-category-overrides '((file" (initOf [
      { plugins.orderless.enable = true; }
    ]);
    expected = true;
  };
  testMarginaliaActivation = {
    expr = lib.hasInfix "(marginalia-mode 1)" (initOf [ { plugins.marginalia.enable = true; } ]);
    expected = true;
  };
  testSavehistActivation = {
    expr = lib.hasInfix "(savehist-mode 1)" (initOf [ { plugins.savehist.enable = true; } ]);
    expected = true;
  };
  testWhichKeyActivation = {
    expr = lib.hasInfix "(which-key-mode 1)" (initOf [ { plugins.which-key.enable = true; } ]);
    expected = true;
  };
  testModusLoadsTheme = {
    expr = lib.hasInfix "(load-theme 'modus-operandi" (initOf [
      { plugins.modus-themes.enable = true; }
    ]);
    expected = true;
  };
  testBuiltinHasNoPackage = {
    expr = (cfg [ { plugins.savehist.enable = true; } ]).plugins.savehist.package;
    expected = null;
  };
  testModusThemesHasPackage = {
    expr = (cfg [ { plugins.modus-themes.enable = true; } ]).plugins.modus-themes.package;
    expected = "modus-themes";
  };
  testMagitBinding = {
    expr = lib.hasInfix ''("C-x g" . magit-status)'' (initOf [ { plugins.magit.enable = true; } ]);
    expected = true;
  };
  testFailLoud = {
    # evalEnnoix throws when an enabled plugin's package isn't in the scope.
    expr =
      (builtins.tryEval
        (cfg [
          {
            plugins.magit.enable = true;
            plugins.magit.package = "no-such-pkg";
          }
        ]).build.package
      ).success;
    expected = false;
  };
  testCatalogHasSeven = {
    expr = builtins.length (import ./plugins { inherit lib; }); # ./plugins — eval-tests.nix lives in modules/
    expected = 7;
  };
}
