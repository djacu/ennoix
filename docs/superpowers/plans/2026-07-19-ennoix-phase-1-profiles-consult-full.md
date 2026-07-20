# Phase 1 Plan 2 — Profiles Mechanism + consult-full Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `profiles` mechanism (a namespace + a collector that registers each profile's `enable` toggle and imports its gated module) and ship the first profile, `consult-full`, which merges consult's complete curated binding surface onto the base tier.

**Architecture:** `modules/profiles.nix` declares `options.profiles = attrsOf (submodule { options.enable = …; })`. `modules/eval.nix` gains a collector mirroring the catalog collector: it reads `modules/profiles/<name>/` directory names, registers each toggle (so `profiles.<name>.enable` materializes at `false` even when off — keeping `profile.nix` a pure `mkIf` body), and imports each `profile.nix`. `modules/profiles/consult-full/profile.nix` is `lib.mkIf config.profiles.consult-full.enable { … }` that sets consult's full-tier `bind`/`bindLocal`/`config`/`runtimePackages` at `mkCatalogDefault` — equal priority to the base module, so they MERGE (base ∪ full).

**Tech Stack:** Nix (NixOS module system), emacs use-package, treefmt.

**Depends on:** Plan 1 (the base `consult` catalog module must exist for the profile to merge onto). Plan 1 must be merged before starting.

**Source of truth:** `docs/superpowers/specs/2026-07-19-ennoix-phase-1-design.md` §2, §3, §4, and Appendix A (full rows). Every file body and `expected` test string below was emitted/verified by the real `pkgs.ennoixEval` — do not paraphrase.

## Global Constraints

- Curated values MUST be wrapped in `mkCatalogDefault` (`specialArg`, `= lib.mkOverride 1400`). The `consult-full` profile deliberately uses it so its defs MERGE with the base module's (equal priority) rather than replace them.
- The profile registers its `enable` via the collector (from the directory name), NOT by self-registering; `profile.nix` stays a pure `lib.mkIf config.profiles.consult-full.enable { … }` body.
- **`git add` new/changed files before every `nix build`** (flakes omit untracked files). Commands below do this. In particular the collector's `builtins.readDir ./profiles` only sees git-tracked entries.
- The profiles collector appends `profileModules` AFTER `catalogModules`, so where the base module and the profile both define `config` (type `lines`), concatenation order is deterministically base-then-profile. Do not reorder.
- `nix fmt` before every commit; formatting check is `nix build .#checks.x86_64-linux.formatting`.
- Commits MUST NOT contain a `Co-Authored-By: Claude` trailer.
- Eval-test runner: `nix build .#ennoix-tests-eval`.

______________________________________________________________________

### Task 1: profiles namespace + eval.nix collector (inert scaffold)

**Files:**

- Create: `modules/profiles.nix`
- Create: `modules/profiles/.gitkeep` (so the collector's `readDir ./profiles` resolves with zero profiles present)
- Modify: `modules/eval.nix` (add the profiles collector to the `let` block and `baseModules`)

**Interfaces:**

- Produces: `options.profiles` (an `attrsOf` of `{ enable }` submodules) reachable through `ennoixEval`; the collector plumbing (`profileNames`, `profileModules`, `profileToggles`) that Task 2's profile relies on.

This is a scaffold task: with no profile directory yet, the collector is inert. It therefore adds **no eval test** — any `(cfg []).profiles`-shaped assertion would go stale the moment Task 2 registers the `consult-full` toggle (`(cfg []).profiles` becomes `{ consult-full = { enable = false; }; }`, not `{ }`). The gate is that every existing check stays green, which proves the namespace is wired into `baseModules` and `readDir ./profiles` resolves. Profile-specific assertions live in Task 2.

- [ ] **Step 1: Create the namespace.** Create `modules/profiles.nix` with exactly:

```nix
# The `profiles` namespace: each profile is a directory under modules/profiles
# whose profile.nix gates a bundle of usePackage settings behind its enable.
{ lib, ... }:
{
  options.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options.enable = lib.mkEnableOption "the ${name} profile";
        }
      )
    );
    default = { };
  };
}
```

- [ ] **Step 2: Create the placeholder so the collector resolves.** Create an empty file `modules/profiles/.gitkeep`:

```bash
mkdir -p modules/profiles && touch modules/profiles/.gitkeep
```

- [ ] **Step 3: Wire the collector into `modules/eval.nix`.** Replace the entire file contents so it reads exactly:

```nix
# ennoixEval's substance: assemble baseModules (namespace + generation +
# build + the collected catalog + the collected profiles) and evaluate user
# modules against them.
{ lib, pkgs }:
let
  catalogDir = ./catalog;
  # Every DIRECTORY under modules/catalog is an entry; its module MUST be
  # named module.nix. A misnamed module fails naturally at import
  # ("path '.../module.nix' does not exist", naming the entry).
  catalogModules = map (name: catalogDir + "/${name}/module.nix") (
    builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir catalogDir))
  );

  # Every DIRECTORY under modules/profiles is a profile; its module MUST be
  # named profile.nix. Toggles are registered here from the dir names so each
  # profile's `enable` materializes at its false default even when off — which
  # lets profile.nix stay a pure `mkIf config.profiles.<name>.enable {…}` body.
  profilesDir = ./profiles;
  profileNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir profilesDir)
  );
  profileModules = map (name: profilesDir + "/${name}/profile.nix") profileNames;
  profileToggles = {
    profiles = lib.genAttrs profileNames (_: { });
  };

  baseModules = [
    ./use-package.nix
    ./generation.nix
    ./build.nix
    ./profiles.nix
    profileToggles
  ]
  ++ catalogModules
  ++ profileModules;
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

- [ ] **Step 4: Verify the collector wires in and breaks nothing.** The scaffold is inert (no profile dir), so the gate is that every existing check stays green — proving `modules/profiles.nix` is reachable in `baseModules` and `readDir ./profiles` resolves (a missing `.gitkeep` or a mis-wired `baseModules` would make `eval.nix` throw and fail these).

Run: `nix fmt && git add modules/profiles.nix modules/profiles/.gitkeep modules/eval.nix && nix build .#ennoix-tests-eval .#ennoix-tests-load .#checks.x86_64-linux.formatting`
Expected: PASS (all).

- [ ] **Step 5: Commit.**

```bash
git add modules/profiles.nix modules/profiles/.gitkeep modules/eval.nix
git commit -m "feat: add profiles namespace and collector"
```

______________________________________________________________________

### Task 2: consult-full profile

**Files:**

- Create: `modules/profiles/consult-full/profile.nix`
- Test: `modules/eval-tests.nix` (add two entries)

**Interfaces:**

- Consumes: `config`/`lib`/`mkCatalogDefault`/`pkgs` from args; the base `consult` module from Plan 1 (merges onto its `bind`/`bindLocal`/`config`/`runtimePackages`); the `profiles.consult-full.enable` toggle registered by Task 1's collector.

- Produces: `profiles.consult-full` — enabling it turns consult on (`mkDefault true`) and yields base ∪ full.

- [ ] **Step 1: Write the failing tests.** Add to `modules/eval-tests.nix` inside `lib.runTests`:

```nix
  testConsultFullOffByDefault = {
    expr = (cfg [ ]).profiles.consult-full.enable;
    expected = false;
  };
  # enabling the profile merges the full binding surface onto the base six
  # (bind/bindLocal union; config = base consult-customize THEN the full one).
  testConsultFullMergedAssembly = {
    expr = assemblyOf "consult" [ { profiles.consult-full.enable = true; } ];
    expected = "(use-package consult\n  :bind ((\"C-M-#\" . consult-register) (\"C-c M-x\" . consult-mode-command) (\"C-c h\" . consult-history) (\"C-c i\" . consult-info) (\"C-c k\" . consult-kmacro) (\"C-c m\" . consult-man) (\"C-x 4 b\" . consult-buffer-other-window) (\"C-x 5 b\" . consult-buffer-other-frame) (\"C-x M-:\" . consult-complex-command) (\"C-x b\" . consult-buffer) (\"C-x p b\" . consult-project-buffer) (\"C-x r b\" . consult-bookmark) (\"C-x t b\" . consult-buffer-other-tab) (\"M-#\" . consult-register-load) (\"M-'\" . consult-register-store) (\"M-g I\" . consult-imenu-multi) (\"M-g M-g\" . consult-goto-line) (\"M-g e\" . consult-compile-error) (\"M-g f\" . consult-flymake) (\"M-g g\" . consult-goto-line) (\"M-g i\" . consult-imenu) (\"M-g k\" . consult-global-mark) (\"M-g m\" . consult-mark) (\"M-g o\" . consult-outline) (\"M-g r\" . consult-grep-match) (\"M-s G\" . consult-git-grep) (\"M-s L\" . consult-line-multi) (\"M-s c\" . consult-locate) (\"M-s d\" . consult-find) (\"M-s e\" . consult-isearch-history) (\"M-s g\" . consult-grep) (\"M-s k\" . consult-keep-lines) (\"M-s l\" . consult-line) (\"M-s r\" . consult-ripgrep) (\"M-s u\" . consult-focus-lines) (\"M-y\" . consult-yank-pop))\n  :bind (:map isearch-mode-map (\"M-e\" . consult-isearch-history) (\"M-s L\" . consult-line-multi) (\"M-s e\" . consult-isearch-history) (\"M-s l\" . consult-line))\n  :bind (:map minibuffer-local-map (\"M-r\" . consult-history) (\"M-s\" . consult-history))\n  :custom ((consult-narrow-key \"<\"))\n  :init (advice-add #'register-preview :override #'consult-register-window)\n(setq register-preview-delay 0.5)\n(setq xref-show-xrefs-function #'consult-xref\n      xref-show-definitions-function #'consult-xref)\n  :config (consult-customize consult-ripgrep :preview-key '(:debounce 0.4 any))\n(consult-customize\n consult-theme :preview-key '(:debounce 0.2 any)\n consult-git-grep consult-grep consult-man consult-bookmark\n consult-recent-file consult-xref\n consult-source-bookmark consult-source-file-register\n consult-source-recent-file consult-source-project-recent-file\n :preview-key '(:debounce 0.4 any))\n  )";
  };
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `git add modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: FAIL — build errors because `profiles.consult-full` is not registered until `modules/profiles/consult-full/` exists (the collector reads directory names). The thrown error is `attribute 'consult-full' missing` from `testConsultFullOffByDefault`.

- [ ] **Step 3: Write the profile.** Create `modules/profiles/consult-full/profile.nix` with exactly:

```nix
# consult's complete README binding surface (the "full" tier), merged onto the
# base six. All at mkCatalogDefault so bind/bindLocal/config MERGE with the base
# consult module. `[remap Info-search]` is omitted (the bind emitter can't
# express a remap vector); consult-info stays on C-c i. consult-locate needs a
# system-provided locate db and binary; consult-git-grep uses ambient `git`.
{
  config,
  lib,
  mkCatalogDefault,
  pkgs,
  ...
}:
lib.mkIf config.profiles.consult-full.enable {
  usePackage.consult.enable = lib.mkDefault true;
  usePackage.consult.bind = mkCatalogDefault {
    "C-c M-x" = "consult-mode-command";
    "C-c h" = "consult-history";
    "C-c k" = "consult-kmacro";
    "C-c m" = "consult-man";
    "C-c i" = "consult-info";
    "C-x M-:" = "consult-complex-command";
    "C-x 4 b" = "consult-buffer-other-window";
    "C-x 5 b" = "consult-buffer-other-frame";
    "C-x t b" = "consult-buffer-other-tab";
    "C-x r b" = "consult-bookmark";
    "C-x p b" = "consult-project-buffer";
    "M-#" = "consult-register-load";
    "M-'" = "consult-register-store";
    "C-M-#" = "consult-register";
    "M-g e" = "consult-compile-error";
    "M-g r" = "consult-grep-match";
    "M-g f" = "consult-flymake";
    "M-g M-g" = "consult-goto-line";
    "M-g o" = "consult-outline";
    "M-g m" = "consult-mark";
    "M-g k" = "consult-global-mark";
    "M-g I" = "consult-imenu-multi";
    "M-s d" = "consult-find";
    "M-s c" = "consult-locate";
    "M-s g" = "consult-grep";
    "M-s G" = "consult-git-grep";
    "M-s L" = "consult-line-multi";
    "M-s k" = "consult-keep-lines";
    "M-s u" = "consult-focus-lines";
    "M-s e" = "consult-isearch-history";
  };
  usePackage.consult.bindLocal = mkCatalogDefault {
    isearch-mode-map = {
      "M-e" = "consult-isearch-history";
      "M-s e" = "consult-isearch-history";
      "M-s L" = "consult-line-multi";
    };
    minibuffer-local-map = {
      "M-s" = "consult-history";
      "M-r" = "consult-history";
    };
  };
  usePackage.consult.config = mkCatalogDefault ''
    (consult-customize
     consult-theme :preview-key '(:debounce 0.2 any)
     consult-git-grep consult-grep consult-man consult-bookmark
     consult-recent-file consult-xref
     consult-source-bookmark consult-source-file-register
     consult-source-recent-file consult-source-project-recent-file
     :preview-key '(:debounce 0.4 any))'';
  usePackage.consult.runtimePackages = mkCatalogDefault [
    pkgs.gnugrep
    pkgs.findutils
  ];
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `nix fmt && git add modules/profiles/consult-full/profile.nix modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: PASS — `testConsultFullOffByDefault` (`false`) and `testConsultFullMergedAssembly` (exact base ∪ full).

- [ ] **Step 5: Commit.**

```bash
git add modules/profiles/consult-full/profile.nix modules/eval-tests.nix
git commit -m "feat(profiles): add consult-full"
```

______________________________________________________________________

### Task 3: enable consult-full in ennoix-emacs-full (CI coverage)

**Files:**

- Modify: `overlays/top-level/ennoix-emacs-full/package.nix` (add a second module enabling the profile)

**Interfaces:**

- Consumes: the `consult-full` profile from Task 2.

- Produces: `ennoix-emacs-full` built with the full consult tier (and `gnugrep`/`findutils` on PATH), so the profile is exercised end-to-end in CI.

- [ ] **Step 1: Enable the profile.** In `overlays/top-level/ennoix-emacs-full/package.nix`, add a second element to the `ennoixEval [ … ]` list so it reads exactly:

```nix
# The ENTIRE catalog enabled — build coverage. Enables are derived
# structurally from the catalog directory names (dir name IS the
# usePackage key); never hand-listed. The consult-full profile is enabled
# explicitly (the structural catalog enable does not reach profiles).
# NOTE: flakes copy the git INDEX — `git add` new catalog entries or local
# -full builds will include drafts that CI (clean checkout) will not see.
{ ennoixEval, lib }:
(ennoixEval [
  {
    usePackage =
      lib.genAttrs
        (builtins.attrNames (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../../../modules/catalog)
        ))
        (_: {
          enable = true;
        });
  }
  { profiles.consult-full.enable = true; }
]).build.package
```

- [ ] **Step 2: Build the whole-catalog load gate.**

Run: `nix fmt && git add overlays/top-level/ennoix-emacs-full/package.nix && nix build .#ennoix-tests-load-full`
Expected: PASS — `ennoix-emacs-full` builds with the full consult tier (its `bind`/`bindLocal`/`config` merged) and `gnugrep`/`findutils`/`ripgrep` wrapped onto PATH, and boots under `--batch` with no load error. May take several minutes on a cold cache.

- [ ] **Step 3: Full check sweep.**

Run: `nix build .#ennoix-tests-eval .#ennoix-tests-load .#checks.x86_64-linux.formatting`
Expected: PASS (all).

- [ ] **Step 4: Commit.**

```bash
git add overlays/top-level/ennoix-emacs-full/package.nix
git commit -m "feat: cover the consult-full tier in ennoix-emacs-full"
```

______________________________________________________________________

## Self-Review

- **Spec coverage:** §3.1 namespace + collector + toggle registration (Task 1), §3.2/§3.3 the gated profile with full-tier bind/bindLocal/config/runtimePackages (Task 2), §3.4 `-full` explicit profile enable (Task 3). §4 Plan-2 tests: merged-assembly equality + off-by-default (Task 2), build/load coverage (Task 3). Appendix A "full" rows are exactly the 30 global binds + isearch-map (3) + minibuffer-map (2) in Task 2's `bind`/`bindLocal`. Covered.
- **Placeholders:** none — `profile.nix`, `profiles.nix`, the `eval.nix` rewrite, and both `expected` strings are verbatim verified content.
- **Type/name consistency:** `profiles.nix` option shape and `profile.nix` arg set (`{ config, lib, mkCatalogDefault, pkgs, ... }`) match `eval.nix` `specialArgs`. The collector names (`profilesDir`/`profileNames`/`profileModules`/`profileToggles`) are self-consistent and appended to `baseModules` after `catalogModules`. `assemblyOf`/`cfg` helpers and the merged/off-by-default assertions match `modules/eval-tests.nix`.
- **Dependency:** Task 2's merged-assembly string assumes Plan 1's base `consult` module is present (verified: profile-off leaves the base assembly byte-identical; profile-on merges to the expected full string). Plan 1 must be merged first.
