# Pure-eval tests through the real entrypoint. `lib.runTests` -> [] when all pass.
# Emitter-shape EQUALITY tests on per-entry assembly paths (no hasInfix).
{
  lib,
  ennoixEval,
  hello,
}:
let
  cfg = ennoixEval;
  assemblyOf = name: modules: (cfg modules).usePackage.${name}.assembly;
in
lib.runTests {
  testEmptyInitText = {
    expr = (cfg [ ]).build.initText;
    expected = "";
  };
  testEmptyBuildIsDerivation = {
    expr = lib.isDerivation (cfg [ ]).build.package;
    expected = true;
  };
  testVerticoAssembly = {
    expr = assemblyOf "vertico" [ { usePackage.vertico.enable = true; } ];
    expected = "(use-package vertico\n  :init (vertico-mode 1)\n  )";
  };
  # bind: structured attrsOf str -> ("KEY" . command), key quoted/escaped
  testBindShape = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          bind = {
            "C-c p" = "probe-cmd";
          };
        };
      }
    ];
    expected = "(use-package probe\n  :bind ((\"C-c p\" . probe-cmd))\n  )";
  };
  # every remaining keyword emitter in one synthetic entry
  # (custom iterates lexicographically: probe-count < probe-flag < probe-lit)
  testKeywordShapes = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          demand = true;
          after = [ "vertico" ];
          commands = [ "probe-cmd" ];
          mode = [ ''("dummy" . probe-mode)'' ];
          hook = [ "(prog-mode . probe-mode)" ];
          custom = {
            probe-count = 3;
            probe-flag = true;
            probe-lit = ''"lit"'';
          };
          init = "(probe-setup)";
          config = "(probe-finalize)";
        };
      }
    ];
    expected = "(use-package probe\n  :demand t\n  :after (vertico)\n  :commands (probe-cmd)\n  :mode ((\"dummy\" . probe-mode))\n  :hook ((prog-mode . probe-mode))\n  :custom ((probe-count 3) (probe-flag t) (probe-lit \"lit\"))\n  :init (probe-setup)\n  :config (probe-finalize)\n  )";
  };
  testDeferNumber = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          defer = 2;
        };
      }
    ];
    expected = "(use-package probe\n  :defer 2\n  )";
  };
  # bind variants: :bind*, :bind-keymap, and per-map local binds
  testBindVariants = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          bind' = {
            "C-c P" = "probe-override";
          };
          bindKeyMap = {
            "C-c m" = "probe-command-map";
          };
          bindLocal = {
            probe-mode-map = {
              "x" = "probe-exec";
            };
          };
        };
      }
    ];
    expected = "(use-package probe\n  :bind* ((\"C-c P\" . probe-override))\n  :bind-keymap ((\"C-c m\" . probe-command-map))\n  :bind (:map probe-mode-map (\"x\" . probe-exec))\n  )";
  };
  # bind keys escape backslashes as well as quotes
  testBindKeyEscaping = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          bind = {
            "C-\\" = "probe-cmd";
          };
        };
      }
    ];
    expected = "(use-package probe\n  :bind ((\"C-\\\\\" . probe-cmd))\n  )";
  };
  # an empty inner bindLocal map emits nothing (emptiness-guard parity)
  testBindLocalEmptyMapOmitted = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          bindLocal = {
            probe-mode-map = { };
          };
        };
      }
    ];
    expected = "(use-package probe\n  )";
  };
  # byte-compiler declarations + :interpreter
  testDeclarationKeywords = {
    expr = assemblyOf "probe" [
      {
        usePackage.probe = {
          enable = true;
          package = null;
          defines = [ "probe-var" ];
          functions = [ "probe-fn" ];
          interpreter = [ ''("probe" . probe-mode)'' ];
        };
      }
    ];
    expected = "(use-package probe\n  :defines (probe-var)\n  :functions (probe-fn)\n  :interpreter ((\"probe\" . probe-mode))\n  )";
  };
  # runtimePackages branch selection (eval-level: wrapped name prefix only;
  # the wrapper's runtime behavior was spike-verified and lands with Phase 1)
  testRuntimeWrapsPackage = {
    expr =
      lib.hasPrefix "ennoix-"
        (cfg [
          {
            usePackage.probe = {
              enable = true;
              package = null;
              runtimePackages = [ hello ];
            };
          }
        ]).build.package.name;
    expected = true;
  };
  testNoRuntimeNoWrap = {
    expr = lib.hasPrefix "ennoix-" (cfg [ { usePackage.vertico.enable = true; } ]).build.package.name;
    expected = false;
  };
}
