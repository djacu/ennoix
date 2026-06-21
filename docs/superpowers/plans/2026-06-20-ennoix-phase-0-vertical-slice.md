# ennoix Phase-0 Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove `plugins.<name>.enable = true` → a working, configured emacs you can `nix run`, end-to-end, for the 7 Phase-0 plugins.

**Architecture:** A NixOS-module-system eval core (`lib.evalModules`) over per-plugin modules whose curated config lives in option `default`s; a generation step emits one `use-package` form per enabled plugin into an init text; that text is baked as a `default.el` `trivialBuild` package inside `emacsWithPackages` (the spike-verified injection); a `config.assertions` pass fails loudly on unknown packages. Standalone delivery only (`nix run`); HM/NixOS adapters, runtime binaries, profiles, and conflict assertions are out of scope (later plans).

**Tech Stack:** Nix (flakes, the module system, `lib.evalModules`/`lib.runTests`), nixpkgs `emacsPackagesFor`/`emacsWithPackages`/`trivialBuild`, emacs 30.2. No flake-parts. Spec: `docs/superpowers/specs/2026-06-20-ennoix-architecture-design.md` (Plan 1 in §11). Primer: `docs/superpowers/specs/2026-06-07-emacs-primer.md`.

> **Verification note:** every Nix snippet below was prototyped and run — generation output, the fail-loud throw, the build (via `epkgs.withPackages`), and real-startup load with `vertico-mode`/`savehist-mode` active. The load gate was confirmed to *catch* a broken config (a bare `--batch` load errors `void-function vertico-mode`; the gate runs `(package-activate-all)` first and greps for error markers).

> **Option namespace:** options live at the eval's **top level** — `plugins.<name>.…` and `build.…` (NOT under an `ennoix.` prefix). This is deliberate: it matches the spec and lets Plan 2's home-manager `submoduleWith` expose `config.programs.ennoix.build.package` without double-nesting.

> **Formatter note:** `nix fmt` runs treefmt with deadnix + statix + nixfmt + mdformat. It may rewrite snippets (deadnix strips unused bindings; statix applies idioms), so a committed file can differ character-for-character from the snippet here. Verify each task with `nix build .#checks.x86_64-linux.formatting` in addition to `nix fmt`.

______________________________________________________________________

## File Structure

New code lives under `modules/` (the eval core + catalog) and `library/` (the public API), wired into the existing hand-rolled `flake.nix`.

- `modules/lib/mk-plugin.nix` — shared per-plugin module builder (the schema; curated values become option `default`s).
- `modules/generation.nix` — collects enabled plugins → `build.initText`.
- `modules/build.nix` — `build.{emacsWithPackages,package}` (default.el injection).
- `modules/assertions.nix` — the `assertions` option + the fail-loud package checks.
- `modules/plugins/by-name/<plugin>/default.nix` — one per Phase-0 plugin (7 total).
- `modules/plugins/default.nix` — `readDir`-collects every `by-name/<plugin>`.
- `modules/default.nix` — `{ lib }:` → the `baseModules` list (core modules ++ plugins).
- `overlays/emacs-packages/default.nix` — the ennoix emacs-scope overlay slot (empty in Phase 0; the `overrideScope` backstop seam).
- `library/ennoix.nix` — `evalEnnoix` / `makeEnnoix` (pkgs resolved inside the eval).
- `library/default.nix` — MODIFY: expose `ennoix`.
- `tests/ennoix.nix` — `lib.runTests` unit tests (generation, defaults, assertions, build).
- `checks/default.nix` — MODIFY: bind `pkgs`; add `ennoix-unit` (eval tests) and `ennoix-loads` (build-level `emacs --batch` gate).
- `flake.nix` — MODIFY: add `packages.<system>.default = library.ennoix.makeEnnoix { … }`.

______________________________________________________________________

## Task 1: Bind `pkgs` in checks + the `lib.runTests` harness

> **Critical prerequisite (verified against the real file):** `checks/default.nix` is `mapAttrs (flip (const (system: { … }))) inputs.self.legacyPackages`. `flip`+`const` **discard the package-set value** and bind only the attr *name* as `system` — so `pkgs` is **not** in scope. Every later check uses `pkgs`, so we bind it first.

**Files:**

- Create: `tests/ennoix.nix`

- Modify: `checks/default.nix`

- [ ] **Step 1: Create `tests/ennoix.nix`** (a `lib.runTests` suite; returns `[]` when all pass)

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

- [ ] **Step 2: Modify `checks/default.nix` to bind `pkgs` and add `ennoix-unit`**

Change the per-system body so `pkgs` is bound, then add the check. The body becomes:

```nix
mapAttrs (flip (
  const (
    system:
    let
      pkgs = inputs.self.legacyPackages.${system};
    in
    {
      formatting = inputs.self.formatterModule.${system}.config.build.check inputs.self;

      ennoix-unit =
        let
          failures = import ../tests/ennoix.nix { inherit lib; };
        in
        if failures == [ ]
        then pkgs.runCommand "ennoix-unit-pass" { } "touch $out"
        else throw "ennoix unit tests failed:\n${lib.generators.toPretty { } failures}";
    }
  )
)) inputs.self.legacyPackages
```

(`mapAttrs`, `flip`, `const`, `lib` are already in scope in this file; `pkgs` is now bound from `legacyPackages`.)

- [ ] **Step 3: Run the check to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: builds successfully (self-check passes; `pkgs.runCommand` resolves).

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

- [ ] **Step 1: Replace `tests/ennoix.nix` with the mk-plugin tests** (keep the `{ lib }:` header)

```nix
{ lib }:
let
  inherit (lib) evalModules;
  mkPlugin = import ../modules/lib/mk-plugin.nix { inherit lib; };
  evalOne = mod: (evalModules { modules = [ mod ]; }).config;

  verticoCfg = evalOne (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; });
  savehistCfg = evalOne (mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; });
in
lib.runTests {
  testCuratedInitDefault = {
    expr = verticoCfg.plugins.vertico.init;
    expected = "(vertico-mode 1)";
  };
  testPackageDefaultsToName = {
    expr = verticoCfg.plugins.vertico.package;
    expected = "vertico";
  };
  testBuiltinHasNoPackage = {
    expr = savehistCfg.plugins.savehist.package;
    expected = null;
  };
  testDisabledByDefault = {
    expr = verticoCfg.plugins.vertico.enable;
    expected = false;
  };
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `error: … mk-plugin.nix … No such file`.

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
  options.plugins.${name} = {
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

> Note the deliberate naming: the builder arg is `extraConfig`; the *option* it sets is `config`. Plugin modules (Task 7) must pass `extraConfig =`, not `config =`.

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

## Task 3: `generation.nix` — emit use-package forms into `build.initText`

**Files:**

- Create: `modules/generation.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Add to `tests/ennoix.nix`** (a `genText` helper in the `let`, two cases in `runTests`)

```nix
  # in the let-block:
  genText = userMods:
    (evalModules {
      modules = [
        (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; })
        (mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; })
        (import ../modules/generation.nix)
      ] ++ userMods;
    }).config.build.initText;

  bothText = genText [ { plugins.vertico.enable = true; plugins.savehist.enable = true; } ];
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
    expr = lib.hasInfix "use-package" (genText [ ]);
    expected = false;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `generation.nix … No such file`.

- [ ] **Step 3: Implement `modules/generation.nix`**

```nix
{ config, lib, ... }:
let
  inherit (lib) types mkOption filterAttrs mapAttrsToList concatStringsSep optional;

  enabled = filterAttrs (_: p: p.enable) config.plugins;

  form = name: p:
    concatStringsSep "\n" (
      [ "(use-package ${name}" ]
      ++ optional (p.init != "") "  :init ${p.init}"
      ++ optional (p.config != "") "  :config ${p.config}"
      ++ [ "  )" ]
    );
in
{
  options.build.initText = mkOption {
    type = types.lines;
    default = "";
    description = "The generated init.el body (use-package forms for enabled plugins).";
  };

  # deterministic order: mapAttrsToList iterates attr names alphabetically
  config.build.initText = concatStringsSep "\n\n" (mapAttrsToList form enabled);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/generation.nix tests/ennoix.nix
git commit -m "feat: generation — emit use-package forms into build.initText"
```

______________________________________________________________________

## Task 4: `assertions.nix` — fail loudly on unknown packages

**Files:**

- Create: `modules/assertions.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Add to `tests/ennoix.nix`** (inject a fake `epkgs` so the test stays pure — no build)

```nix
  # in the let-block:
  fakeEpkgs = { vertico = "drv"; }; # only vertico "exists"
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
    expr = failing (assertList [ { plugins.vertico.enable = true; } ]);
    expected = [ ];
  };
  testAssertFailsForMissing = {
    expr = builtins.length (failing (assertList [ { plugins.magit.enable = true; } ]));
    expected = 1; # magit not in fakeEpkgs
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `assertions.nix … No such file`.

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

  # Catalog packages are backstopped by the ennoix overlay (Task 6), so these
  # hold for the shipped catalog and only fire on a bad user override / extra package.
  config.assertions = mapAttrsToList (name: p: {
    assertion = p.package == null || hasAttr p.package epkgs;
    message = "ennoix: plugin '${name}' references package '${toString p.package}' which is not in the emacs package set.";
  }) (filterAttrs (_: p: p.enable) config.plugins);
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

> This is the first task whose test builds, so it needs `pkgs` to reach the suite. Do the wiring (Steps 1–2) **before** the RED run (Step 4), or the build test is silently skipped (false green).

**Files:**

- Create: `modules/build.nix`

- Modify: `tests/ennoix.nix` (header), `checks/default.nix` (pass `pkgs`)

- [ ] **Step 1: Make `tests/ennoix.nix` accept `pkgs`.** Change its header to:

```nix
{ lib, pkgs ? null }:
```

- [ ] **Step 2: Pass `pkgs` into the suite.** In `checks/default.nix`, change the `ennoix-unit` import to:

```nix
failures = import ../tests/ennoix.nix { inherit lib pkgs; };
```

- [ ] **Step 3: Add the build test** (guarded so pure-eval still works when `pkgs` is null)

```nix
  # in the let-block:
  buildCfg = (evalModules {
    modules = [
      (mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; })
      (mkPlugin { name = "savehist"; builtIn = true; init = "(savehist-mode 1)"; })
      (import ../modules/generation.nix)
      (import ../modules/build.nix)
      {
        _module.args.pkgs = pkgs;
        _module.args.epkgs = (pkgs.emacsPackagesFor pkgs.emacs).overrideScope (import ../overlays/emacs-packages/default.nix);
      }
      { plugins.vertico.enable = true; plugins.savehist.enable = true; }
    ];
  }).config;
```

The `runTests` call becomes `tests // lib.optionalAttrs (pkgs != null) buildTests` where:

```nix
  # buildTests:
  {
    testBuildIsDerivation = {
      expr = lib.isDerivation buildCfg.build.package;
      expected = true;
    };
  }
```

(`overlays/emacs-packages/default.nix` is created in Task 6 — note this import for execution ordering; if running tasks strictly in order, create that file first or stub it here as `(_: _: { })`.)

- [ ] **Step 4: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `build.nix … No such file`. (If it unexpectedly **passes**, `pkgs` isn't reaching the suite — recheck Steps 1–2 and the Task-1 `pkgs` binding.)

- [ ] **Step 5: Implement `modules/build.nix`** (build from the overlaid scope `epkgs`, so the ennoix-overlay seam is real)

```nix
{ config, lib, epkgs, ... }:
let
  inherit (lib) types mkOption filterAttrs mapAttrsToList;

  enabledWithPkg = filterAttrs (_: p: p.enable && p.package != null) config.plugins;
  pluginPkgs = mapAttrsToList (_: p: epkgs.${p.package}) enabledWithPkg;

  defaultEl = epkgs.trivialBuild {
    pname = "default";
    version = "0";
    src = epkgs.callPackage (
      { runCommand, writeText }:
      runCommand "ennoix-default-src" { } ''
        mkdir -p "$out"
        cp ${writeText "default.el" config.build.initText} "$out/default.el"
      ''
    ) { };
    packageRequires = pluginPkgs;
  };
in
{
  options.build.emacsWithPackages = mkOption { type = types.package; };
  options.build.package = mkOption { type = types.package; };

  # bare: packages on load-path, no config baked (the HM adapter uses this later)
  config.build.emacsWithPackages = epkgs.withPackages (_: pluginPkgs);
  # baked: standalone/NixOS — config rides in default.el
  config.build.package = epkgs.withPackages (_: pluginPkgs ++ [ defaultEl ]);
}
```

> `epkgs.callPackage` is used for `runCommand`/`writeText` so the module needs no separate `pkgs` arg; both `withPackages` and `trivialBuild` live on the `emacsPackagesFor` scope. (Prototype-verified: `epkgs.withPackages` builds.)

- [ ] **Step 6: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
nix fmt
git add modules/build.nix tests/ennoix.nix checks/default.nix
git commit -m "feat: build — bake generated config as default.el in emacsWithPackages"
```

______________________________________________________________________

## Task 6: ennoix overlay slot + plugins collector + `baseModules`

> `modules/default.nix` is a `{ lib }:` function **from the start** (stable signature — no mid-plan change), and `modules/plugins/default.nix` `readDir`s `by-name/` (empty now; Task 7 fills it). So Task 7 adds plugins without touching `modules/default.nix`.

**Files:**

- Create: `overlays/emacs-packages/default.nix`

- Create: `modules/plugins/by-name/.gitkeep`

- Create: `modules/plugins/default.nix`

- Create: `modules/default.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Add the baseModules test**

```nix
  # in the let-block:
  baseModules = import ../modules/default.nix { inherit lib; };
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
Expected: FAIL — `modules/default.nix … No such file`.

- [ ] **Step 3a: Create `overlays/emacs-packages/default.nix`** (backstop seam; empty in Phase 0)

```nix
# ennoix's emacs-scope overlay: provides catalog packages missing upstream.
# Phase 0 needs none (all 7 are in nixpkgs / built-in); later phases extend it.
_eself: _esuper: { }
```

- [ ] **Step 3b: Create the empty plugins dir** so `readDir` has a target

```bash
mkdir -p modules/plugins/by-name && touch modules/plugins/by-name/.gitkeep
```

- [ ] **Step 3c: Create `modules/plugins/default.nix`** (collects every `by-name/<plugin>`)

```nix
{ lib }:
let
  mkPlugin = import ../lib/mk-plugin.nix { inherit lib; };
  dir = ./by-name;
  names = builtins.attrNames (
    lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir)
  );
in
map (name: import (dir + "/${name}") { inherit mkPlugin; }) names
```

(`.gitkeep` is a regular file, not a directory, so `filterAttrs (… == "directory")` skips it → `names = []` → `[]`.)

- [ ] **Step 3d: Create `modules/default.nix`** (`{ lib }:` — stable signature)

```nix
{ lib }:
[
  ./generation.nix
  ./build.nix
  ./assertions.nix
]
++ import ./plugins { inherit lib; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS (`baseModules` is a 3-element list; no plugins yet).

- [ ] **Step 5: Commit**

```bash
nix fmt
git add overlays/emacs-packages/default.nix modules/plugins modules/default.nix tests/ennoix.nix
git commit -m "feat: ennoix overlay slot + plugins collector + baseModules"
```

______________________________________________________________________

## Task 7: the 7 Phase-0 plugin modules

**Files:**

- Create: `modules/plugins/by-name/{vertico,orderless,marginalia,savehist,which-key,modus-themes,magit}/default.nix`
- Test: `tests/ennoix.nix`

> Curated values are the canonical activations from each package's docs. `orderless` sets `completion-styles` (no mode). `savehist`/`which-key`/`modus-themes` are built-in in emacs 30.2 (`builtIn = true`, no derivation). Each module receives `{ mkPlugin }` (passed by `modules/plugins/default.nix`). **Use `extraConfig =`, not `config =`** (mk-plugin's arg name).

- [ ] **Step 1: Add the catalog test**

```nix
  # in the let-block:
  catalog = import ../modules/plugins { inherit lib; };
  allText = (evalModules {
    modules = catalog ++ [ (import ../modules/generation.nix) ] ++ [{
      plugins = lib.genAttrs
        [ "vertico" "orderless" "marginalia" "savehist" "which-key" "modus-themes" "magit" ]
        (_: { enable = true; });
    }];
  }).config.build.initText;
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
Expected: FAIL — `testCatalogHasSeven` (catalog is empty → length 0 ≠ 7).

- [ ] **Step 3: Create the 7 plugin modules**

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
  extraConfig = "(setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))";
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
{ mkPlugin }: mkPlugin { name = "modus-themes"; builtIn = true; extraConfig = "(load-theme 'modus-operandi :no-confirm)"; }
```

`modules/plugins/by-name/magit/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "magit"; extraConfig = "(keymap-global-set \"C-x g\" #'magit-status)"; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L`
Expected: PASS (catalog length 7; orderless/magit text present).

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/plugins/by-name tests/ennoix.nix
git commit -m "feat: Phase-0 catalog — vertico/orderless/marginalia/savehist/which-key/modus-themes/magit"
```

______________________________________________________________________

## Task 8: `library/ennoix.nix` — `evalEnnoix` / `makeEnnoix`

**Files:**

- Create: `library/ennoix.nix`

- Modify: `library/default.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Add the test** (under the `pkgs != null` build-tests block)

```nix
  # in buildTests:
  testMakeEnnoixIsDerivation = {
    expr =
      let
        ennoix = import ../library/ennoix.nix { inherit lib; nixpkgs = pkgs.path; };
      in
      lib.isDerivation (ennoix.makeEnnoix {
        inherit pkgs;
        modules = [ { plugins.vertico.enable = true; } ];
      });
    expected = true;
  };
```

> This test exercises `library/ennoix.nix` directly. The `library/default.nix` wiring (Step 4) is validated by Task 9's flake output, which consumes `inputs.self.library.ennoix.makeEnnoix`.

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#checks.x86_64-linux.ennoix-unit -L 2>&1 | tail -20`
Expected: FAIL — `library/ennoix.nix … No such file`.

- [ ] **Step 3: Implement `library/ennoix.nix`**

```nix
{ lib, nixpkgs }:
let
  baseModules = import ../modules/default.nix { inherit lib; };

  # Resolve pkgs INSIDE the eval (one source of truth). Phase 0 callers always
  # pass `pkgs` (from legacyPackages, which already applies the repo overlays);
  # the `system`-only fallback is a convenience that does NOT apply the repo's
  # top-level overlay and is unexercised in Phase 0 (refined in a later plan).
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

  makeEnnoix = args: (evalEnnoix args).build.package;
in
{ inherit evalEnnoix makeEnnoix; }
```

- [ ] **Step 4: Expose it from `library/default.nix`.** Inside the `makeExtensible` body (alongside `paths`/`systems`), add:

```nix
ennoix = import ./ennoix.nix { inherit lib; nixpkgs = inputs.nixpkgs; };
```

(`inputs` is the file-level argument of `library/default.nix`; `inputs.nixpkgs` is the flake input.)

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

- [ ] **Step 1: Add the `packages.default` output to `flake.nix`** (inside `outputs = inputs: { … }`, using the repo's `defaultSystems` helper)

```nix
packages = inputs.self.library.systems.defaultSystems (system: {
  default = inputs.self.library.ennoix.makeEnnoix {
    pkgs = inputs.self.legacyPackages.${system};
    modules = [
      {
        plugins.vertico.enable = true;
        plugins.orderless.enable = true;
        plugins.marginalia.enable = true;
        plugins.savehist.enable = true;
        plugins.which-key.enable = true;
        plugins.modus-themes.enable = true;
        plugins.magit.enable = true;
      }
    ];
  };
});
```

- [ ] **Step 2: Add the `ennoix-loads` gate** to `checks/default.nix` (inside the same per-system attrset as `ennoix-unit`; `pkgs` is bound from Task 1)

```nix
ennoix-loads =
  let
    emacs = inputs.self.packages.${system}.default;
  in
  pkgs.runCommand "ennoix-loads" { } ''
    export HOME=$(mktemp -d)
    # --batch skips package activation AND default.el. Mirror real startup:
    # (package-activate-all) loads the nix packages' autoloads, then load the
    # generated default.el. use-package CATCHES errors and prints them rather
    # than exiting non-zero, so we grep for error markers + require a success
    # marker (verified: a bare load without activate-all errors void-function).
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

- [ ] **Step 3: Run the gate to verify it passes**

Run: `nix build .#checks.x86_64-linux.ennoix-loads -L`
Expected: builds (config loads, no error markers, success marker present).

- [ ] **Step 4 (optional RED sanity check — proves the gate isn't vacuous):** temporarily change `magit`'s `extraConfig` to include `(this-function-does-not-exist)`, run `nix build .#checks.x86_64-linux.ennoix-loads -L`, confirm it FAILS on the error-marker grep, then revert.

- [ ] **Step 5: Manual `nix run` smoke test**

Run: `nix build .#packages.x86_64-linux.default -o ennoix-emacs && HOME=$(mktemp -d) ./ennoix-emacs/bin/emacs --batch --eval '(package-activate-all)' --eval '(load (locate-library "default") nil t)' --eval '(princ (format "vertico=%s magit=%s\n" (fboundp (quote vertico-mode)) (fboundp (quote magit-status))))'`
Expected: prints `vertico=t magit=t`, no `Error (use-package)` lines. (Interactive check on a graphical host: `nix run .#` → vertical minibuffer + modus theme; `C-x g` → magit.)

- [ ] **Step 6: Commit**

```bash
nix fmt
git add flake.nix checks/default.nix
git commit -m "feat: standalone packages.default (nix run) + ennoix-loads build gate"
```

______________________________________________________________________

## Task 10: full check + flake evaluation

- [ ] **Step 1: Run the formatter check and the full flake check**

Run: `nix fmt && nix flake check -L 2>&1 | tail -30`
Expected: `formatting`, `ennoix-unit`, and `ennoix-loads` all pass; flake evaluates. (The pre-existing aarch64 "omitted incompatible systems" warning is fine.)

- [ ] **Step 2: Commit any formatting changes**

```bash
git add -A
git commit -m "chore: nix fmt" || echo "nothing to format"
```

______________________________________________________________________

## Self-Review

**Spec coverage (Plan 1 scope, spec §11):**

- eval core (standalone) → Task 8 (`evalEnnoix`, pkgs-inside via `resolvePkgs`/`specialArgs`). ✓
- generation pipeline (§5.5) → Task 3. ✓ (Buckets beyond per-plugin + the structured-keyword serializer are simplified to `:init`/`:config` literal strings for Phase 0 — the 7 Phase-0 plugins' curated values are literal elisp, so this is sufficient; richer keywords/buckets are a later-plan extension.)
- default.el injection → Task 5 (spike + prototype verified). ✓
- makeEnnoix standalone flake output → Task 9. ✓
- ennoix overlay slot + fail-loud assertion → Task 6 (slot) + Task 4 (assertion) + Task 8 (throws on failed assertions). ✓
- 7 Phase-0 plugins → Task 7. ✓
- gate: `emacs --batch` load check + manual `nix run` → Task 9. ✓
- Deferred items (HM/NixOS adapters, runtime binaries, profiles, conflict assertions) → correctly absent. ✓

**Placeholder scan:** no TBD/TODO; every code step shows real, prototyped code. ✓

**Type/name consistency:** options at top level — `plugins.<name>.{enable,package,init,config}`, `build.{initText,emacsWithPackages,package}` — and `evalEnnoix`/`makeEnnoix`/`mkPlugin`, `epkgs`/`pkgs` via `specialArgs`, used consistently across Tasks 2–9. `mkPlugin`'s builder arg is `extraConfig` (sets the option `config`); all plugin modules pass `extraConfig =` (Task 7). `package` is a name string (matches the assertion's `hasAttr p.package epkgs` and the build's `epkgs.${p.package}`). `modules/default.nix` is `{ lib }:` from Task 6 — no mid-plan signature change. ✓

**Spec reconciliation (deliberate, recorded):**

- Options live at top level (`plugins.*`/`build.*`), matching the spec's `config.build.package` and enabling Plan 2's `submoduleWith` to expose `config.programs.ennoix.build.package` without double-nesting.
- `makeEnnoixWithModule` (spec §4.3 frozen API) is **deferred** to a later plan; Phase 0 ships `evalEnnoix` + `makeEnnoix`.
- `build.emacsWithPackages` is implemented now (spec §4.2, trivial) though its only consumer is the Plan-2 HM adapter — kept as forward-work since it is the bare half of `build.package`.
- `resolvePkgs`'s `system`-only fallback is unexercised in Phase 0 (callers pass `pkgs`) and does not apply the repo's top-level overlay — noted in `library/ennoix.nix`; reconciled when a `system`-only caller appears.
