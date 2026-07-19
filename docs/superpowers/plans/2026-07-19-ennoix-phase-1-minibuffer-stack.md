# Phase 1 Plan 1 — Minibuffer Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the consult/embark/embark-consult/wgrep minibuffer stack as curated catalog modules (consult = base tier), bundle ripgrep as the first `runtimePackages` use, and wire the four into the flagship.

**Architecture:** Each plugin is a `modules/catalog/<name>/module.nix` auto-collected by `modules/eval.nix`; curated values are set at `mkCatalogDefault`. consult declares `runtimePackages = [ pkgs.ripgrep ]`, which flips `build.package` to a `symlinkJoin`-wrapped emacs with `rg` on `exec-path`. Tests are exact-equality assertions on each entry's `assembly` string in `modules/eval-tests.nix`, plus the existing build/load gates (`ennoix-emacs-full` structurally picks up new catalog dirs).

**Tech Stack:** Nix (NixOS module system, `lib.evalModules`), emacs use-package, treefmt.

**Source of truth:** `docs/superpowers/specs/2026-07-19-ennoix-phase-1-design.md` §1, §4, and Appendix A (base rows). Every module body and every `expected` test string below was emitted by the real `pkgs.ennoixEval` and captured verbatim — do not paraphrase them.

## Global Constraints

- Curated values MUST be wrapped in `mkCatalogDefault` (a `specialArg`, `= lib.mkOverride 1400`). Catalog modules take it from their arguments: `{ mkCatalogDefault, ... }:` (add `pkgs` where a package is referenced).
- Catalog path is exactly `modules/catalog/<name>/module.nix`; the directory name IS the `usePackage` key (which IS the emitted feature and the nixpkgs package name). Never hand-list catalog entries anywhere.
- **`git add` new/changed files before every `nix build`** — flakes copy the git tree and omit untracked files; the repo's own convention (see `overlays/top-level/ennoix-emacs-full/package.nix` header) is to stage first. Commands below do this.
- `nix fmt` before every commit. The formatting check is `nix build .#checks.x86_64-linux.formatting`.
- Do NOT edit `overlays/top-level/ennoix-emacs-full/package.nix` — it derives enables structurally from the catalog directory names, so new modules are picked up automatically.
- Match existing catalog module style (`modules/catalog/magit/module.nix`, `modules/catalog/which-key/module.nix`): one short comment, then the `usePackage.<name>` config. Do NOT add extra options, helpers, or fields beyond what each task specifies.
- Commits MUST NOT contain a `Co-Authored-By: Claude` trailer.
- The eval-test runner is `nix build .#ennoix-tests-eval` (throws a failure list on any mismatch; builds `touch $out` when all pass). Baseline is green before this plan.

______________________________________________________________________

### Task 1: consult catalog module (base tier) + ripgrep runtime wrap

**Files:**

- Create: `modules/catalog/consult/module.nix`
- Test: `modules/eval-tests.nix` (add two entries to the `lib.runTests { … }` attrset)

**Interfaces:**

- Consumes: `mkCatalogDefault` and `pkgs` from module `specialArgs`; the `usePackage` submodule options `init`/`config`/`custom`/`bind`/`bindLocal`/`runtimePackages` (declared in `modules/lib/use-package-type.nix`).

- Produces: a `consult` catalog entry. Later tasks and Plan 2 rely on the base `bind`/`bindLocal`/`config` being at `mkCatalogDefault` priority so the `consult-full` profile can merge onto them.

- [ ] **Step 1: Write the failing tests.** In `modules/eval-tests.nix`, add these two entries inside the `lib.runTests { … }` attrset (e.g. immediately after `testMagitAssembly`):

```nix
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
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `git add modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: FAIL. The thrown failure list contains `testConsultAssembly` (actual `"(use-package consult\n  )"` — no curated fields yet) and `testConsultRuntimeWraps` (actual `false` — no `runtimePackages`, so `build.package` is unwrapped).

- [ ] **Step 3: Write the module.** Create `modules/catalog/consult/module.nix` with exactly:

```nix
{ pkgs, mkCatalogDefault, ... }:
{
  # consult-ripgrep shells out to `rg`, so ripgrep is bundled onto the built
  # emacs's PATH (the first runtimePackages use). Standard-key rebindings
  # (C-x b, M-y, M-g g) are drop-in enhanced replacements per upstream.
  usePackage.consult = {
    init = mkCatalogDefault ''
      (advice-add #'register-preview :override #'consult-register-window)
      (setq register-preview-delay 0.5)
      (setq xref-show-xrefs-function #'consult-xref
            xref-show-definitions-function #'consult-xref)'';
    config = mkCatalogDefault "(consult-customize consult-ripgrep :preview-key '(:debounce 0.4 any))";
    custom = mkCatalogDefault { consult-narrow-key = ''"<"''; };
    bind = mkCatalogDefault {
      "C-x b" = "consult-buffer";
      "M-y" = "consult-yank-pop";
      "M-s l" = "consult-line";
      "M-s r" = "consult-ripgrep";
      "M-g g" = "consult-goto-line";
      "M-g i" = "consult-imenu";
    };
    bindLocal = mkCatalogDefault {
      isearch-mode-map = {
        "M-s l" = "consult-line";
      };
    };
    runtimePackages = mkCatalogDefault [ pkgs.ripgrep ];
  };
}
```

- [ ] **Step 4: Run the tests to verify they pass.**

Run: `nix fmt && git add modules/catalog/consult/module.nix modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: PASS (builds `touch $out`; no throw).

- [ ] **Step 5: Commit.**

```bash
git add modules/catalog/consult/module.nix modules/eval-tests.nix
git commit -m "feat(catalog): add consult base tier with ripgrep runtime wrap"
```

______________________________________________________________________

### Task 2: embark catalog module

**Files:**

- Create: `modules/catalog/embark/module.nix`
- Test: `modules/eval-tests.nix` (add one entry)

**Interfaces:**

- Consumes: `mkCatalogDefault`; the `init`/`config`/`bind` options.

- Produces: an `embark` catalog entry (referenced by Task 5's flagship and by embark-consult).

- [ ] **Step 1: Write the failing test.** Add to `modules/eval-tests.nix` inside `lib.runTests`:

```nix
  testEmbarkAssembly = {
    expr = assemblyOf "embark" [ { usePackage.embark.enable = true; } ];
    expected = "(use-package embark\n  :bind ((\"C-.\" . embark-act) (\"C-;\" . embark-dwim) (\"C-h B\" . embark-bindings))\n  :init (setq prefix-help-command #'embark-prefix-help-command)\n  :config (add-to-list 'display-buffer-alist\n             '(\"\\\\`\\\\*Embark Collect \\\\(Live\\\\|Completions\\\\)\\\\*\"\n               nil\n               (window-parameters (mode-line-format . none))))\n  )";
  };
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `git add modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: FAIL — `testEmbarkAssembly` actual is `"(use-package embark\n  )"`.

- [ ] **Step 3: Write the module.** Create `modules/catalog/embark/module.nix` with exactly:

```nix
{ mkCatalogDefault, ... }:
{
  # C-. / C-; are embark's canonical defaults but don't reach Emacs in a
  # terminal, and C-. is intercepted by GNOME emoji input; override `bind` on
  # affected setups. (C-; also clashes with flyspell-mode.) The display-buffer
  # entry hides the Embark Collect buffers' mode line (embark README).
  usePackage.embark = {
    init = mkCatalogDefault "(setq prefix-help-command #'embark-prefix-help-command)";
    config = mkCatalogDefault ''
      (add-to-list 'display-buffer-alist
                   '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                     nil
                     (window-parameters (mode-line-format . none))))'';
    bind = mkCatalogDefault {
      "C-." = "embark-act";
      "C-;" = "embark-dwim";
      "C-h B" = "embark-bindings";
    };
  };
}
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `nix fmt && git add modules/catalog/embark/module.nix modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add modules/catalog/embark/module.nix modules/eval-tests.nix
git commit -m "feat(catalog): add embark"
```

______________________________________________________________________

### Task 3: embark-consult catalog module

**Files:**

- Create: `modules/catalog/embark-consult/module.nix`
- Test: `modules/eval-tests.nix` (add one entry)

**Interfaces:**

- Consumes: `mkCatalogDefault`; the `after` option.

- Produces: an `embark-consult` catalog entry.

- [ ] **Step 1: Write the failing test.** Add to `modules/eval-tests.nix`:

```nix
  testEmbarkConsultAssembly = {
    expr = assemblyOf "embark-consult" [ { usePackage.embark-consult.enable = true; } ];
    expected = "(use-package embark-consult\n  :after (embark consult)\n  )";
  };
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `git add modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: FAIL — actual is `"(use-package embark-consult\n  )"` (no `:after`).

- [ ] **Step 3: Write the module.** Create `modules/catalog/embark-consult/module.nix` with exactly:

```nix
{ mkCatalogDefault, ... }:
{
  # embark-consult self-registers all integration at load; :after is all
  # ennoix needs (embark also auto-loads it after consult).
  usePackage.embark-consult.after = mkCatalogDefault [ "embark" "consult" ];
}
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `nix fmt && git add modules/catalog/embark-consult/module.nix modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add modules/catalog/embark-consult/module.nix modules/eval-tests.nix
git commit -m "feat(catalog): add embark-consult"
```

______________________________________________________________________

### Task 4: wgrep catalog module

**Files:**

- Create: `modules/catalog/wgrep/module.nix`
- Test: `modules/eval-tests.nix` (add one entry)

**Interfaces:**

- Consumes: `mkCatalogDefault`; the `demand` option.

- Produces: a `wgrep` catalog entry.

- [ ] **Step 1: Write the failing test.** Add to `modules/eval-tests.nix`:

```nix
  testWgrepAssembly = {
    expr = assemblyOf "wgrep" [ { usePackage.wgrep.enable = true; } ];
    expected = "(use-package wgrep\n  :demand t\n  )";
  };
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `git add modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: FAIL — actual is `"(use-package wgrep\n  )"` (no `:demand t`).

- [ ] **Step 3: Write the module.** Create `modules/catalog/wgrep/module.nix` with exactly:

```nix
{ mkCatalogDefault, ... }:
{
  # Self-installing (grep-setup-hook binds C-c C-p); nothing to configure.
  usePackage.wgrep.demand = mkCatalogDefault true;
}
```

- [ ] **Step 4: Run the test to verify it passes.**

Run: `nix fmt && git add modules/catalog/wgrep/module.nix modules/eval-tests.nix && nix build .#ennoix-tests-eval`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add modules/catalog/wgrep/module.nix modules/eval-tests.nix
git commit -m "feat(catalog): add wgrep"
```

______________________________________________________________________

### Task 5: Flagship wiring + build/load coverage

**Files:**

- Modify: `overlays/top-level/ennoix-emacs/package.nix` (add four enables to the hand-listed `usePackage` attrset)

**Interfaces:**

- Consumes: the four catalog entries from Tasks 1–4.

- Produces: a flagship (`ennoix-emacs`) that ships the minibuffer stack (consult = base tier). `ennoix-emacs-full` gains the four automatically via its structural catalog-dir enable (no edit).

- [ ] **Step 1: Add the four enables.** In `overlays/top-level/ennoix-emacs/package.nix`, extend the `usePackage = { … };` attrset so it reads exactly (alphabetical):

```nix
    usePackage = {
      consult.enable = true;
      embark.enable = true;
      embark-consult.enable = true;
      magit.enable = true;
      marginalia.enable = true;
      modus-themes.enable = true;
      orderless.enable = true;
      savehist.enable = true;
      vertico.enable = true;
      wgrep.enable = true;
      which-key.enable = true;
    };
```

- [ ] **Step 2: Build the flagship and run its load gate.**

Run: `nix fmt && git add overlays/top-level/ennoix-emacs/package.nix && nix build .#ennoix-tests-load`
Expected: PASS — the flagship boots under `--batch` with the four packages and produces no load error (the gate greps for error markers and the success marker). This is a positive boot gate, not a RED→GREEN assertion: the load gate only asserts no startup error, so it exercises the four packages at load but would not have "failed" before Step 1 (the flagship simply shipped fewer packages).

- [ ] **Step 3: Build the whole-catalog load gate (covers -full auto-pickup + ripgrep wrap).**

Run: `nix build .#ennoix-tests-load-full`
Expected: PASS — `ennoix-emacs-full` (now including consult/embark/embark-consult/wgrep via structural enable, wrapped with ripgrep) builds and boots with no load error. Note: this compiles emacs with the full catalog and may take several minutes on a cold cache.

- [ ] **Step 4: Full check sweep.**

Run: `nix build .#ennoix-tests-eval .#checks.x86_64-linux.formatting`
Expected: PASS (both).

- [ ] **Step 5: Commit.**

```bash
git add overlays/top-level/ennoix-emacs/package.nix
git commit -m "feat: ship minibuffer stack in the flagship"
```

______________________________________________________________________

## Self-Review

- **Spec coverage:** §1.1 consult (Task 1, incl. runtimePackages/ripgrep), §1.2 embark (Task 2), §1.3 embark-consult (Task 3), §1.4 wgrep (Task 4), §1.5 flagship + `-full` auto-pickup (Task 5). §4 eval tests (assembly equality per module + `testConsultRuntimeWraps`) and load gates (Task 5 Steps 2–3). Appendix A "base" rows are exactly the six binds + one bindLocal in Task 1. Covered.
- **Out of plan (Plan 2):** profiles mechanism, `consult-full`, the `-full` profile-enable edit. Not touched here — Plan 1 ships and merges independently.
- **Placeholders:** none — every module body and `expected` string is the verbatim verified emission.
- **Type/name consistency:** module arg sets (`{ pkgs, mkCatalogDefault, ... }` for consult; `{ mkCatalogDefault, ... }` for the rest) match `eval.nix`'s `specialArgs`. Option names (`init`/`config`/`custom`/`bind`/`bindLocal`/`runtimePackages`/`after`/`demand`) all exist in `modules/lib/use-package-type.nix`. Test helper `assemblyOf`/`cfg` and args `{ lib, ennoixEval, hello }` match `modules/eval-tests.nix`.
