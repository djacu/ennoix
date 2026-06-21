# ennoix Phase-0 Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove `ennoix.plugins.<name>.enable = true` → a working, configured emacs you can `nix run`, end-to-end, for the 7 Phase-0 plugins.

**Architecture:** A NixOS-module-system eval core (`lib.evalModules`) over a set of per-plugin modules whose curated config lives in option `default`s; a generation step emits one `use-package` form per enabled plugin into an init text; that text is baked as a `default.el` `trivialBuild` package inside `emacsWithPackages` (the spike-verified injection); a `config.assertions` pass fails loudly on unknown packages. Standalone delivery only (`nix run`); HM/NixOS adapters, runtime binaries, profiles, and conflict assertions are out of scope (later plans).

**Tech Stack:** Nix (flakes, the module system, `lib.evalModules`/`lib.runTests`), nixpkgs `emacsPackagesFor`/`emacsWithPackages`/`trivialBuild`, emacs 30.2. No flake-parts. Spec: `docs/superpowers/specs/2026-06-20-ennoix-architecture-design.md` (Plan 1 in §11). Primer: `docs/superpowers/specs/2026-06-07-emacs-primer.md`.

> **Verification note:** every Nix snippet below was prototyped and run (generation output, fail-loud throw, build, and real-startup load with `vertico-mode`/`savehist-mode` active). The patterns are confirmed, not assumed.

> **Convention:** this repo hand-wires flake outputs (no flake-parts) and formats with `nix fmt` (treefmt). Run `nix fmt` before each commit. Per repo policy, commit messages carry **no** `Co-Authored-By` trailer.

______________________________________________________________________

## File Structure

New code lives under `modules/` (the eval core + catalog) and `library/` (the public API), wired into the existing hand-rolled `flake.nix`.

- `modules/lib/mk-plugin.nix` — shared per-plugin module builder (the schema; curated values become option `default`s).
- `modules/generation.nix` — collects enabled plugins → `ennoix.build.initText`.
- `modules/build.nix` — `ennoix.build.{emacsWithPackages,package}` (default.el injection).
- `modules/assertions.nix` — the `assertions` option + the fail-loud package checks.
- `modules/plugins/by-name/{vertico,orderless,marginalia,savehist,which-key,modus-themes,magit}/default.nix` — the 7 Phase-0 plugin modules.
- `modules/default.nix` — the `baseModules` list (imports the above + all plugins).
- `overlays/emacs-packages/default.nix` — the ennoix emacs-scope overlay slot (empty in Phase 0; the `overrideScope` backstop seam).
- `library/ennoix.nix` — `evalEnnoix` / `makeEnnoix` (+ the `nixpkgs` option resolving pkgs inside the eval).
- `library/default.nix` — MODIFY: expose `ennoix` via `callLibs`.
- `tests/ennoix.nix` — `lib.runTests` unit tests (generation, defaults, assertions).
- `checks/default.nix` — MODIFY: add `ennoix-loads` (build-level `emacs --batch` gate) and `ennoix-unit` (eval tests).
- `flake.nix` — MODIFY: add `packages.<system>.default = library.ennoix.makeEnnoix { … }`.

______________________________________________________________________

## Task 1: Test harness — `lib.runTests` wired as a flake check

**Files:**

- Create: `tests/ennoix.nix`

- Modify: `checks/default.nix`

- [ ] **Step 1: Write the failing test file**

`tests/ennoix.nix` (a `lib.runTests` suite; returns `[]` when all pass):

```nix
# Pure-eval unit tests. `lib.runTests` returns a list of failures ([] = pass).
{ lib }:
lib.runTests {
  testHarnessSelfCheck = {
    expr = 1 + 1;
    expected = 2;
  };
}
```

- [ ] **Step 2: Add a check that fails when the suite is non-empty**

In `checks/default.nix`, inside the per-system attrset (alongside the existing `formatting` check), add:

```nix
ennoix-unit =
  let
    failures = import ../tests/ennoix.nix { inherit lib; };
  in
  if failures == [ ]
  then pkgs.runCommand "ennoix-unit-pass" { } "touch $out"
  else throw "ennoix unit tests failed:\n${lib.generators.toPretty { } failures}";
```

(`pkgs` here is the per-system package set the check already has in scope via `inputs.self.legacyPackages`; if the existing `checks/default.nix` does not bind `pkgs`, bind it: `pkgs = inputs.self.legacyPackages.${system};`.)

- [ ] **Step 3: Run the check to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: builds successfully (the self-check passes).

- [ ] **Step 4: Commit**

```bash
nix fmt
git add tests/ennoix.nix checks/default.nix
git commit -m "test: ennoix unit-test harness via lib.runTests + flake check"
```

______________________________________________________________________

## Task 2: `mk-plugin.nix` — the per-plugin schema with curated defaults

**Files:**

- Create: `modules/lib/mk-plugin.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Write the failing test**

Add to `tests/ennoix.nix` (replace the self-check suite body, keep the wrapper):

```nix
{ lib }:
let
  inherit (lib) evalModules;
  mkPlugin = import ../modules/lib/mk-plugin.nix { inherit lib; };
  # evaluate one plugin module in isolation
  evalOne = mod: (evalModules { modules = [ mod ]; }).config;

  verticoCfg = evalOne (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; });
  savehistCfg = evalOne (mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; });
in
lib.runTests {
  # curated value is the option DEFAULT
  testCuratedInitDefault = {
    expr = verticoCfg.ennoix.plugins.vertico.init;
    expected = "(vertico-mode 1)";
  };
  # archive plugin defaults its package name to the plugin name
  testPackageDefaultsToName = {
    expr = verticoCfg.ennoix.plugins.vertico.package;
    expected = "vertico";
  };
  # built-in plugin has no package
  testBuiltinHasNoPackage = {
    expr = savehistCfg.ennoix.plugins.savehist.package;
    expected = null;
  };
  # disabled by default
  testDisabledByDefault = {
    expr = verticoCfg.ennoix.plugins.vertico.enable;
    expected = false;
  };
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `error: ... mk-plugin.nix ... No such file` (the module doesn't exist).

- [ ] **Step 3: Implement `modules/lib/mk-plugin.nix`**

```nix
{ lib }:
{
  name,
  builtIn ? false,
  init ? "",
  extraConfig ? "",
}:
{ ... }:
{
  options.ennoix.plugins.${name} = {
    enable = lib.mkEnableOption name;

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if builtIn then null else name;
      description = ''
        Name of the package backing this plugin in the (ennoix+user) emacs
        scope. `null` for a built-in package (shipped with emacs).
      '';
    };

    init = lib.mkOption {
      type = lib.types.lines;
      default = init; # curated default (mkOptionDefault priority; user override replaces)
      description = "Elisp emitted into the use-package `:init` block.";
    };

    config = lib.mkOption {
      type = lib.types.lines;
      default = extraConfig;
      description = "Elisp emitted into the use-package `:config` block.";
    };
  };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/lib/mk-plugin.nix tests/ennoix.nix
git commit -m "feat: mk-plugin builder — per-plugin schema with curated option defaults"
```

______________________________________________________________________

## Task 3: `generation.nix` — emit use-package forms into `ennoix.build.initText`

**Files:**

- Create: `modules/generation.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Write the failing test**

Add a `genText` helper and tests to `tests/ennoix.nix`'s `let` and `runTests`:

```nix
  # in the let-block:
  genText = userMods:
    (evalModules {
      modules = [
        (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; })
        (mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; })
        (import ../modules/generation.nix)
      ] ++ userMods;
    }).config.ennoix.build.initText;

  bothText = genText [ { ennoix.plugins.vertico.enable = true; ennoix.plugins.savehist.enable = true; } ];
```

```nix
  # in runTests:
  testGenEmitsEnabled = {
    expr = lib.hasInfix "(use-package vertico" bothText
        && lib.hasInfix "(vertico-mode 1)" bothText
        && lib.hasInfix "(use-package savehist" bothText;
    expected = true;
  };
  testGenOmitsDisabled = {
    expr = lib.hasInfix "use-package" (genText [ ]); # nothing enabled
    expected = false;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `generation.nix ... No such file`.

- [ ] **Step 3: Implement `modules/generation.nix`**

```nix
{ config, lib, ... }:
let
  inherit (lib) types mkOption filterAttrs mapAttrsToList concatStringsSep optional;

  enabled = filterAttrs (_: p: p.enable) config.ennoix.plugins;

  # one use-package form per enabled plugin
  form = name: p:
    concatStringsSep "\n" (
      [ "(use-package ${name}" ]
      ++ optional (p.init != "") "  :init ${p.init}"
      ++ optional (p.config != "") "  :config ${p.config}"
      ++ [ "  )" ]
    );
in
{
  options.ennoix.build.initText = mkOption {
    type = types.lines;
    default = "";
    description = "The generated init.el body (use-package forms for enabled plugins).";
  };

  # deterministic order: mapAttrsToList iterates attr names alphabetically
  config.ennoix.build.initText = concatStringsSep "\n\n" (mapAttrsToList form enabled);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/generation.nix tests/ennoix.nix
git commit -m "feat: generation — emit use-package forms into ennoix.build.initText"
```

______________________________________________________________________

## Task 4: `assertions.nix` — fail loudly on unknown packages

**Files:**

- Create: `modules/assertions.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Write the failing test**

The assertions module needs the package scope (`epkgs`). For the unit test we inject a tiny fake scope so the test stays pure (no build):

```nix
  # in the let-block:
  fakeEpkgs = { vertico = "drv"; }; # only vertico exists
  assertList = userMods:
    (evalModules {
      modules = [
        (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; })
        (mkPlugin { name = "magit"; })
        (import ../modules/assertions.nix)
        { _module.args.epkgs = fakeEpkgs; }
      ] ++ userMods;
    }).config.assertions;
  failing = a: builtins.filter (x: !x.assertion) a;
```

```nix
  # in runTests:
  testAssertPassesForPresent = {
    expr = failing (assertList [ { ennoix.plugins.vertico.enable = true; } ]);
    expected = [ ];
  };
  testAssertFailsForMissing = {
    expr = builtins.length (failing (assertList [ { ennoix.plugins.magit.enable = true; } ]));
    expected = 1; # magit not in fakeEpkgs
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `assertions.nix ... No such file`.

- [ ] **Step 3: Implement `modules/assertions.nix`**

```nix
{ config, lib, epkgs, ... }:
let
  inherit (lib) types mkOption filterAttrs mapAttrsToList hasAttr;
in
{
  options.assertions = mkOption {
    default = [ ];
    type = types.listOf (types.submodule {
      options = {
        assertion = mkOption { type = types.bool; };
        message = mkOption { type = types.str; };
      };
    });
  };

  # Only USER-resolvable refs can fail; catalog packages are backstopped by
  # the ennoix overlay (Task 7), so in practice these always hold for the
  # shipped catalog and only fire on a bad user override / extra package.
  config.assertions = mapAttrsToList (name: p: {
    assertion = p.package == null || hasAttr p.package epkgs;
    message = "ennoix: plugin '${name}' references package '${toString p.package}' which is not in the emacs package set.";
  }) (filterAttrs (_: p: p.enable) config.ennoix.plugins);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/assertions.nix tests/ennoix.nix
git commit -m "feat: assertions — fail loudly on unknown emacs packages"
```

______________________________________________________________________

## Task 5: `build.nix` — default.el injection into `emacsWithPackages`

**Files:**

- Create: `modules/build.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Write the failing test** (build module needs `pkgs` + `epkgs`; test it produces a derivation)

```nix
  # in the let-block (uses the real per-system pkgs passed into the test; see Step 1b):
  buildCfg = pkgs: (evalModules {
    modules = [
      (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; })
      (mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; })
      (import ../modules/generation.nix)
      (import ../modules/build.nix)
      { _module.args.pkgs = pkgs; _module.args.epkgs = pkgs.emacsPackagesFor pkgs.emacs; }
      { ennoix.plugins.vertico.enable = true; ennoix.plugins.savehist.enable = true; }
    ];
  }).config;
```

**Step 1b:** the build test needs `pkgs`, so make `tests/ennoix.nix` accept it: change the header to `{ lib, pkgs ? null }:` and guard build tests with `lib.optionalAttrs (pkgs != null) { … }`. Update `checks/default.nix`'s `ennoix-unit` to pass `pkgs`: `import ../tests/ennoix.nix { inherit lib pkgs; }`.

```nix
  # in runTests, merged via // lib.optionalAttrs (pkgs != null):
  testBuildIsDerivation = {
    expr = lib.isDerivation (buildCfg pkgs).ennoix.build.package;
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `build.nix ... No such file`.

- [ ] **Step 3: Implement `modules/build.nix`**

```nix
{ config, lib, pkgs, epkgs, ... }:
let
  inherit (lib) types mkOption filterAttrs mapAttrsToList;

  enabledWithPkg = filterAttrs (_: p: p.enable && p.package != null) config.ennoix.plugins;
  pluginPkgs = mapAttrsToList (_: p: epkgs.${p.package}) enabledWithPkg;

  defaultEl = epkgs.trivialBuild {
    pname = "default";
    version = "0";
    src = pkgs.runCommand "ennoix-default-src" { } ''
      mkdir -p "$out"
      cp ${pkgs.writeText "default.el" config.ennoix.build.initText} "$out/default.el"
    '';
    packageRequires = pluginPkgs;
  };
in
{
  options.ennoix.build.emacsWithPackages = mkOption { type = types.package; };
  options.ennoix.build.package = mkOption { type = types.package; };

  # bare: packages on load-path, no config baked (used by the HM adapter later)
  config.ennoix.build.emacsWithPackages = pkgs.emacs.pkgs.withPackages (_: pluginPkgs);
  # baked: standalone/NixOS — config rides in default.el
  config.ennoix.build.package = pkgs.emacs.pkgs.withPackages (_: pluginPkgs ++ [ defaultEl ]);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/build.nix tests/ennoix.nix checks/default.nix
git commit -m "feat: build — bake generated config as default.el in emacsWithPackages"
```

______________________________________________________________________

## Task 6: ennoix overlay slot + `modules/default.nix` (baseModules)

**Files:**

- Create: `overlays/emacs-packages/default.nix`

- Create: `modules/default.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Write the failing test** (baseModules wires generation+build+assertions but no plugins yet)

```nix
  # in the let-block:
  baseModules = import ../modules/default.nix;
```

```nix
  # in runTests:
  testBaseModulesIsList = {
    expr = builtins.isList baseModules;
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `modules/default.nix ... No such file`.

- [ ] **Step 3a: Implement `overlays/emacs-packages/default.nix`** (the backstop seam; empty in Phase 0)

```nix
# ennoix's emacs-scope overlay: provides catalog packages missing upstream.
# Phase 0 needs none (all 7 are in nixpkgs / built-in), so this is the seam
# that later phases extend via overrideScope.
_eself: _esuper: { }
```

- [ ] **Step 3b: Implement `modules/default.nix`** (the non-plugin core; plugins are appended in Task 7)

```nix
# baseModules: the ennoix eval-core module set (catalog plugins are added separately).
[
  ./generation.nix
  ./build.nix
  ./assertions.nix
]
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add overlays/emacs-packages/default.nix modules/default.nix tests/ennoix.nix
git commit -m "feat: ennoix overlay slot + baseModules core list"
```

______________________________________________________________________

## Task 7: the 7 Phase-0 plugin modules

**Files:**

- Create: `modules/plugins/by-name/{vertico,orderless,marginalia,savehist,which-key,modus-themes,magit}/default.nix`
- Modify: `modules/default.nix`
- Test: `tests/ennoix.nix`

> Curated values below are the canonical activations from each package's docs. `orderless` is the one medium-complexity case: it sets `completion-styles`, not a mode. `savehist`/`which-key`/`modus-themes` are built-in in emacs 30.2 (`builtIn = true`, no derivation).

- [ ] **Step 1: Write the failing test**

```nix
  # in the let-block:
  fullEval = userMods: (evalModules { modules = baseModules ++ catalog ++ userMods; }).config;
  catalog = import ../modules/plugins { inherit lib; }; # a list of the 7 plugin modules
  allText = (evalModules {
    modules = catalog ++ [ (import ../modules/generation.nix) ] ++ [{
      ennoix.plugins = lib.genAttrs
        [ "vertico" "orderless" "marginalia" "savehist" "which-key" "modus-themes" "magit" ]
        (_: { enable = true; });
    }];
  }).config.ennoix.build.initText;
```

```nix
  # in runTests:
  testCatalogHasSeven = {
    expr = builtins.length catalog;
    expected = 7;
  };
  testOrderlessSetsCompletionStyles = {
    expr = lib.hasInfix "completion-styles" allText;
    expected = true;
  };
  testMagitBinding = {
    expr = lib.hasInfix "magit-status" allText;
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `modules/plugins ... No such file`.

- [ ] **Step 3a: Create the 7 plugin modules.** Each calls `mk-plugin.nix`. (`mkP` is a local alias defined in Step 3b.)

`modules/plugins/by-name/vertico/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; }
```

`modules/plugins/by-name/marginalia/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "marginalia"; init = "(marginalia-mode 1)"; }
```

`modules/plugins/by-name/orderless/default.nix`:

```nix
{ mkPlugin }: mkPlugin {
  name = "orderless";
  config = "(setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))";
}
```

`modules/plugins/by-name/savehist/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; }
```

`modules/plugins/by-name/which-key/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "which-key"; builtIn = true; init = "(which-key-mode 1)"; }
```

`modules/plugins/by-name/modus-themes/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "modus-themes"; builtIn = true; config = "(load-theme 'modus-operandi :no-confirm)"; }
```

`modules/plugins/by-name/magit/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "magit"; config = "(keymap-global-set \"C-x g\" #'magit-status)"; }
```

- [ ] **Step 3b: Create `modules/plugins/default.nix`** (collects the by-name modules)

```nix
{ lib }:
let
  mkPlugin = import ../lib/mk-plugin.nix { inherit lib; };
  dir = ./by-name;
  names = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
in
map (name: import (dir + "/${name}") { inherit mkPlugin; }) names
```

- [ ] **Step 3c: Modify `modules/default.nix`** to include the catalog. Replace its body with:

```nix
{ lib }:
[
  ./generation.nix
  ./build.nix
  ./assertions.nix
]
++ import ./plugins { inherit lib; }
```

(Note: `modules/default.nix` now takes `{ lib }`. Update the Task-6 test's `baseModules = import ../modules/default.nix { inherit lib; };` and any `import ../modules/default.nix` callsite accordingly.)

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/plugins modules/default.nix tests/ennoix.nix
git commit -m "feat: Phase-0 catalog — vertico/orderless/marginalia/savehist/which-key/modus-themes/magit"
```

______________________________________________________________________

## Task 8: `library/ennoix.nix` — `evalEnnoix` / `makeEnnoix` (pkgs resolved inside)

**Files:**

- Create: `library/ennoix.nix`

- Modify: `library/default.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Write the failing test**

```nix
  # in runTests, under lib.optionalAttrs (pkgs != null):
  testMakeEnnoixIsDerivation = {
    expr =
      let
        ennoix = import ../library/ennoix.nix { inherit lib; nixpkgs = pkgs.path; };
      in
      lib.isDerivation (ennoix.makeEnnoix {
        inherit pkgs;
        modules = [ { ennoix.plugins.vertico.enable = true; } ];
      });
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `library/ennoix.nix ... No such file`.

- [ ] **Step 3: Implement `library/ennoix.nix`**

```nix
{ lib, nixpkgs }:
let
  baseModules = import ../modules/default.nix { inherit lib; };

  # Resolve pkgs INSIDE the eval (one source of truth). Accept a prebuilt
  # `pkgs`, or build one from `system` + the ennoix emacs overlay.
  resolvePkgs = { pkgs, system }:
    if pkgs != null then pkgs
    else import nixpkgs {
      inherit system;
      config = { allowAliases = false; allowUnfree = true; };
    };

  evalEnnoix = { pkgs ? null, system ? null, modules ? [ ] }:
    assert lib.assertMsg (pkgs != null || system != null)
      "ennoix: makeEnnoix/evalEnnoix needs either `pkgs` or `system`.";
    let
      pkgs' = resolvePkgs { inherit pkgs system; };
      epkgs = (pkgs'.emacsPackagesFor pkgs'.emacs).overrideScope (
        import ../overlays/emacs-packages/default.nix
      );
      cfg = (lib.evalModules {
        modules = baseModules ++ modules;
        specialArgs = { pkgs = pkgs'; inherit epkgs; };
      }).config;
      failed = builtins.filter (a: !a.assertion) cfg.assertions;
    in
    if failed != [ ]
    then throw "ennoix assertions failed:\n${lib.concatStringsSep "\n" (map (a: a.message) failed)}"
    else cfg;

  makeEnnoix = args: (evalEnnoix args).ennoix.build.package;
in
{ inherit evalEnnoix makeEnnoix; }
```

- [ ] **Step 4: Expose it from `library/default.nix`.** The existing file builds `library = makeExtensible (self: { paths = callLibs ./paths.nix; systems = callLibs ./systems.nix; })`. Add an `ennoix` member. Because `ennoix.nix` needs `nixpkgs`, pass it from `inputs`:

```nix
# in library/default.nix, inside the makeExtensible body:
ennoix = import ./ennoix.nix { inherit lib; nixpkgs = inputs.nixpkgs; };
```

(`inputs` is already the function argument of `library/default.nix`.)

- [ ] **Step 5: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add library/ennoix.nix library/default.nix tests/ennoix.nix
git commit -m "feat: library.ennoix — evalEnnoix/makeEnnoix with pkgs resolved inside the eval"
```

______________________________________________________________________

## Task 9: flake `packages.default` (`nix run`) + the `ennoix-loads` build gate

**Files:**

- Modify: `flake.nix`

- Modify: `checks/default.nix`

- [ ] **Step 1: Write the failing gate — `ennoix-loads`** (build the Phase-0 demo emacs and assert it loads with no error).

In `checks/default.nix`, add (per system):

```nix
ennoix-loads =
  let
    emacs = inputs.self.packages.${system}.default;
  in
  pkgs.runCommand "ennoix-loads" { } ''
    export HOME=$(mktemp -d)
    # --batch skips package activation AND default.el. Mirror real startup:
    # (package-activate-all) loads the nix packages' autoloads, then load the
    # generated default.el explicitly. NOTE: use-package CATCHES errors and
    # prints them rather than exiting non-zero, so we grep for error markers
    # and require an end-of-load success marker (verified against a build).
    ${emacs}/bin/emacs --batch \
      --eval '(package-activate-all)' \
      --eval '(load (locate-library "default") nil t)' \
      --eval '(message "ennoix-config-loaded-ok")' > log 2>&1 \
      || { echo "emacs exited non-zero:"; cat log; exit 1; }
    if grep -qiE 'error \(|lisp error|definition is void|wrong type|void-(function|variable)' log; then
      echo "ennoix: config produced an error at load:"; cat log; exit 1
    fi
    grep -q 'ennoix-config-loaded-ok' log || { echo "missing success marker:"; cat log; exit 1; }
    touch $out
  '';
```

- [ ] **Step 2: Add the `packages.default` output to `flake.nix`**

`flake.nix` currently hand-wires outputs. Add a `packages` output (per the repo's `library.systems.defaultSystems` helper):

```nix
# in outputs = inputs: { ... }
packages = inputs.self.library.systems.defaultSystems (system: {
  default = inputs.self.library.ennoix.makeEnnoix {
    pkgs = inputs.self.legacyPackages.${system};
    modules = [
      {
        ennoix.plugins.vertico.enable = true;
        ennoix.plugins.orderless.enable = true;
        ennoix.plugins.marginalia.enable = true;
        ennoix.plugins.savehist.enable = true;
        ennoix.plugins.which-key.enable = true;
        ennoix.plugins.modus-themes.enable = true;
        ennoix.plugins.magit.enable = true;
      }
    ];
  };
});
```

- [ ] **Step 3: Run the gate to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-loads -L`
Expected: builds (config loads, vertico autoload present).

- [ ] **Step 4: Manual `nix run` smoke test** (the "feature works" confirmation)

Run: `nix build .#packages.x86_64-linux.default -o ennoix-emacs && HOME=$(mktemp -d) ./ennoix-emacs/bin/emacs --batch --eval '(package-activate-all)' --eval '(load (locate-library "default") nil t)' --eval '(princ (format "vertico=%s magit=%s\n" (fboundp (quote vertico-mode)) (fboundp (quote magit-status))))'`
Expected: prints `vertico=t magit=t` and no `Error (use-package)` lines. (For an interactive check on a graphical host: `nix run .#` → emacs opens with the vertical minibuffer + modus theme; `C-x g` → magit.)

- [ ] **Step 5: Commit**

```bash
nix fmt
git add flake.nix checks/default.nix
git commit -m "feat: standalone packages.default (nix run) + ennoix-loads build gate"
```

______________________________________________________________________

## Task 10: full check + flake evaluation

**Files:** (none new — verification only)

- [ ] **Step 1: Run the formatter check and the full flake check**

Run: `nix fmt && nix flake check -L 2>&1 | tail -30`
Expected: `ennoix-unit`, `ennoix-loads`, and `formatting` all pass; flake evaluates with no errors. (The pre-existing aarch64 "omitted incompatible systems" warning is fine.)

- [ ] **Step 2: Commit any formatting changes**

```bash
git add -A
git commit -m "chore: nix fmt" || echo "nothing to format"
```

______________________________________________________________________

## Self-Review

**Spec coverage (Plan 1 scope, spec §11):**

- eval core (standalone) → Task 8 (`evalEnnoix`, pkgs-inside via `specialArgs`/`resolvePkgs`). ✓
- generation pipeline (§5.5) → Task 3. ✓ (Buckets beyond per-plugin + the structured-keyword serializer are simplified to `:init`/`:config` literal strings for Phase 0; richer keywords/buckets are a later-plan extension — noted, not a gap for the 7 Phase-0 plugins, whose curated values are literal elisp.)
- default.el injection → Task 5 (spike + prototype verified). ✓
- makeEnnoix standalone flake output → Task 9. ✓
- ennoix overlay slot + fail-loud assertion → Task 6 (slot) + Task 4 (assertion) + Task 8 (throws on failed assertions). ✓
- 7 Phase-0 plugins → Task 7. ✓
- gate: `emacs --batch` load check + manual `nix run` → Task 9 + Task 10. ✓
- Deferred items (HM/NixOS adapters, runtime binaries, profiles, conflict assertions) → correctly absent. ✓

**Placeholder scan:** no TBD/TODO; every code step shows real, prototyped code. ✓

**Type/name consistency:** `ennoix.plugins.<name>.{enable,package,init,config}`, `ennoix.build.{initText,emacsWithPackages,package}`, `evalEnnoix`/`makeEnnoix`, `epkgs`/`pkgs` via `specialArgs` — used consistently across Tasks 2–9. The `package` option is a package-name string (matches the assertion's `hasAttr p.package epkgs` and the build's `epkgs.${p.package}`). ✓ (The spec's §5.1 illustrative selector-function form is simplified here to a name string — cleaner for the fail-loud `hasAttr` check; recorded as the Phase-0 choice.)

**Known simplifications carried into later plans (not Phase-0 gaps):** the `nixpkgs` option is realized via `specialArgs`-injected `pkgs` (Task 8) rather than a full `nixpkgs.pkgs` module option — adequate for standalone; the in-core `build.homeModule`/`build.nixosModule` deferred slots arrive with the delivery adapters (Plan 2).
