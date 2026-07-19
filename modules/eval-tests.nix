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
  testOrderlessAssembly = {
    expr = assemblyOf "orderless" [ { usePackage.orderless.enable = true; } ];
    expected = "(use-package orderless\n  :config (setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))\n  )";
  };
  testMagitAssembly = {
    expr = assemblyOf "magit" [ { usePackage.magit.enable = true; } ];
    expected = "(use-package magit\n  :bind ((\"C-x g\" . magit-status))\n  )";
  };
  testConsultAssembly = {
    expr = assemblyOf "consult" [ { usePackage.consult.enable = true; } ];
    expected = "(use-package consult\n  :bind ((\"C-x b\" . consult-buffer) (\"M-g g\" . consult-goto-line) (\"M-g i\" . consult-imenu) (\"M-s l\" . consult-line) (\"M-s r\" . consult-ripgrep) (\"M-y\" . consult-yank-pop))\n  :bind (:map isearch-mode-map (\"M-s l\" . consult-line))\n  :custom ((consult-narrow-key \"<\"))\n  :init (advice-add #'register-preview :override #'consult-register-window)\n(setq register-preview-delay 0.5)\n(setq xref-show-xrefs-function #'consult-xref\n      xref-show-definitions-function #'consult-xref)\n  :config (consult-customize consult-ripgrep :preview-key '(:debounce 0.4 any))\n  )";
  };
  # consult declares runtimePackages = [ ripgrep ]; build.package must be the
  # symlinkJoin-wrapped emacs (name gains the "ennoix-" prefix). Branch-selected
  # check per testRuntimeWrapsPackage; rg-on-PATH is build/interactive only.
  testConsultRuntimeWraps = {
    expr = lib.hasPrefix "ennoix-" (cfg [ { usePackage.consult.enable = true; } ]).build.package.name;
    expected = true;
  };
  testEmbarkAssembly = {
    expr = assemblyOf "embark" [ { usePackage.embark.enable = true; } ];
    expected = "(use-package embark\n  :bind ((\"C-.\" . embark-act) (\"C-;\" . embark-dwim) (\"C-h B\" . embark-bindings))\n  :init (setq prefix-help-command #'embark-prefix-help-command)\n  :config (add-to-list 'display-buffer-alist\n             '(\"\\\\`\\\\*Embark Collect \\\\(Live\\\\|Completions\\\\)\\\\*\"\n               nil\n               (window-parameters (mode-line-format . none))))\n  )";
  };
  testEmbarkConsultAssembly = {
    expr = assemblyOf "embark-consult" [ { usePackage.embark-consult.enable = true; } ];
    expected = "(use-package embark-consult\n  :after (embark consult)\n  )";
  };
  # built-in: catalog's mkCatalogDefault (1400) must beat the type's
  # declaration default (1500) on a SCALAR — the case that hard-conflicts
  # at equal priority.
  testSavehistIsBuiltin = {
    expr = (cfg [ { usePackage.savehist.enable = true; } ]).usePackage.savehist.package;
    expected = null;
  };
  # recorded policy: modus-themes is a PACKAGE, not a built-in
  testModusThemesPackage = {
    expr = (cfg [ { usePackage.modus-themes.enable = true; } ]).usePackage.modus-themes.package.pname;
    expected = "modus-themes";
  };
  # THE override-replacement contract (kept by decision): a user plain
  # definition REPLACES a mkCatalogDefault value for a mergeable field —
  # exact equality proves the curated binding is GONE, not merged in.
  testUserOverrideReplacesCatalogBind = {
    expr = assemblyOf "magit" [
      {
        usePackage.magit = {
          enable = true;
          bind = {
            "C-c g" = "magit-dispatch";
          };
        };
      }
    ];
    expected = "(use-package magit\n  :bind ((\"C-c g\" . magit-dispatch))\n  )";
  };
  # The dotted-path form is a definition of the WHOLE bind option too —
  # it looks additive but replaces the catalog default wholesale, exactly
  # like the full-attrset form above (same option, same priority 100).
  testUserDottedPathAlsoReplaces = {
    expr = assemblyOf "magit" [
      {
        usePackage.magit.enable = true;
        usePackage.magit.bind."C-c M-g" = "magit-file-dispatch";
      }
    ];
    expected = "(use-package magit\n  :bind ((\"C-c M-g\" . magit-file-dispatch))\n  )";
  };
}
