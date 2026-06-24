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
  # ennoix's core claim: a user override REPLACES the curated default (curated
  # values are option defaults at mkOptionDefault priority, so a user definition
  # drops the default) — it does not merge/append.
  testUserOverrideReplacesDefault = {
    expr =
      let
        out = initOf [
          {
            plugins.vertico.enable = true;
            plugins.vertico.init = "(my-custom-vertico-setup)";
          }
        ];
      in
      lib.hasInfix "(my-custom-vertico-setup)" out && !(lib.hasInfix "(vertico-mode 1)" out);
    expected = true;
  };
  # Replacement holds for list-typed options too (the curated bind list is
  # dropped, not merged with the user's).
  testUserOverrideReplacesListDefault = {
    expr =
      let
        out = initOf [
          {
            plugins.magit.enable = true;
            plugins.magit.bind = [ ''("C-c m" . magit-dispatch)'' ];
          }
        ];
      in
      lib.hasInfix "magit-dispatch" out && !(lib.hasInfix "magit-status" out);
    expected = true;
  };
}
