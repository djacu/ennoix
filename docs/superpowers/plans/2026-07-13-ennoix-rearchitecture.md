# ennoix Re-architecture Implementation Plan

> **Status: implemented** — all four tasks executed and reviewed (subagent-driven); the implementation is the `6ca306e..7fbaa2b` range on `djacu/rearchitecture`. Review fixes were synced back into this document as they landed.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase 0's wiring with the re-architecture: a flat package set (`pkgs.ennoixEval`, `ennoix-emacs*`, `ennoix-tests-*`), one `usePackage` namespace over a shared rycee-style type, a `catalog/<name>/module.nix` catalog at `mkOverride 1400`, and path-collected test/package jobsets.

**Architecture:** Spec: `docs/superpowers/specs/2026-07-06-ennoix-rearchitecture-design.md` (read §2's tree first). `ennoixEval` (callPackage'd, `modules: config`) evaluates `baseModules` (namespace + generation + build + collected catalog) via a thin `lib.evalModules`; per-entry `use-package` forms are emitted by the shared type's internal `assembly` option; `build.package` holds the final (runtime-wrapped when needed) emacs. No assertions layer — missing packages fail naturally at eval.

**Tech Stack:** Nix flakes (hand-wired outputs), the NixOS module system (`evalModules`, `submoduleWith`, `mkPackageOption`, `mkOverride 1400`), nixpkgs `emacsPackages` (`withPackages`/`trivialBuild`), emacs 30.2, treefmt.

## Global Constraints

- **Branch:** work on `djacu/rearchitecture` (already checked out; contains the spec commits).
- **No flake-parts.** Outputs stay hand-wired.
- **Commit messages carry NO `Co-Authored-By` trailer** (hard repo rule).
- Run `nix fmt` before every commit (treefmt: nixfmt + deadnix + statix + mdformat, `no-lambda-pattern-names = true`); the formatter may reflow snippets — that is expected. Verify with `nix build .#checks.x86_64-linux.formatting`.
- **Every commit must evaluate:** `nix flake check --no-build` green at each task's end.
- **Flakes evaluate the git index:** `git add` new files/directories BEFORE any `nix build`, or the evaluator cannot see them.
- Exact names (spec §2): option namespace `usePackage`; `pkgs.ennoixEval`; packages `ennoix-emacs`, `ennoix-emacs-full`; tests `ennoix-tests-eval`, `ennoix-tests-load`, `ennoix-tests-load-full`; `mkCatalogDefault = lib.mkOverride 1400` (exactly 1400).
- Base emacs is `pkgs.emacs` via `pkgs.emacsPackages` only — never call `emacsPackagesFor` outside the `emacs-packages` overlay.
- CLI note: `nix build .#packages.x86_64-linux.default` is broken in this repo (installable prefix-resolution quirk); use `nix build .#default`.
- **Zero assumptions:** if a command behaves unexpectedly, STOP and report; do not invent workarounds.

______________________________________________________________________

## File Structure (final state — spec §2 tree)

- `modules/lib/use-package-type.nix` — NEW: the shared type (options + `assembly` emitter).
- `modules/use-package.nix` — NEW: declares the flat `usePackage` option.
- `modules/eval.nix` — NEW: `{ lib, pkgs }: modules: config` (assembles baseModules + catalog collector).
- `modules/generation.nix` — REWRITE: `build.initText` = concatenated enabled assemblies.
- `modules/build.nix` — REWRITE: `build.package` from hardcoded package derivations + runtime wrapper.
- `modules/eval-tests.nix` — REWRITE: emitter-equality suite + override-replacement test.
- `modules/catalog/<name>/module.nix` — NEW ×7 (vertico, orderless, marginalia, savehist, which-key, modus-themes, magit).
- `overlays/top-level/{ennoixEval,ennoix-emacs,ennoix-emacs-full}/package.nix` — NEW.
- `overlays/tests/{ennoix-tests-eval,ennoix-tests-load,ennoix-tests-load-full}/package.nix` — NEW.
- `overlays/emacs-packages/.gitkeep` — NEW (replaces the deleted `default.nix` stub).
- `overlays/default.nix`, `hydra-jobs/tests.nix`, `flake.nix`, `library/default.nix` — REWRITE/MODIFY.
- DELETE: `library/ennoix.nix`, `modules/default.nix`, `modules/lib/mk-plugin.nix`, `modules/assertions.nix`, `modules/plugins/` (entirely), `overlays/emacs-packages/default.nix`.

______________________________________________________________________

## Task 1: The atomic swap — core module system, `ennoixEval`, walking-skeleton tests

> One coherent commit that tears down Phase 0's wiring and stands up the re-architecture with a one-entry catalog (vertico). The coarse RED→GREEN is the eval-test runner: it cannot exist before `ennoixEval` does. The flake `packages` output is REMOVED in this task (nothing to point it at yet) and restored in Task 3.

**Files:**

- Create: `modules/lib/use-package-type.nix`, `modules/use-package.nix`, `modules/eval.nix`, `modules/catalog/vertico/module.nix`, `overlays/top-level/ennoixEval/package.nix`, `overlays/tests/ennoix-tests-eval/package.nix`, `overlays/emacs-packages/.gitkeep`
- Rewrite: `modules/generation.nix`, `modules/build.nix`, `modules/eval-tests.nix`, `overlays/default.nix`, `hydra-jobs/tests.nix`
- Modify: `flake.nix` (remove `packages`), `library/default.nix` (remove `ennoix`)
- Delete: `library/ennoix.nix`, `modules/default.nix`, `modules/lib/mk-plugin.nix`, `modules/assertions.nix`, `modules/plugins/` (recursively), `overlays/emacs-packages/default.nix`

**Interfaces:**

- Consumes: `pkgs.emacsPackages` (withPackages/trivialBuild), `lib.evalModules`, `lib.mkPackageOption`, the repo's `packagesFromDirectoryRecursive` slot pattern, `self.library.paths.getDirectoryNames` (hydra-jobs only).

- Produces (later tasks rely on these EXACT names/shapes):

  - `pkgs.ennoixEval : [module] -> config`, with `config.build.initText : string`, `config.build.package : derivation`, and per-entry `config.usePackage.<name>.{enable,package,runtimePackages,extraPackages,after,bind,bind',bindKeyMap,bindLocal,commands,custom,defines,functions,hook,interpreter,mode,defer,demand,init,config,assembly}`.
  - specialArgs available to all modules: `pkgs`, `mkCatalogDefault` (= `lib.mkOverride 1400`).
  - Catalog contract: every DIRECTORY `modules/catalog/<key>/` is an entry; its module is `module.nix`; the directory name IS the `usePackage` key.
  - `pkgs.ennoix-tests-eval` (derivation; throws at eval on test failure).

- [ ] **Step 1: Record the RED**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix-tests-eval 2>&1 | tail -3`
Expected: FAIL — `error: flake '…' does not provide attribute … 'legacyPackages.x86_64-linux.ennoix-tests-eval'` (any missing-attribute failure is the RED; nothing exists yet).

- [ ] **Step 2: Delete the Phase-0 machinery**

```bash
git rm library/ennoix.nix modules/default.nix modules/lib/mk-plugin.nix modules/assertions.nix overlays/emacs-packages/default.nix
git rm -r modules/plugins
# git rm deletes the emptied overlays/emacs-packages directory — recreate it
mkdir -p overlays/emacs-packages && touch overlays/emacs-packages/.gitkeep
```

- [ ] **Step 3: Restore `library/default.nix` to flake plumbing only** (full file)

```nix
inputs:

let

  inherit (inputs.nixpkgs-lib)
    lib
    ;

  inherit (lib.fixedPoints)
    makeExtensible
    ;

  library = makeExtensible (
    self:
    let
      callLibs =
        file:
        import file {
          inherit lib;
          library = self;
        };
    in
    {

      paths = callLibs ./paths.nix;
      systems = callLibs ./systems.nix;

    }
  );

in

library
```

- [ ] **Step 4: Remove the `packages` output from `flake.nix`** (full `outputs` block after the edit; `inputs` block unchanged)

```nix
  outputs = inputs: {

    checks = import ./checks/default.nix inputs;
    formatter = import ./formatter/default.nix inputs;
    formatterModule = import ./formatterModule/default.nix inputs;
    legacyPackages = import ./legacyPackages/default.nix inputs;
    library = import ./library/default.nix inputs;
    nixosModules = import ./nixosModules/default.nix inputs;
    nixosConfigurations = import ./nixosConfigurations/default.nix inputs;
    overlays = import ./overlays/default.nix inputs;

  };
```

- [ ] **Step 5: Create `modules/lib/use-package-type.nix`** (the shared type; full file)

```nix
# The shared use-package entry type (adapted from rycee's usePackageType).
# NOTE: this submodule declares an OPTION named `config`; the module arg
# `config` below is the submodule's own config, so the option is read as
# `config.config`. Do not "fix" this — it mirrors rycee and use-package.
# (Entries can only SET a `config` key in shorthand because the namespace
# declares the submodule with shorthandOnlyDefinesConfig = true.)
{
  name,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    filterAttrs
    mapAttrsToList
    mkEnableOption
    mkOption
    mkPackageOption
    optional
    types
    ;

  quote = s: ''"${lib.strings.escape [ "\"" "\\" ] s}"'';

  # :custom value serialization: bool -> t/nil, int -> number,
  # string -> LITERAL elisp emitted verbatim (typed coercion stops here).
  toElisp =
    v:
    if builtins.isBool v then
      (if v then "t" else "nil")
    else if builtins.isInt v then
      toString v
    else
      v;

  listKw = kw: xs: optional (xs != [ ]) "  :${kw} (${concatStringsSep " " xs})";
  pairsKw =
    kw: f: attrs:
    optional (attrs != { }) "  :${kw} (${concatStringsSep " " (mapAttrsToList f attrs)})";
  linesKw = kw: s: optional (s != "") "  :${kw} ${s}";
  boolKw = kw: b: optional b "  :${kw} t";
  deferKw = d: if builtins.isBool d then optional d "  :defer t" else [ "  :defer ${toString d}" ];
  bindPair = key: cmd: "(${quote key} . ${cmd})";
  # one ":bind (:map <name> ...)" line per local keymap (rycee's emission;
  # use-package merges repeated :bind occurrences)
  bindLocalKw =
    maps:
    mapAttrsToList (
      mapName: pairs: "  :bind (:map ${mapName} ${concatStringsSep " " (mapAttrsToList bindPair pairs)})"
    ) (filterAttrs (_: pairs: pairs != { }) maps);
in
{
  options = {
    enable = mkEnableOption "the ${name} use-package entry";
    package = mkPackageOption pkgs.emacsPackages name {
      nullable = true;
      pkgsText = "pkgs.emacsPackages";
    };
    runtimePackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Non-elisp binaries placed on the built emacs's PATH.";
    };
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Extra elisp packages installed without a use-package form of their own.";
    };
    after = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :after
    bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ":bind — key = keybinding string, value = command.";
    };
    bind' = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ":bind* — like bind, but overrides minor-mode maps.";
    };
    bindKeyMap = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ":bind-keymap — key = keybinding string, value = keymap.";
    };
    bindLocal = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      default = { };
      description = "Local keymap binds: keymap name -> { key = command; }.";
    };
    commands = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :commands (rycee's `command`, deliberately renamed)
    custom = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.bool
          types.int
          types.str
        ]
      );
      default = { };
    }; # :custom
    defines = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :defines (byte-compiler declarations)
    functions = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :functions (byte-compiler declarations)
    hook = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :hook — literal elisp pairs
    interpreter = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :interpreter — literal elisp pairs
    mode = mkOption {
      type = types.listOf types.str;
      default = [ ];
    }; # :mode — literal elisp pairs
    defer = mkOption {
      type = types.either types.bool types.ints.positive;
      default = false;
    }; # :defer t / :defer N
    demand = mkOption {
      type = types.bool;
      default = false;
    }; # :demand t
    init = mkOption {
      type = types.lines;
      default = "";
    }; # :init
    config = mkOption {
      type = types.lines;
      default = "";
    }; # :config
    assembly = mkOption {
      type = types.lines;
      readOnly = true;
      internal = true;
      description = "The complete generated use-package form for this entry.";
    };
  };

  config.assembly = concatStringsSep "\n" (
    [ "(use-package ${name}" ]
    ++ boolKw "demand" config.demand
    ++ deferKw config.defer
    ++ listKw "after" config.after
    ++ listKw "commands" config.commands
    ++ listKw "defines" config.defines
    ++ listKw "functions" config.functions
    ++ listKw "mode" config.mode
    ++ listKw "interpreter" config.interpreter
    ++ listKw "hook" config.hook
    ++ pairsKw "bind" bindPair config.bind
    ++ pairsKw "bind*" bindPair config.bind'
    ++ pairsKw "bind-keymap" bindPair config.bindKeyMap
    ++ bindLocalKw config.bindLocal
    # NOTE: :custom attribute NAMES are spliced unescaped (rycee parity);
    # exotic quoted-attr names are the catalog author's responsibility.
    ++ pairsKw "custom" (var: v: "(${var} ${toElisp v})") config.custom
    ++ linesKw "init" config.init
    ++ linesKw "config" config.config
    ++ [ "  )" ]
  );
}
```

- [ ] **Step 6: Create `modules/use-package.nix`** (full file)

```nix
# The single flat namespace: usePackage.<name> — keys are emacs
# feature/package names; freeform (any key is a fully-typed entry).
{ lib, pkgs, ... }:
{
  options.usePackage = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [ ./lib/use-package-type.nix ];
        # Required: neither top-level specialArgs nor _module.args reach
        # submodules (verified in bare evalModules AND under NixOS).
        specialArgs = { inherit pkgs; };
        # REQUIRED: the type declares an option named `config`, and entries
        # set it in shorthand (usePackage.foo = { config = "..."; }). Raw
        # submoduleWith defaults shorthandOnlyDefinesConfig = false, which
        # parses such entries as full modules and breaks them
        # (types.submodule hardcodes true; verified).
        shorthandOnlyDefinesConfig = true;
      }
    );
    default = { };
    description = "use-package entries emitted into the generated init.";
  };
}
```

- [ ] **Step 7: Rewrite `modules/generation.nix`** (full file)

```nix
{ config, lib, ... }:
let
  inherit (lib)
    filterAttrs
    mapAttrsToList
    concatStringsSep
    mkOption
    types
    ;
  enabled = filterAttrs (_: p: p.enable) config.usePackage;
in
{
  options.build.initText = mkOption {
    type = types.lines;
    default = "";
    description = "Generated init.el body: enabled entries' use-package forms in attribute-name order.";
  };
  config.build.initText = concatStringsSep "\n\n" (mapAttrsToList (_: p: p.assembly) enabled);
}
```

- [ ] **Step 8: Rewrite `modules/build.nix`** (full file)

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrValues
    concatMap
    filterAttrs
    makeBinPath
    mkOption
    types
    unique
    ;
  enabled = attrValues (filterAttrs (_: p: p.enable) config.usePackage);
  # No name resolution: option values ARE the derivations (null = built-in).
  # extraPackages: per-entry elisp installed without a use-package form —
  # symmetric with runtimePackages (build-level coverage arrives with the
  # first catalog entry that uses it).
  elispPkgs = unique (
    map (p: p.package) (builtins.filter (p: p.package != null) enabled)
    ++ concatMap (p: p.extraPackages) enabled
  );
  runtimePkgs = unique (concatMap (p: p.runtimePackages) enabled);
  epkgs = pkgs.emacsPackages;
  # NOTE: build.initText is spliced verbatim into this '' string. Catalog
  # elisp containing a literal ${...} would be Nix-interpolated or error —
  # escape as ''${ when it first appears. https://github.com/djacu/ennoix/issues/2
  # Always wrap with a header + (provide 'default): a truly EMPTY default.el
  # fails native-compilation on emacs 30.2 (native-compiler-error-empty-byte).
  defaultEl = epkgs.trivialBuild {
    pname = "default";
    version = "0";
    src = pkgs.runCommand "ennoix-default-src" { } ''
      mkdir -p "$out"
      cp ${
        pkgs.writeText "default.el" ''
          ;;; default.el --- ennoix generated config  -*- lexical-binding: t; -*-
          ${config.build.initText}
          (provide 'default)
          ;;; default.el ends here
        ''
      } "$out/default.el"
    '';
    packageRequires = elispPkgs;
  };
  emacsPkg = epkgs.withPackages (_: elispPkgs ++ [ defaultEl ]);
  # runtimePackages: wrap EVERY binary (emacs, emacsclient, etags, ...) so
  # the binaries are on PATH purely (emacs derives exec-path from PATH).
  # When empty, the output is byte-identical to the unwrapped package.
  withRuntime =
    if runtimePkgs == [ ] then
      emacsPkg
    else
      pkgs.symlinkJoin {
        name = "ennoix-${emacsPkg.name}";
        paths = [ emacsPkg ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          for prog in "$out"/bin/*; do
            wrapProgram "$prog" --prefix PATH : "${makeBinPath runtimePkgs}"
          done
        '';
        inherit (emacsPkg) meta;
      };
in
{
  options.build.package = mkOption {
    type = types.package;
    description = "The final runnable emacs (runtime-wrapped when any entry declares runtimePackages).";
  };
  config.build.package = withRuntime;
}
```

- [ ] **Step 9: Create `modules/catalog/vertico/module.nix`** (full file)

```nix
{ mkCatalogDefault, ... }:
{
  usePackage.vertico.init = mkCatalogDefault "(vertico-mode 1)";
}
```

- [ ] **Step 10: Create `modules/eval.nix`** (full file)

```nix
# ennoixEval's substance: assemble baseModules (namespace + generation +
# build + the collected catalog) and evaluate user modules against them.
{ lib, pkgs }:
let
  catalogDir = ./catalog;
  # Every DIRECTORY under modules/catalog is an entry; its module MUST be
  # named module.nix. A misnamed module fails naturally at import
  # ("path '.../module.nix' does not exist", naming the entry).
  catalogModules = map (name: catalogDir + "/${name}/module.nix") (
    builtins.attrNames (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir catalogDir)
    )
  );
  baseModules = [
    ./use-package.nix
    ./generation.nix
    ./build.nix
  ]
  ++ catalogModules;
in
modules:
(lib.evalModules {
  modules = baseModules ++ modules;
  specialArgs = {
    inherit pkgs;
    mkCatalogDefault = lib.mkOverride 1400;
  };
}).config
```

- [ ] **Step 11: Create `overlays/top-level/ennoixEval/package.nix`** (full file)

```nix
# The ennoix eval entrypoint: modules -> config. callPackage'd by the
# top-level slot, so pkgs.ennoixEval gains .override { pkgs = ...; }.
{ lib, pkgs }:
import ../../../modules/eval.nix { inherit lib pkgs; }
```

- [ ] **Step 12: Rewrite `overlays/default.nix`** (full file; deletes the `ennoix` overlay, adds the `tests` and `emacs-packages` slots)

```nix
inputs:
let

  # inherits

  inherit (inputs.nixpkgs-lib)
    lib
    ;

  inherit (lib.filesystem)
    listFilesRecursive
    packagesFromDirectoryRecursive
    ;

  inherit (lib.fixedPoints)
    composeManyExtensions
    ;

  inherit (lib.lists)
    filter
    ;

  # overlays

  # Fixes for upstream nixpkgs packages with broken hashes or other issues
  fixes = composeManyExtensions (
    map import (filter (path: baseNameOf path == "overlay.nix") (listFilesRecursive ./fixes))
  );

  top-level =
    final: prev:
    packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      inherit (prev) newScope;
      directory = ./top-level;
    };

  python-packages = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (
        python-final: _python-prev:
        packagesFromDirectoryRecursive {
          inherit (python-final) callPackage newScope;
          directory = ./python-packages;
        }
      )
    ];
  };

  verification =
    final: prev:
    packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      inherit (prev) newScope;
      directory = ./verification;
    };

  # ennoix test derivations; hydra-jobs/tests.nix collects this slot by
  # directory name (the same jobset<->directory pairing as packages.nix).
  tests =
    final: prev:
    packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      inherit (prev) newScope;
      directory = ./tests;
    };

  # ennoix's emacs-scope extension: catalog-gap packages as
  # emacs-packages/<name>/package.nix, callPackage'd against the SCOPE
  # (with pkgs fallback). Wraps the FUNCTION so every produced scope —
  # pkgs.emacsPackages, emacs.pkgs, variant bases — carries the extension.
  emacs-packages = _final: prev: {
    emacsPackagesFor =
      emacs:
      (prev.emacsPackagesFor emacs).overrideScope (
        eself: _esuper:
        packagesFromDirectoryRecursive {
          inherit (eself) callPackage newScope;
          directory = ./emacs-packages;
        }
      );
  };

  default = composeManyExtensions [
    fixes
    top-level
    python-packages
    verification
    tests
    emacs-packages
  ];

in
{
  inherit
    default
    emacs-packages
    fixes
    python-packages
    tests
    top-level
    ;
}
```

- [ ] **Step 13: Rewrite `modules/eval-tests.nix`** (walking-skeleton suite; full file)

```nix
# Pure-eval tests through the real entrypoint. `lib.runTests` -> [] when all pass.
# Emitter-shape EQUALITY tests on per-entry assembly paths (no hasInfix).
{
  lib,
  ennoixEval,
  hello,
}:
let
  cfg = modules: ennoixEval modules;
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
    expr = lib.hasPrefix "ennoix-" (cfg [
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
```

- [ ] **Step 14: Create `overlays/tests/ennoix-tests-eval/package.nix`** (full file)

```nix
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
```

- [ ] **Step 15: Rewrite `hydra-jobs/tests.nix`** (full file)

```nix
{
  supportedSystems ? [
    "aarch64-linux"
    "x86_64-linux"
  ],
  evalSystem ? builtins.currentSystem or "x86_64-linux",
  nixpkgs ? null,
}@args:
let
  inherit (import ./common.nix args) lib releaseLib self;
  inherit (releaseLib) pkgs;
  inherit (self.library.paths) getDirectoryNames;
  inherit (lib.attrsets) getAttrs recurseIntoAttrs;
in
# Single-eval-system jobset (no mapTestOn; test derivations carry no
# meta.platforms). Collected purely by path from overlays/tests — the same
# jobset<->directory pairing as packages.nix <-> overlays/top-level.
recurseIntoAttrs {
  ennoix = recurseIntoAttrs (getAttrs (getDirectoryNames ../overlays/tests) pkgs);
}
```

- [ ] **Step 16: Stage everything, then GREEN**

```bash
git add -A
nix build .#legacyPackages.x86_64-linux.ennoix-tests-eval -L
```

Expected: builds (store path printed). A `lib.runTests` failure would surface as `error: ennoix eval tests failed: …` naming the failing test — fix the discrepancy before proceeding (the expected strings above are exact).

- [ ] **Step 17: Whole-flake sanity**

Run: `nix flake check --no-build && nix fmt && nix build .#checks.x86_64-linux.formatting`
Expected: all pass (aarch64 "omitted incompatible systems" warning is pre-existing and fine).

- [ ] **Step 18: Commit**

```bash
git add -A
git commit -m "refactor: re-architect core — ennoixEval + usePackage namespace + slots"
```

______________________________________________________________________

## Task 2: Catalog completion + the override-replacement contract

**Files:**

- Create: `modules/catalog/{orderless,marginalia,savehist,which-key,modus-themes,magit}/module.nix`
- Modify: `modules/eval-tests.nix` (add 6 tests; keep all Task-1 tests)

**Interfaces:**

- Consumes: `mkCatalogDefault` specialArg; `usePackage.<key>.{init,config,bind,package}` option paths; catalog directory contract from Task 1.

- Produces: catalog keys `orderless`, `marginalia`, `savehist`, `which-key`, `modus-themes`, `magit` (exact `usePackage` keys — Task 3 enables them by these names).

- [ ] **Step 1: Add the failing tests** (into `modules/eval-tests.nix`'s `lib.runTests` set)

```nix
  testOrderlessAssembly = {
    expr = assemblyOf "orderless" [ { usePackage.orderless.enable = true; } ];
    expected = "(use-package orderless\n  :config (setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))\n  )";
  };
  testMagitAssembly = {
    expr = assemblyOf "magit" [ { usePackage.magit.enable = true; } ];
    expected = "(use-package magit\n  :bind ((\"C-x g\" . magit-status))\n  )";
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
```

- [ ] **Step 2: RED**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix-tests-eval 2>&1 | tail -5`
Expected: FAIL — `error: savehist cannot be found in pkgs.emacsPackages`: `testSavehistIsBuiltin` forces the `mkPackageOption` declaration default before the catalog module defines `package = null`, and savehist (a core-emacs feature) has no `emacsPackages` attr. The throw aborts the whole `runTests` evaluation, so no per-test failure list is printed. (Once the catalog modules exist, orderless/magit would otherwise fail as string-mismatch records; the modus-themes and override-replacement tests already pass pre-catalog — that is expected.)

- [ ] **Step 3: Create the six catalog modules**

`modules/catalog/orderless/module.nix`:

```nix
{ mkCatalogDefault, ... }:
{
  usePackage.orderless.config = mkCatalogDefault "(setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))";
}
```

`modules/catalog/marginalia/module.nix`:

```nix
{ mkCatalogDefault, ... }:
{
  usePackage.marginalia.init = mkCatalogDefault "(marginalia-mode 1)";
}
```

`modules/catalog/savehist/module.nix`:

```nix
{ mkCatalogDefault, ... }:
{
  usePackage.savehist = {
    package = mkCatalogDefault null; # ships with emacs; install nothing
    init = mkCatalogDefault "(savehist-mode 1)";
  };
}
```

`modules/catalog/which-key/module.nix`:

```nix
{ mkCatalogDefault, ... }:
{
  usePackage.which-key = {
    package = mkCatalogDefault null; # built into emacs >= 30
    init = mkCatalogDefault "(which-key-mode 1)";
  };
}
```

`modules/catalog/modus-themes/module.nix`:

```nix
{ mkCatalogDefault, ... }:
{
  # Deliberately a PACKAGE (package defaults to pkgs.emacsPackages.modus-themes):
  # emacs bundles the modus library only under etc/themes (off load-path), so
  # use-package's require fails for the built-in; the package also keeps the
  # entry overridable. See the builtIn-vs-package policy record.
  usePackage.modus-themes.config = mkCatalogDefault "(load-theme 'modus-operandi :no-confirm)";
}
```

`modules/catalog/magit/module.nix`:

```nix
{ mkCatalogDefault, ... }:
{
  # :bind defers magit (autoloads on C-x g; not eager-loaded at startup).
  usePackage.magit.bind = mkCatalogDefault {
    "C-x g" = "magit-status";
  };
}
```

- [ ] **Step 4: GREEN**

```bash
git add -A
nix build .#legacyPackages.x86_64-linux.ennoix-tests-eval -L
```

Expected: builds (all 18 tests pass — 12 from Task 1, 6 from this task).

- [ ] **Step 5: Commit**

```bash
nix fmt
git add -A
git commit -m "feat: catalog — the Phase-0 seven as mkCatalogDefault modules"
```

______________________________________________________________________

## Task 3: Packages, flake output, load gates

**Files:**

- Create: `overlays/top-level/ennoix-emacs/package.nix`, `overlays/top-level/ennoix-emacs-full/package.nix`, `overlays/tests/ennoix-tests-load/package.nix`, `overlays/tests/ennoix-tests-load-full/package.nix`
- Modify: `flake.nix` (restore `packages`)

**Interfaces:**

- Consumes: `pkgs.ennoixEval` (`[module] -> config`, `.build.package`), catalog keys from Task 2, `self.library.systems.defaultSystems`.

- Produces: `pkgs.ennoix-emacs`, `pkgs.ennoix-emacs-full` (derivations), flake `packages.<system>.default`, `pkgs.ennoix-tests-load`, `pkgs.ennoix-tests-load-full`.

- [ ] **Step 1: Create the load gates first (the RED)**

`overlays/tests/ennoix-tests-load/package.nix`:

```nix
# --batch load gate for the flagship package. Catches STARTUP-time errors
# only; deferred :config bodies never run in --batch.
# https://github.com/djacu/ennoix/issues/4
{ runCommand, ennoix-emacs }:
runCommand "ennoix-tests-load" { } ''
  export HOME=$(mktemp -d)
  ${ennoix-emacs}/bin/emacs --batch \
    --eval '(package-activate-all)' \
    --eval '(load (locate-library "default") nil t)' \
    --eval '(message "ennoix-config-loaded-ok")' > log 2>&1 \
    || { echo "emacs exited non-zero:"; cat log; exit 1; }
  if grep -qiE 'error \(|lisp error|definition is void|wrong type|void-(function|variable)' log; then
    echo "config produced an error at load:"; cat log; exit 1
  fi
  grep -q 'ennoix-config-loaded-ok' log || { echo "missing success marker:"; cat log; exit 1; }
  touch $out
''
```

`overlays/tests/ennoix-tests-load-full/package.nix`: identical except the header line, the argument, and names — `{ runCommand, ennoix-emacs-full }:`, `runCommand "ennoix-tests-load-full"`, and `${ennoix-emacs-full}/bin/emacs`.

- [ ] **Step 2: RED**

```bash
git add -A
nix build .#legacyPackages.x86_64-linux.ennoix-tests-load 2>&1 | tail -3
```

Expected: FAIL — `ennoix-emacs` cannot be resolved by callPackage (`Function called without required argument "ennoix-emacs"` or similar): the package doesn't exist yet.

- [ ] **Step 3: Create the packages**

`overlays/top-level/ennoix-emacs/package.nix`:

```nix
# The flagship `nix run` demo: curated starter (the Phase-0 seven,
# hand-listed — the flagship's contents are editorial).
{ ennoixEval }:
(ennoixEval [
  {
    usePackage = {
      magit.enable = true;
      marginalia.enable = true;
      modus-themes.enable = true;
      orderless.enable = true;
      savehist.enable = true;
      vertico.enable = true;
      which-key.enable = true;
    };
  }
]).build.package
```

`overlays/top-level/ennoix-emacs-full/package.nix`:

```nix
# The ENTIRE catalog enabled — build coverage. Enables are derived
# structurally from the catalog directory names (dir name IS the
# usePackage key); never hand-listed.
# NOTE: flakes copy the git INDEX — `git add` new catalog entries or local
# -full builds will include drafts that CI (clean checkout) will not see.
{ ennoixEval, lib }:
(ennoixEval [
  {
    usePackage = lib.genAttrs (builtins.attrNames (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../../../modules/catalog)
    )) (_: { enable = true; });
  }
]).build.package
```

- [ ] **Step 4: Restore the flake `packages` output.** In `flake.nix`'s `outputs` block, add:

```nix
    packages = inputs.self.library.systems.defaultSystems (system: {
      default = inputs.self.legacyPackages.${system}.ennoix-emacs;
    });
```

- [ ] **Step 5: GREEN — build both gates** (compiles magit + deps; takes minutes)

```bash
git add -A
nix build .#legacyPackages.x86_64-linux.ennoix-tests-load .#legacyPackages.x86_64-linux.ennoix-tests-load-full -L
```

Expected: both build.

- [ ] **Step 6 (optional RED sanity — proves the gate is non-vacuous after the mechanism swap):** temporarily set `usePackage.vertico.init = mkCatalogDefault "(this-function-does-not-exist)"` in `modules/catalog/vertico/module.nix`, `git add`, run the Step-5 build, confirm it FAILS with `Symbol's function definition is void`; then revert and `git add` again.

- [ ] **Step 7: Commit**

```bash
nix fmt
git add -A
git commit -m "feat: ennoix-emacs + ennoix-emacs-full + load gates + nix run"
```

______________________________________________________________________

## Task 4: Full verification sweep + issue housekeeping

**Files:** none created; possible formatting-only changes.

**Interfaces:** consumes everything above.

- [ ] **Step 1: Format + fast whole-flake checks**

Run: `nix fmt && nix build .#checks.x86_64-linux.formatting && nix flake check --no-build`
Expected: all pass.

- [ ] **Step 2: Both hydra jobsets through the real runner**

Run: `nix run .#verify-hydra-jobset -- hydra-jobs/tests.nix && nix run .#verify-hydra-jobset -- hydra-jobs/packages.nix`
Expected: tests jobset builds `ennoix.ennoix-tests-{eval,load,load-full}`; packages jobset builds `ennoix-emacs`/`ennoix-emacs-full`. `ennoixEval` appears as a harmless EMPTY job (release-lib maps non-derivations to `{ }` — expected, not an error).

- [ ] **Step 3: Runtime smoke test (activation + deferral survived the re-architecture)**

```bash
nix build .#default -o /tmp/ennoix-smoke
HOME=$(mktemp -d) /tmp/ennoix-smoke/bin/emacs --batch \
  --eval '(package-activate-all)' \
  --eval '(load (locate-library "default") nil t)' \
  --eval '(princ (format "vertico=%s magit-bound=%s magit-loaded=%s theme=%s\n" (bound-and-true-p vertico-mode) (fboundp (quote magit-status)) (featurep (quote magit)) (and (member (quote modus-operandi) custom-enabled-themes) t)))'
rm /tmp/ennoix-smoke
```

Expected output line: `vertico=t magit-bound=t magit-loaded=nil theme=t` (magit bound but DEFERRED; theme applied).

- [ ] **Step 4: Close issue #5 (spec §9 disposition)**

```bash
gh issue close 5 --comment "Resolved by the re-architecture (docs/superpowers/specs/2026-07-06-ennoix-rearchitecture-design.md §9): build.emacsWithPackages is dropped; the home-manager adapter plan will introduce what it actually needs."
```

(#2 and #4 stay open — their notes carry to the new code sites; #3 stays open — tier-1 covers emission shapes, not load behavior of every keyword.)

- [ ] **Step 5: Commit any formatting stragglers**

```bash
git add -A
git commit -m "chore: nix fmt" || echo "nothing to commit"
```

______________________________________________________________________

## Self-Review

**Spec coverage:** §2 layering → Task 1 (library restore, slots, `ennoixEval` in top-level, `emacs-packages` pFDR wrap, `.gitkeep`); §3 → Task 1 (`eval.nix`, callPackage'd package.nix, `build.package` projection); §4 → Task 1 (`use-package.nix` + shared type, all fields incl. structured `bind`/`custom`, `commands` rename, `assembly`); §5 → Tasks 1–2 (collector in `eval.nix`, 7 catalog modules, `mkCatalogDefault` 1400, dir-name==key); §6 → Task 1 (`generation.nix` lexicographic + blank-line join, `build.nix` with runtime wrapper + issue-#2/native-comp comments); §7 → Task 3 (flagship hand-listed, `-full` structural, `.build.package` projection, flake default); §8 → Tasks 1–3 (eval equality suite + override-replacement + runtime-branch probes; build coverage via `-full`; both `--batch` gates with the issue-#4 note; tests slot + path-collected `hydra-jobs/tests.nix`; VM tier has no task — deferred by spec); §9 → Tasks 1 (deletions/rewrites) and 4 (issue #5). Docs task (old-spec status line) — already done in the spec commit. ✓

**Placeholder scan:** every code step carries full file contents or exact insertions; the one "identical except" (Task 3 load-full gate) names each difference explicitly. ✓

**Type consistency:** `ennoixEval : [module] -> config` used identically in Tasks 1/3; `assemblyOf`/`cfg` helpers defined in Task 1's eval-tests and reused by Task 2's additions; catalog keys in Task 2 match Task 3's enables; `hello` threading matches between eval-tests.nix and its package.nix. Expected assembly strings follow the Task-1 emitter exactly (keyword order: demand, defer, after, commands, defines, functions, mode, interpreter, hook, bind, bind\*, bind-keymap, bindLocal, custom, init, config; two-space indent; dangling `  )`; attrs iterate lexicographically). Revised after the three-lens adversarial review (`shorthandOnlyDefinesConfig = true` — the critical fix; `mkdir -p` before the `.gitkeep`; corrected RED expectations; counts) and extended with the full built-in keyword set + `extraPackages` per the ratified spec update; the extended emitter and the `config`-key shorthand case are spike-verified. ✓
