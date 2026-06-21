# ennoix Phase-0 Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove `plugins.<name>.enable = true` → a working, configured emacs you can `nix run`, end-to-end, for the 7 Phase-0 plugins.

**Architecture:** A NixOS-module-system eval core (`lib.evalModules`) over per-plugin modules whose curated config lives in option `default`s; a generation step emits one `use-package` form per enabled plugin into an init text; that text is baked as a `default.el` `trivialBuild` package inside `emacsWithPackages` (the spike-verified injection); a `config.assertions` pass fails loudly on unknown packages. Standalone delivery only (`nix run`); HM/NixOS adapters, runtime binaries, profiles, and conflict assertions are out of scope (later plans).

**Tech Stack:** Nix (flakes, the module system, `lib.evalModules`/`lib.runTests`), nixpkgs `emacsPackagesFor`/`emacsWithPackages`/`trivialBuild`, emacs 30.2. No flake-parts. Spec: `docs/superpowers/specs/2026-06-20-ennoix-architecture-design.md` (Plan 1 in §11). Primer: `docs/superpowers/specs/2026-06-07-emacs-primer.md`.

> **Verification note:** every Nix snippet below was prototyped and run — generation output, the fail-loud throw, the build (via `epkgs.withPackages`), real-startup load with `vertico-mode`/`savehist-mode` active, the load gate catching a broken config, and the overlay-fixpoint test/example pattern (instant `ennoix.tests.unit` + recursion-free `ennoix.examples.full`).

> **Tests live in `hydra-jobs`, not `checks`.** Heavy builds don't belong in `nix flake check` (slow, serial). ennoix tests are exposed as derivations in the package set via an `ennoix` overlay (composed into `overlays.default`, like `verification`) and collected by `hydra-jobs/tests.nix` — filterable and parallel via `verify-hydra-jobset` / hydra. `checks` keeps only the repo's existing `formatting` check.

> **Test runner (used throughout):** `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`. The `unit` derivation evaluates `tests/ennoix.nix` (`lib.runTests`) and `touch`es `$out` if it returns `[]`, else `throw`s. It is **instant** — the "build" assertions use `lib.isDerivation` (eval-only); the real emacs build happens only in `ennoix.tests.loads` (Task 9). A RED shows up as a `throw`/eval error from `nix build`; GREEN builds.

> **Option namespace:** options live at the eval's **top level** — `plugins.<name>.…` and `build.…` (NOT under an `ennoix.` prefix). Spec §11 delegates the exact option names to Plan 1; top-level names let Plan 2's home-manager `submoduleWith` expose `config.programs.ennoix.build.package` without double-nesting.

> **Formatter note:** `nix fmt` runs treefmt with deadnix + statix + nixfmt + mdformat (`no-lambda-pattern-names = true`, so unused pattern args like `{ lib, pkgs ? null }` are not flagged). It may rewrite snippets, so a committed file can differ character-for-character from the snippet here. Verify each task with `nix build .#checks.x86_64-linux.formatting` plus `nix fmt`.

______________________________________________________________________

## File Structure

New code lives under `modules/` (eval core + catalog) and `library/` (public API); tests/examples are exposed via an overlay and collected by a new hydra jobset.

- `modules/lib/mk-plugin.nix` — shared per-plugin module builder (the schema; curated values become option `default`s).
- `modules/generation.nix` — collects enabled plugins → `build.initText`.
- `modules/build.nix` — `build.{emacsWithPackages,package}` (default.el injection).
- `modules/assertions.nix` — the `assertions` option + fail-loud package checks.
- `modules/plugins/by-name/<plugin>/default.nix` — one per Phase-0 plugin (7 total).
- `modules/plugins/default.nix` — `readDir`-collects every `by-name/<plugin>`.
- `modules/default.nix` — `{ lib }:` → the `baseModules` list (core ++ plugins).
- `overlays/emacs-packages/default.nix` — the ennoix emacs-scope overlay slot (empty in Phase 0; the `overrideScope` backstop seam).
- `library/ennoix.nix` — `evalEnnoix` / `makeEnnoix` (pkgs resolved inside the eval).
- `library/default.nix` — MODIFY: expose `ennoix`.
- `tests/ennoix.nix` — `lib.runTests` unit tests (generation, defaults, assertions, build).
- `overlays/default.nix` — MODIFY: add an `ennoix` overlay exposing `pkgs.ennoix.{tests.{unit,loads},examples.full}`, composed into `default`.
- `hydra-jobs/tests.nix` — NEW: jobset collecting `pkgs.ennoix.tests` (next to `packages.nix`).
- `flake.nix` — MODIFY: add `packages.<system>.default = legacyPackages.<system>.ennoix.examples.full`.
- `checks/default.nix` — UNCHANGED (formatting only).

______________________________________________________________________

## Task 1: Test suite + the `ennoix` overlay slot (the runner)

> The overlay (in `overlays.default`) wraps `tests/ennoix.nix` as `pkgs.ennoix.tests.unit`. That derivation IS the TDD runner for every later task. It passes `pkgs = final` from the start, so build-tests (Task 5+) need no extra wiring.

**Files:**

- Create: `tests/ennoix.nix`
- Create: `overlays/emacs-packages/default.nix`
- Modify: `overlays/default.nix`

> The emacs-scope overrideScope stub is created here (not later) because the build test in Task 5 imports it, and the overlay's `tests.unit` always passes `pkgs = final`, so that import is live from Task 5 on.

- [ ] **Step 1: Create `tests/ennoix.nix`** (accepts `pkgs` from the start; self-check only) **and the emacs-scope overlay stub.**

`tests/ennoix.nix`:

```nix
# Pure-eval unit tests. `lib.runTests` returns a list of failures ([] = pass).
{ lib, pkgs ? null }:
lib.runTests {
  testHarnessSelfCheck = {
    expr = 1 + 1;
    expected = 2;
  };
}
```

`overlays/emacs-packages/default.nix` (the `overrideScope` backstop seam; empty in Phase 0 — all 7 plugins are in nixpkgs / built-in; later phases extend it):

```nix
_eself: _esuper: { }
```

- [ ] **Step 2: Add the `ennoix` overlay to `overlays/default.nix`.** In the `let` block add:

```nix
ennoix = final: _prev: {
  ennoix.tests.unit =
    let
      failures = import ../tests/ennoix.nix { inherit (final) lib; pkgs = final; };
    in
    if failures == [ ]
    then final.runCommand "ennoix-tests-unit" { } "touch $out"
    else throw "ennoix unit tests failed:\n${final.lib.generators.toPretty { } failures}";
};
```

Add `ennoix` to the `composeManyExtensions` list for `default`, and to the `inherit` export:

```nix
  default = composeManyExtensions [
    fixes
    top-level
    python-packages
    verification
    ennoix
  ];
in
{
  inherit
    default
    ennoix
    fixes
    python-packages
    top-level
    ;
}
```

- [ ] **Step 3: Run the runner to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: builds (self-check passes; `touch $out`).

- [ ] **Step 4: Commit**

```bash
nix fmt
git add tests/ennoix.nix overlays/emacs-packages/default.nix overlays/default.nix
git commit -m "test: ennoix unit suite exposed as pkgs.ennoix.tests.unit overlay"
```

______________________________________________________________________

## Task 2: `mk-plugin.nix` — the per-plugin schema with curated defaults

**Files:**

- Create: `modules/lib/mk-plugin.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Replace `tests/ennoix.nix`'s body** (keep the `{ lib, pkgs ? null }:` header)

```nix
{ lib, pkgs ? null }:
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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
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

> The builder arg is `extraConfig`; the *option* it sets is `config`. Plugin modules (Task 7) must pass `extraConfig =`, not `config =`.

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
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

- [ ] **Step 1: Add to `tests/ennoix.nix`** (inject a fake `epkgs` so the test stays pure)

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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
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

  # Catalog packages are backstopped by the ennoix overlay (Task 6); these
  # hold for the shipped catalog and only fire on a bad user override / extra package.
  config.assertions = mapAttrsToList (name: p: {
    assertion = p.package == null || hasAttr p.package epkgs;
    message = "ennoix: plugin '${name}' references package '${toString p.package}' which is not in the emacs package set.";
  }) (filterAttrs (_: p: p.enable) config.plugins);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/assertions.nix tests/ennoix.nix
git commit -m "feat: assertions — fail loudly on unknown emacs packages"
```

______________________________________________________________________

## Task 5: `build.nix` — default.el injection into `emacsWithPackages`

> The build test asserts `lib.isDerivation` (eval-only) — it does **not** build emacs, so the `unit` runner stays instant. Because the overlay always passes `pkgs = final` (non-null), the `buildTests` branch is **always active** under the runner — `build.nix`, `buildCfg`, and the `overlays/emacs-packages` import (created in Task 1) are live every run. The `pkgs != null` guard only protects a hypothetical direct `import ../tests/ennoix.nix { inherit lib; }` that the runner never uses.

**Files:**

- Create: `modules/build.nix`

- Test: `tests/ennoix.nix`

- [ ] **Step 1: Add the build test** (guarded so pure-eval still works when `pkgs` is null)

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

The `runTests` call becomes `(lib.runTests { …pure tests… }) ++ lib.optionals (pkgs != null) (lib.runTests buildTests)` where:

```nix
  buildTests = {
    testBuildIsDerivation = {
      expr = lib.isDerivation buildCfg.build.package;
      expected = true;
    };
    testBareIsDerivation = {
      expr = lib.isDerivation buildCfg.build.emacsWithPackages;
      expected = true;
    };
  };
```

(`../overlays/emacs-packages/default.nix` was created in Task 1, so this import resolves.)

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — `build.nix … No such file`.

- [ ] **Step 3: Implement `modules/build.nix`** (build from the overlaid scope `epkgs`)

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

> Prototype-verified: `epkgs.withPackages` builds; both `withPackages` and `trivialBuild` live on the `emacsPackagesFor` scope.

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/build.nix tests/ennoix.nix
git commit -m "feat: build — bake generated config as default.el in emacsWithPackages"
```

______________________________________________________________________

## Task 6: plugins collector + `baseModules`

> `modules/default.nix` is a `{ lib }:` function from the start (stable signature) and `modules/plugins/default.nix` `readDir`s `by-name/` (empty now; Task 7 fills it) — so Task 7 adds plugins without touching `modules/default.nix`.

**Files:**

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
  # in runTests (pure tests):
  testBaseModulesIsList = {
    expr = builtins.isList baseModules;
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — `modules/default.nix … No such file`.

- [ ] **Step 3a: Create the empty plugins dir** (so `readDir` has a target)

```bash
mkdir -p modules/plugins/by-name && touch modules/plugins/by-name/.gitkeep
```

- [ ] **Step 3b: Create `modules/plugins/default.nix`**

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

- [ ] **Step 3c: Create `modules/default.nix`** (`{ lib }:` — stable signature)

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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS (`baseModules` is a 3-element list; no plugins yet).

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/plugins modules/default.nix tests/ennoix.nix
git commit -m "feat: plugins collector + baseModules"
```

______________________________________________________________________

## Task 7: the 7 Phase-0 plugin modules

**Files:**

- Create: `modules/plugins/by-name/{vertico,orderless,marginalia,savehist,which-key,modus-themes,magit}/default.nix`
- Test: `tests/ennoix.nix`

> Each module receives `{ mkPlugin }`. **Use `extraConfig =`** (mk-plugin's arg), not `config =`. `savehist`/`which-key`/`modus-themes` are built-in in emacs 30.2 (`builtIn = true`).

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
  # in runTests (pure tests):
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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — `testCatalogHasSeven` (catalog empty → 0 ≠ 7).

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

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
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

- [ ] **Step 1: Add the test** (in `buildTests`, exercised only when `pkgs != null`)

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

> Exercises `library/ennoix.nix` directly. The `library/default.nix` wiring (Step 4) is validated by Task 9's flake `packages.default` (`legacyPackages.<sys>.ennoix.examples.full` → `library.ennoix.makeEnnoix`).

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — `library/ennoix.nix … No such file`.

- [ ] **Step 3: Implement `library/ennoix.nix`**

```nix
{ lib, nixpkgs }:
let
  baseModules = import ../modules/default.nix { inherit lib; };

  # Resolve pkgs INSIDE the eval. Phase 0 callers always pass `pkgs` (from
  # legacyPackages, which already applies the repo overlays); the system-only
  # fallback does NOT apply the repo top-level overlay and is unexercised in
  # Phase 0 (refined in a later plan).
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

- [ ] **Step 4: Expose it from `library/default.nix`.** Inside the `makeExtensible` body (alongside `paths`/`systems`):

```nix
ennoix = import ./ennoix.nix { inherit lib; nixpkgs = inputs.nixpkgs; };
```

(`inputs` is the file-level argument of `library/default.nix`.)

- [ ] **Step 5: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add library/ennoix.nix library/default.nix tests/ennoix.nix
git commit -m "feat: library.ennoix — evalEnnoix/makeEnnoix with pkgs resolved inside the eval"
```

______________________________________________________________________

## Task 9: example emacs + load gate (overlay) + `packages.default` + hydra jobset

**Files:**

- Modify: `overlays/default.nix` (extend the `ennoix` overlay)

- Modify: `flake.nix`

- Create: `hydra-jobs/tests.nix`

- [ ] **Step 1: Extend the `ennoix` overlay** in `overlays/default.nix` to add the example emacs and the load gate:

```nix
ennoix = final: _prev: {
  ennoix = {
    examples.full = inputs.self.library.ennoix.makeEnnoix {
      pkgs = final;
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

    tests.unit =
      let
        failures = import ../tests/ennoix.nix { inherit (final) lib; pkgs = final; };
      in
      if failures == [ ]
      then final.runCommand "ennoix-tests-unit" { } "touch $out"
      else throw "ennoix unit tests failed:\n${final.lib.generators.toPretty { } failures}";

    # HEAVY: builds the example emacs and asserts its generated config loads.
    tests.loads = final.runCommand "ennoix-tests-loads" { } ''
      export HOME=$(mktemp -d)
      # --batch skips package activation AND default.el; mirror real startup.
      # use-package CATCHES errors and prints them, so grep error markers +
      # require a success marker (verified: bare load errors void-function).
      ${final.ennoix.examples.full}/bin/emacs --batch \
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
  };
};
```

- [ ] **Step 2: Add `packages.default`** to `flake.nix` (inside `outputs = inputs: { … }`, reusing the example):

```nix
packages = inputs.self.library.systems.defaultSystems (system: {
  default = inputs.self.legacyPackages.${system}.ennoix.examples.full;
});
```

- [ ] **Step 3: Create `hydra-jobs/tests.nix`** (jobset collecting `pkgs.ennoix.tests`, mirroring `packages.nix`'s arg shape)

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
  inherit (import ./common.nix args)
    lib
    releaseLib
    ;
  inherit (releaseLib) pkgs;
  inherit (lib.attrsets) recurseIntoAttrs;
in
# Single-eval-system jobset: releaseLib.pkgs is built at evalSystem only, and
# (unlike packages.nix) we don't use mapTestOn — so `supportedSystems` is inert
# here in Phase 0 (it aligns with verify-hydra-jobset's single-system --arg).
# Test derivations have no meta.platforms, so collect with recurseIntoAttrs
# (not packagePlatforms); nix-eval-jobs --force-recurse walks the tree.
recurseIntoAttrs {
  ennoix = recurseIntoAttrs pkgs.ennoix.tests;
}
```

- [ ] **Step 4: Run the unit jobset entry (instant) and the heavy load gate**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L && nix build .#legacyPackages.x86_64-linux.ennoix.tests.loads -L`
Expected: both build (unit instant; loads builds the emacs and the config loads, no error markers).

- [ ] **Step 5: Verify the hydra jobset evaluates + builds** (the real runner)

Run: `nix run .#verify-hydra-jobset -- hydra-jobs/tests.nix`
Expected: evaluates `ennoix.{unit,loads}` and builds them; exits 0. (`verify-hydra-jobset` is the repo's `overlays/verification` tool.)

- [ ] **Step 6 (optional RED sanity — proves the gate isn't vacuous):** temporarily add `(this-function-does-not-exist)` to `magit`'s `extraConfig`, run `nix build .#legacyPackages.x86_64-linux.ennoix.tests.loads -L`, confirm it FAILS on the error-marker grep, then revert.

- [ ] **Step 7: Manual `nix run` smoke test**

Run: `nix build .#packages.x86_64-linux.default -o ennoix-emacs && HOME=$(mktemp -d) ./ennoix-emacs/bin/emacs --batch --eval '(package-activate-all)' --eval '(load (locate-library "default") nil t)' --eval '(princ (format "vertico=%s magit=%s\n" (fboundp (quote vertico-mode)) (fboundp (quote magit-status))))'`
Expected: prints `vertico=t magit=t`, no `Error (use-package)` lines. (Interactive, graphical host: `nix run .#` → vertical minibuffer + modus theme; `C-x g` → magit.)

- [ ] **Step 8: Commit**

```bash
nix fmt
git add overlays/default.nix flake.nix hydra-jobs/tests.nix
git commit -m "feat: ennoix example + load gate (overlay) + packages.default + hydra tests jobset"
```

______________________________________________________________________

## Task 10: full flake check + jobset evaluation

- [ ] **Step 1: Run the formatter/flake check (formatting only — fast) and the jobset**

Run: `nix fmt && nix flake check -L 2>&1 | tail -20 && nix run .#verify-hydra-jobset -- hydra-jobs/tests.nix`
Expected: `nix flake check` passes quickly (only `formatting`; no emacs build); the jobset builds `ennoix.unit` + `ennoix.loads`. (Pre-existing aarch64 "omitted incompatible systems" warning is fine.)

- [ ] **Step 2: Commit any formatting changes**

```bash
git add -A
git commit -m "chore: nix fmt" || echo "nothing to format"
```

______________________________________________________________________

## Self-Review

**Spec coverage (Plan 1 scope, spec §11):**

- eval core (standalone) → Task 8. ✓
- generation pipeline (§5.5) → Task 3 (simplified to `:init`/`:config` literal strings; the 7 Phase-0 curated values are literal elisp, so sufficient; richer buckets/serializer are later-plan work). ✓
- default.el injection → Task 5 (spike + prototype verified). ✓
- makeEnnoix standalone flake output → Task 9 (`packages.default` from `examples.full`). ✓
- ennoix overlay slot + fail-loud assertion → Task 6 (emacs-scope slot) + Task 4 (assertion) + Task 8 (throws). ✓
- 7 Phase-0 plugins → Task 7. ✓
- gate: `emacs --batch` load check + manual `nix run` → Task 9 (`ennoix.tests.loads` + smoke test). ✓
- Deferred items (HM/NixOS adapters, runtime binaries, profiles, conflict assertions) → absent. ✓

**Tests-in-hydra-jobs (per decision):** `checks` is untouched (formatting only). ennoix tests are package-set derivations (`pkgs.ennoix.tests.{unit,loads}`) via the `ennoix` overlay, collected by `hydra-jobs/tests.nix`, run with `verify-hydra-jobset`. The fast `unit` derivation doubles as the TDD runner.

**Placeholder scan:** none; every code step shows real, prototyped code. ✓

**Type/name consistency:** top-level `plugins.<name>.{enable,package,init,config}` and `build.{initText,emacsWithPackages,package}`; `evalEnnoix`/`makeEnnoix`/`mkPlugin`; `epkgs`/`pkgs` via `specialArgs`; `package` is a name string (matches `hasAttr p.package epkgs` and `epkgs.${p.package}`); `mkPlugin`'s builder arg is `extraConfig` (sets option `config`), plugin modules pass `extraConfig =`; `modules/default.nix` is `{ lib }:` from Task 6 (no mid-plan signature change); the `ennoix` overlay grows (Task 1 → Task 9) but keeps `tests.unit` identical. ✓

**Deliberate reconciliations (recorded):** options at top level (exact names delegated to Plan 1 by spec §11; enables Plan-2 `submoduleWith` without double-nesting); the **configurable emacs binary** (spec's `cfg.package`, §6) is deferred — Phase 0 hardcodes `pkgs.emacs` (30.2, as §9 fixes); **magit's keybinding** is emitted via freeform `extraConfig`, not the structured `bind` keyword (§5.1), because the structured serializer is deferred (all 7 curated values are literal elisp, so `:init`/`:config` suffice); `makeEnnoixWithModule` (spec §4.3) deferred; `build.emacsWithPackages` is forward-work for the Plan-2 HM adapter (the bare half of `build.package`, eval-asserted in Task 5); `resolvePkgs`'s system-only branch is unexercised in Phase 0 (callers pass `pkgs`) and noted in source.
