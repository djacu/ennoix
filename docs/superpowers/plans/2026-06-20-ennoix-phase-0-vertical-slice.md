# ennoix Phase-0 Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove `plugins.<name>.enable = true` → a working, configured emacs you can `nix run`, end-to-end, for the 7 Phase-0 plugins.

**Architecture:** A NixOS-module-system eval core (`lib.evalModules`, exposed as `library.ennoix.evalEnnoix`) over per-plugin modules whose curated config lives in option `default`s; a generation step emits one `use-package` form per enabled plugin into an init text; that text is baked as a `default.el` `trivialBuild` package inside `emacsWithPackages` (the spike-verified injection); a `config.assertions` pass fails loudly on unknown packages. Standalone delivery only (`nix run`); HM/NixOS adapters, runtime binaries, profiles, and conflict assertions are out of scope (later plans).

**Tech Stack:** Nix (flakes, the module system, `lib.evalModules`/`lib.runTests`), nixpkgs `emacsPackagesFor`/`emacsWithPackages`/`trivialBuild`, emacs 30.2. No flake-parts. Spec: `docs/superpowers/specs/2026-06-20-ennoix-architecture-design.md` (Plan 1 in §11). Primer: `docs/superpowers/specs/2026-06-07-emacs-primer.md`.

> **Walking-skeleton structure (read first).** Tests run *through the real entrypoint* `evalEnnoix` (not hand-assembled module fixtures). That means the entrypoint must exist before the tests can — so **Task 1 stands up the entire pipeline with an *empty* catalog** (zero plugins): `evalEnnoix { modules = [ ]; }` must yield an emacs whose `build.initText` is `""` and that builds + loads. From Task 2 on, each plugin/behavior is added and asserted *through* `evalEnnoix`. The core machinery (Task 1) is therefore built and verified as a unit (one coarse RED→GREEN); the catalog — the actual product — gets fine-grained per-plugin RED/GREEN (Tasks 2–5).

> **Tests live in `hydra-jobs`, not `checks`.** ennoix tests are package-set derivations via an `ennoix` overlay (composed into `overlays.default`, like `verification`), collected by `hydra-jobs/tests.nix` and run via `verify-hydra-jobset`. `checks` keeps only the repo's existing `formatting` check.

> **Test runner (used throughout):** `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`. The `unit` derivation evaluates `modules/eval-tests.nix` (which calls `evalEnnoix`) via `lib.runTests` and `touch`es `$out` if it returns `[]`, else `throw`s. It is **instant** — `.build.initText` is a string and the derivation assertions use `lib.isDerivation` (eval-only); the real emacs build is only in `ennoix.tests.loads`. A RED is a `throw`/eval error from `nix build`; GREEN builds.

> **Option namespace:** options live at the eval's **top level** — `plugins.<name>.…` and `build.…` (NOT under an `ennoix.` prefix). Spec §11 delegates exact option names to Plan 1; top-level names let Plan 2's home-manager `submoduleWith` expose `config.programs.ennoix.build.package` without double-nesting.

> **Formatter note:** `nix fmt` runs treefmt with deadnix + statix + nixfmt + mdformat (`no-lambda-pattern-names = true`). It may rewrite snippets, so committed files can differ from the snippet here. Verify each task with `nix build .#checks.x86_64-linux.formatting` plus `nix fmt`. Per repo policy, commit messages carry **no** `Co-Authored-By` trailer.

> **Verification note:** every Nix snippet was prototyped and run — generation output, fail-loud throw (incl. `tryEval` catching it), the build via `epkgs.withPackages`, real-startup load with modes active, the load gate catching a broken config, the overlay-fixpoint pattern (instant `tests.unit` + recursion-free `examples.full`), and the **empty-catalog** skeleton (an emacs with an empty `default.el` builds and loads).

______________________________________________________________________

## File Structure

- `modules/lib/mk-plugin.nix` — shared per-plugin module builder (curated values become option `default`s).
- `modules/generation.nix` — enabled plugins → `build.initText`.
- `modules/build.nix` — `build.{emacsWithPackages,package}` (default.el injection).
- `modules/assertions.nix` — the `assertions` option + fail-loud package checks.
- `modules/plugins/by-name/<plugin>/default.nix` — one per Phase-0 plugin (7 total).
- `modules/plugins/default.nix` — `readDir`-collects every `by-name/<plugin>`.
- `modules/default.nix` — `{ lib }:` → `baseModules` (core ++ plugins).
- `modules/eval-tests.nix` — `lib.runTests` suite, **through `evalEnnoix`** (Option 2).
- `overlays/emacs-packages/default.nix` — the ennoix emacs-scope overrideScope stub (empty in Phase 0).
- `library/ennoix.nix` — `evalEnnoix` / `makeEnnoix`.
- `library/default.nix` — MODIFY: expose `ennoix`.
- `overlays/default.nix` — MODIFY: add the `ennoix` overlay (`pkgs.ennoix.{tests.{unit,loads},examples.full}`), composed into `default`.
- `hydra-jobs/tests.nix` — NEW: jobset collecting `pkgs.ennoix.tests`.
- `flake.nix` — MODIFY: `packages.<system>.default = legacyPackages.<system>.ennoix.examples.full`.
- `checks/default.nix` — UNCHANGED.

______________________________________________________________________

## Task 1: Walking skeleton — the whole pipeline with an empty catalog

> Build the entire core so `evalEnnoix` works with zero plugins. The single RED→GREEN is: write `modules/eval-tests.nix` (it calls `evalEnnoix`) + wire the `ennoix.tests.unit` runner → it fails (no `evalEnnoix`); create all the core → it passes (`""` init, real derivation). Then prove delivery (empty example builds + loads). This is the bootstrap; per-plugin TDD starts in Task 2.

**Files (create unless noted):** `overlays/emacs-packages/default.nix`, `modules/lib/mk-plugin.nix`, `modules/generation.nix`, `modules/build.nix`, `modules/assertions.nix`, `modules/plugins/by-name/.gitkeep`, `modules/plugins/default.nix`, `modules/default.nix`, `library/ennoix.nix`, `modules/eval-tests.nix`, `hydra-jobs/tests.nix`; MODIFY `library/default.nix`, `overlays/default.nix`, `flake.nix`.

- [ ] **Step 1: Write `modules/eval-tests.nix`** (the skeleton tests, through `evalEnnoix`)

```nix
# Pure-eval tests through the real entrypoint. `lib.runTests` → [] when all pass.
{ lib, pkgs, evalEnnoix }:
let
  cfg = mods: evalEnnoix { inherit pkgs; modules = mods; };
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
}
```

- [ ] **Step 2: Add the `ennoix` overlay to `overlays/default.nix`** (the `tests.unit` runner — injects `evalEnnoix`). In the `let` block:

```nix
ennoix = final: _prev: {
  ennoix.tests.unit =
    let
      failures = import ../modules/eval-tests.nix {
        inherit (final) lib;
        pkgs = final;
        evalEnnoix = inputs.self.library.ennoix.evalEnnoix;
      };
    in
    if failures == [ ]
    then final.runCommand "ennoix-tests-unit" { } "touch $out"
    else throw "ennoix unit tests failed:\n${final.lib.generators.toPretty { } failures}";
};
```

Add `ennoix` to `composeManyExtensions [ … ]` for `default` and to the `inherit` export.

- [ ] **Step 3: Run the runner to confirm it FAILS (RED)**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — the runner can't resolve `evalEnnoix` yet (an `attribute 'ennoix' missing` error from `inputs.self.library`, since `library/default.nix` isn't wired until Step 11). Any failure here is the RED; the coarse GREEN for the skeleton is Step 12.

- [ ] **Step 4: Create the emacs-scope overlay stub** `overlays/emacs-packages/default.nix`

```nix
# ennoix's emacs-scope overlay: catalog packages missing upstream.
# Phase 0 needs none (all 7 are in nixpkgs / built-in); later phases extend it.
_eself: _esuper: { }
```

- [ ] **Step 5: Create `modules/lib/mk-plugin.nix`**

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
      description = "Package name in the emacs scope; `null` for a built-in.";
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

> Builder arg is `extraConfig`; the option it sets is `config`. Plugin modules (Tasks 2–5) pass `extraConfig =`.

- [ ] **Step 6: Create `modules/generation.nix`**

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
    description = "Generated init.el body (use-package forms for enabled plugins).";
  };
  config.build.initText = concatStringsSep "\n\n" (mapAttrsToList form enabled);
}
```

- [ ] **Step 7: Create `modules/build.nix`**

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
  config.build.emacsWithPackages = epkgs.withPackages (_: pluginPkgs);
  config.build.package = epkgs.withPackages (_: pluginPkgs ++ [ defaultEl ]);
}
```

- [ ] **Step 8: Create `modules/assertions.nix`**

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
  config.assertions = mapAttrsToList (name: p: {
    assertion = p.package == null || hasAttr p.package epkgs;
    message = "ennoix: plugin '${name}' references package '${toString p.package}' not in the emacs package set.";
  }) (filterAttrs (_: p: p.enable) config.plugins);
}
```

- [ ] **Step 9: Create the plugins collector** (empty `by-name/` for now)

```bash
mkdir -p modules/plugins/by-name && touch modules/plugins/by-name/.gitkeep
```

`modules/plugins/default.nix`:

```nix
{ lib }:
let
  mkPlugin = import ../lib/mk-plugin.nix { inherit lib; };
  dir = ./by-name;
  names = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
in
map (name: import (dir + "/${name}") { inherit mkPlugin; }) names
```

- [ ] **Step 10: Create `modules/default.nix`** (`baseModules`)

```nix
{ lib }:
[
  ./generation.nix
  ./build.nix
  ./assertions.nix
]
++ import ./plugins { inherit lib; }
```

- [ ] **Step 11: Create `library/ennoix.nix`** and wire `library/default.nix`

`library/ennoix.nix`:

```nix
{ lib, nixpkgs }:
let
  baseModules = import ../modules/default.nix { inherit lib; };

  # Phase 0 callers always pass `pkgs` (from legacyPackages, already overlaid);
  # the system-only fallback does NOT apply the repo overlay and is unexercised.
  resolvePkgs = { pkgs, system }:
    if pkgs != null then pkgs
    else import nixpkgs { inherit system; config = { allowAliases = false; allowUnfree = true; }; };

  evalEnnoix = { pkgs ? null, system ? null, modules ? [ ] }:
    assert lib.assertMsg (pkgs != null || system != null)
      "ennoix: evalEnnoix needs either `pkgs` or `system`.";
    let
      pkgs' = resolvePkgs { inherit pkgs system; };
      epkgs = (pkgs'.emacsPackagesFor pkgs'.emacs).overrideScope (import ../overlays/emacs-packages/default.nix);
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

In `library/default.nix`, inside the `makeExtensible` body (note: not via `callLibs` — `ennoix.nix` takes `{ lib, nixpkgs }`, not `{ lib, library }`):

```nix
ennoix = import ./ennoix.nix { inherit lib; nixpkgs = inputs.nixpkgs; };
```

- [ ] **Step 12: Run the runner to confirm it PASSES (GREEN)**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS — `evalEnnoix { modules = [ ]; }` gives `initText == ""` and a real `build.package`.

- [ ] **Step 13: Add delivery + the example/loads to the overlay.** Extend the `ennoix` overlay in `overlays/default.nix`:

```nix
ennoix = final: _prev: {
  ennoix = {
    examples.full = inputs.self.library.ennoix.makeEnnoix { pkgs = final; modules = [ ]; }; # empty for now; Task 5 fills it
    tests.unit =
      let
        failures = import ../modules/eval-tests.nix {
          inherit (final) lib;
          pkgs = final;
          evalEnnoix = inputs.self.library.ennoix.evalEnnoix;
        };
      in
      if failures == [ ]
      then final.runCommand "ennoix-tests-unit" { } "touch $out"
      else throw "ennoix unit tests failed:\n${final.lib.generators.toPretty { } failures}";
    tests.loads = final.runCommand "ennoix-tests-loads" { } ''
      export HOME=$(mktemp -d)
      ${final.ennoix.examples.full}/bin/emacs --batch \
        --eval '(package-activate-all)' \
        --eval '(load (locate-library "default") nil t)' \
        --eval '(message "ennoix-config-loaded-ok")' > log 2>&1 \
        || { echo "emacs exited non-zero:"; cat log; exit 1; }
      if grep -qiE 'error \(|lisp error|definition is void|wrong type|void-(function|variable)' log; then
        echo "config produced an error at load:"; cat log; exit 1
      fi
      grep -q 'ennoix-config-loaded-ok' log || { echo "missing success marker:"; cat log; exit 1; }
      touch $out
    '';
  };
};
```

`flake.nix` (inside `outputs = inputs: { … }`):

```nix
packages = inputs.self.library.systems.defaultSystems (system: {
  default = inputs.self.legacyPackages.${system}.ennoix.examples.full;
});
```

`hydra-jobs/tests.nix`:

```nix
{
  supportedSystems ? [ "aarch64-linux" "x86_64-linux" ],
  evalSystem ? builtins.currentSystem or "x86_64-linux",
  nixpkgs ? null,
}@args:
let
  inherit (import ./common.nix args) lib releaseLib;
  inherit (releaseLib) pkgs;
  inherit (lib.attrsets) recurseIntoAttrs;
in
# Single-eval-system jobset (releaseLib.pkgs is built at evalSystem; we don't
# use mapTestOn, so supportedSystems is inert here — aligns with
# verify-hydra-jobset's single-system --arg). Test derivations have no
# meta.platforms, so collect with recurseIntoAttrs; nix-eval-jobs --force-recurse walks it.
recurseIntoAttrs {
  ennoix = recurseIntoAttrs pkgs.ennoix.tests;
}
```

- [ ] **Step 14: Verify the empty skeleton end-to-end**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.loads -L && nix build .#packages.x86_64-linux.default -L`
Expected: both build — an emacs with an empty `default.el` that loads with no error (prototype-verified).

- [ ] **Step 15: Commit**

```bash
nix fmt
git add modules overlays/emacs-packages overlays/default.nix library hydra-jobs/tests.nix flake.nix
git commit -m "feat: ennoix walking skeleton — evalEnnoix + empty-catalog pipeline + nix run"
```

______________________________________________________________________

## Task 2: First plugin (vertico) — the per-plugin TDD pattern through `evalEnnoix`

**Files:** Create `modules/plugins/by-name/vertico/default.nix`; Test `modules/eval-tests.nix`.

- [ ] **Step 1: Add a failing test** (to `modules/eval-tests.nix`'s `runTests`)

```nix
  testVerticoActivation = {
    expr = lib.hasInfix "(vertico-mode 1)" (initOf [ { plugins.vertico.enable = true; } ]);
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — `evalEnnoix` errors that option `plugins.vertico` does not exist (no vertico module yet).

- [ ] **Step 3: Create `modules/plugins/by-name/vertico/default.nix`**

```nix
{ mkPlugin }: mkPlugin { name = "vertico"; init = "(vertico-mode 1)"; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS — enabling vertico (through `evalEnnoix`) emits `(vertico-mode 1)`.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/plugins/by-name/vertico modules/eval-tests.nix
git commit -m "feat: vertico plugin (curated vertico-mode activation)"
```

______________________________________________________________________

## Task 3: Completion stack — orderless + marginalia

> `orderless` uses `:config` (sets `completion-styles`, no mode); `marginalia` is a minor mode like vertico.

**Files:** Create `modules/plugins/by-name/{orderless,marginalia}/default.nix`; Test `modules/eval-tests.nix`.

- [ ] **Step 1: Add failing tests**

```nix
  testOrderlessCompletionStyles = {
    expr = lib.hasInfix "completion-styles" (initOf [ { plugins.orderless.enable = true; } ]);
    expected = true;
  };
  testMarginaliaActivation = {
    expr = lib.hasInfix "(marginalia-mode 1)" (initOf [ { plugins.marginalia.enable = true; } ]);
    expected = true;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — options `plugins.orderless`/`plugins.marginalia` do not exist.

- [ ] **Step 3: Create the two modules**

`modules/plugins/by-name/orderless/default.nix`:

```nix
{ mkPlugin }: mkPlugin {
  name = "orderless";
  extraConfig = "(setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))";
}
```

`modules/plugins/by-name/marginalia/default.nix`:

```nix
{ mkPlugin }: mkPlugin { name = "marginalia"; init = "(marginalia-mode 1)"; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/plugins/by-name/orderless modules/plugins/by-name/marginalia modules/eval-tests.nix
git commit -m "feat: orderless + marginalia (completion stack)"
```

______________________________________________________________________

## Task 4: Built-ins — savehist + which-key + modus-themes

> All three are shipped with emacs 30.2 → `builtIn = true` (no derivation, `package = null`, not added to the closure).

**Files:** Create `modules/plugins/by-name/{savehist,which-key,modus-themes}/default.nix`; Test `modules/eval-tests.nix`.

- [ ] **Step 1: Add failing tests**

```nix
  testSavehistActivation = {
    expr = lib.hasInfix "(savehist-mode 1)" (initOf [ { plugins.savehist.enable = true; } ]);
    expected = true;
  };
  testWhichKeyActivation = {
    expr = lib.hasInfix "(which-key-mode 1)" (initOf [ { plugins.which-key.enable = true; } ]);
    expected = true;
  };
  testModusLoadsTheme = {
    expr = lib.hasInfix "modus-operandi" (initOf [ { plugins.modus-themes.enable = true; } ]);
    expected = true;
  };
  testBuiltinHasNoPackage = {
    expr = (cfg [ { plugins.savehist.enable = true; } ]).plugins.savehist.package;
    expected = null;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — those options do not exist.

- [ ] **Step 3: Create the three modules**

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

- [ ] **Step 4: Run to verify it passes**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add modules/plugins/by-name/savehist modules/plugins/by-name/which-key modules/plugins/by-name/modus-themes modules/eval-tests.nix
git commit -m "feat: savehist + which-key + modus-themes (built-ins)"
```

______________________________________________________________________

## Task 5: magit + fail-loud + the full example

> magit binds via freeform `extraConfig` (the structured `bind` serializer is deferred, §self-review). Also adds the fail-loud test (a bad package → `evalEnnoix` throws → `tryEval` catches it) and points `examples.full` at the full 7-plugin config.

**Files:** Create `modules/plugins/by-name/magit/default.nix`; Modify `modules/eval-tests.nix`, `overlays/default.nix`.

- [ ] **Step 1: Add failing tests**

```nix
  testMagitBinding = {
    expr = lib.hasInfix "magit-status" (initOf [ { plugins.magit.enable = true; } ]);
    expected = true;
  };
  testFailLoud = {
    # evalEnnoix throws when an enabled plugin's package isn't in the scope.
    expr = (builtins.tryEval
      (cfg [ { plugins.magit.enable = true; plugins.magit.package = lib.mkForce "no-such-pkg"; } ]).build.package
    ).success;
    expected = false;
  };
  testCatalogHasSeven = {
    expr = builtins.length (import ../modules/plugins { inherit lib; });
    expected = 7;
  };
```

- [ ] **Step 2: Run to verify it fails**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L 2>&1 | tail -20`
Expected: FAIL — `plugins.magit` does not exist; `testCatalogHasSeven` sees 6.

- [ ] **Step 3: Create `modules/plugins/by-name/magit/default.nix`**

```nix
{ mkPlugin }: mkPlugin { name = "magit"; extraConfig = "(keymap-global-set \"C-x g\" #'magit-status)"; }
```

- [ ] **Step 4: Point `examples.full` at the full config.** In `overlays/default.nix`, change the `examples.full` `modules` to enable all 7:

```nix
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
```

- [ ] **Step 5: Run unit + the full load gate**

Run: `nix build .#legacyPackages.x86_64-linux.ennoix.tests.unit -L && nix build .#legacyPackages.x86_64-linux.ennoix.tests.loads -L`
Expected: both PASS — catalog is 7, magit/fail-loud green, and the full 7-plugin emacs loads (modes active, no error markers).

- [ ] **Step 6: RED sanity (optional — proves the load gate isn't vacuous):** temporarily add `(this-function-does-not-exist)` to magit's `extraConfig`, run `nix build .#legacyPackages.x86_64-linux.ennoix.tests.loads -L`, confirm it FAILS on the error grep, then revert.

- [ ] **Step 7: Commit**

```bash
nix fmt
git add modules/plugins/by-name/magit modules/eval-tests.nix overlays/default.nix
git commit -m "feat: magit + fail-loud test + full 7-plugin example"
```

______________________________________________________________________

## Task 6: full flake check + jobset + smoke test

- [ ] **Step 1: Fast flake check (formatting only) + the jobset**

Run: `nix fmt && nix flake check -L 2>&1 | tail -20 && nix run .#verify-hydra-jobset -- hydra-jobs/tests.nix`
Expected: `nix flake check` passes quickly (only `formatting`; no emacs build); the jobset evaluates and builds `ennoix.{unit,loads}`. (Pre-existing aarch64 "omitted incompatible systems" warning is fine.)

- [ ] **Step 2: Manual `nix run` smoke test**

Run: `nix build .#packages.x86_64-linux.default -o ennoix-emacs && HOME=$(mktemp -d) ./ennoix-emacs/bin/emacs --batch --eval '(package-activate-all)' --eval '(load (locate-library "default") nil t)' --eval '(princ (format "vertico=%s magit=%s\n" (fboundp (quote vertico-mode)) (fboundp (quote magit-status))))'`
Expected: prints `vertico=t magit=t`, no `Error (use-package)` lines. (Interactive, graphical host: `nix run .#` → vertical minibuffer + modus theme; `C-x g` → magit.)

- [ ] **Step 3: Commit any formatting changes**

```bash
git add -A
git commit -m "chore: nix fmt" || echo "nothing to format"
```

______________________________________________________________________

## Self-Review

**Spec coverage (Plan 1 scope, §11):** eval core → Task 1 (`evalEnnoix`); generation (§5.5, `:init`/`:config` literals) → Task 1 + exercised Tasks 2–5; default.el injection → Task 1 (build.nix); makeEnnoix standalone output → Task 1 (`packages.default`); ennoix overlay slot + fail-loud → Task 1 (slot/assertions) + Task 5 (fail-loud test); 7 plugins → Tasks 2–5; gate (`emacs --batch` + `nix run`) → Task 5/6. Deferred items (HM/NixOS, runtime binaries, profiles, conflict assertions) absent. ✓

**Option-2 structure:** tests run through `evalEnnoix` (the real entrypoint), in `modules/eval-tests.nix`. Task 1 is the walking skeleton (whole pipeline, empty catalog, one coarse RED→GREEN); Tasks 2–5 add the catalog with fine-grained per-plugin RED/GREEN through the runner. Every plugin test exercises mk-plugin + generation + build + baseModules + evalEnnoix together — so the machinery is covered by the catalog tests, not in isolation.

**Placeholder scan:** none; all code prototyped. ✓ **Naming/types:** top-level `plugins.*`/`build.*`; `evalEnnoix`/`makeEnnoix`/`mkPlugin`; `epkgs`/`pkgs` via `specialArgs`; `package` a name string; `extraConfig` builder arg → `config` option; `modules/default.nix` stable `{ lib }:`. ✓

**Deliberate reconciliations (recorded):** top-level option names (delegated by §11; enables Plan-2 `submoduleWith`); configurable emacs binary (spec `cfg.package`, §6) deferred — Phase 0 hardcodes `pkgs.emacs` (30.2); magit's keybinding via freeform `extraConfig` (structured `bind` serializer deferred; all 7 curated values are literal elisp); `makeEnnoixWithModule` (§4.3) deferred; `build.emacsWithPackages` is forward-work for the Plan-2 HM adapter; `hydra-jobs/tests.nix` is single-eval-system (`supportedSystems` inert in Phase 0); `resolvePkgs` system-only branch unexercised in Phase 0 (noted in source).
