# ennoix Phase 1 design — minibuffer stack + profiles

Status: design for the roadmap's Phase 1 (consult/embark/embark-consult/wgrep, first `runtimePackages` use) plus a `profiles` mechanism pulled forward to host curated config *tiers*.
Builds on the re-architecture (`2026-07-06-ennoix-rearchitecture-design.md`), whose foundation ships on `main`.
Every config below was re-derived from upstream source and its emission verified through the real `pkgs.ennoixEval`; the profiles mechanism was prototyped and eval-verified.

This spec spans two subsystems and is implemented as **two sequential plans** (see §5):

- **Plan 1 — the minibuffer stack**: four catalog modules + ripgrep runtime binary. Ships independently.
- **Plan 2 — profiles + `consult-full`**: the `profiles` namespace/collector and the first profile. Builds on Plan 1.

______________________________________________________________________

## 1. The four catalog modules (Plan 1)

Each is `modules/catalog/<name>/module.nix`, auto-collected, curated values at `mkCatalogDefault` (`mkOverride 1400`).
The four packages and `ripgrep` are all present in the pinned nixpkgs.

### 1.1 consult — the base (minimal) tier

`modules/catalog/consult/module.nix` (curated defaults):

- `init` (runs before load, from consult's README):
  ```elisp
  (advice-add #'register-preview :override #'consult-register-window)
  (setq register-preview-delay 0.5)
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  ```
- `config`: `(consult-customize consult-ripgrep :preview-key '(:debounce 0.4 any))`
- `custom`: `{ consult-narrow-key = ''"<"''; }` → `:custom ((consult-narrow-key "<"))`
- `bind` (global — the six headline commands):
  `C-x b`→consult-buffer, `M-y`→consult-yank-pop, `M-s l`→consult-line, `M-s r`→consult-ripgrep, `M-g g`→consult-goto-line, `M-g i`→consult-imenu
- `bindLocal`: `{ isearch-mode-map = { "M-s l" = "consult-line"; }; }` (lets consult-line take over an active isearch)
- `runtimePackages = [ pkgs.ripgrep ]` — **the first runtimePackages use**; `consult-ripgrep` shells out to `rg`, and `build.package` becomes the `symlinkJoin`-wrapped emacs with `rg` on `exec-path` (verified: this flips `build.package` to the wrapped derivation).

Standard-key rebindings (`C-x b`/switch-to-buffer, `M-y`/yank-pop, `M-g g`/goto-line) are drop-in enhanced replacements per upstream's own inline comments.

Verified emission:

```elisp
(use-package consult
  :bind (("C-x b" . consult-buffer) ("M-g g" . consult-goto-line) ("M-g i" . consult-imenu) ("M-s l" . consult-line) ("M-s r" . consult-ripgrep) ("M-y" . consult-yank-pop))
  :bind (:map isearch-mode-map ("M-s l" . consult-line))
  :custom ((consult-narrow-key "<"))
  :init … :config … )
```

### 1.2 embark

`modules/catalog/embark/module.nix`:

- `init`: `(setq prefix-help-command #'embark-prefix-help-command)`
- `config`: the README's `display-buffer-alist` entry hiding the Embark Collect buffers' mode line.
- `bind`: `C-.`→embark-act, `C-;`→embark-dwim, `C-h B`→embark-bindings

Decision recorded (B(a)): ship the author's `C-.`/`C-;` defaults and **document the caveat** — `C-.` is intercepted by GNOME emoji-input and does not work in a terminal; users on those setups rebind `embark-act` (the caveat goes in the module comment).

### 1.3 embark-consult

`modules/catalog/embark-consult/module.nix`: **only** `after = [ "embark" "consult" ]`.
Re-confirmed from source (`embark-consult.el`): the package self-registers all integration at load — the Consult preview hook (`(add-hook 'embark-collect-mode-hook 'consult--default-completion-list-preview-setup)`, line ~490), the marker upgrade (`cl-pushnew … embark-collect-mode-hook`, line ~192), exporters, and the `embark-consult-search-map` wiring inside Embark's own keymaps.
None of it is user-facing config, so ennoix adds nothing beyond `:after`.
Verified emission: `(use-package embark-consult\n  :after (embark consult)\n  )`.

### 1.4 wgrep

`modules/catalog/wgrep/module.nix`: `demand = true`, nothing else.
wgrep makes grep buffers editable and self-installs its `C-c C-p` entry key into grep buffers via its own autoloaded `grep-setup-hook`; there is nothing for ennoix to configure.
`demand = true` matches the README's canonical `(require 'wgrep)`, costs ~nothing (tiny dependency-free file), and signals a deliberate "self-installing, nothing to configure" entry rather than an accidentally-empty module.

### 1.5 Flagship + coverage packages

- **`ennoix-emacs`** (flagship, `nix run`): add all four to the hand-listed curated starter (decision C(a)) — the minibuffer stack is a coherent upgrade to the vertico/marginalia it already ships. consult ships the **base** tier here.
- **`ennoix-emacs-full`**: gains the four via the structural catalog-dir enable it already computes; in Plan 2 it additionally enables `profiles.consult-full` so the full consult tier is build-covered.

______________________________________________________________________

## 2. consult's two tiers

Decision A: ship two curated tiers of consult.

- **base** (option a) = the six bindings above, in `consult/module.nix` — everyone gets this on `usePackage.consult.enable`.
- **full** (option c) = consult's *complete* README use-package binding surface — delivered as a **profile** (§3), not a second catalog entry.

The full tier adds, on top of the base six, the remainder of consult's README example (all at `mkCatalogDefault`, so they *merge* onto the base — verified that two `mkCatalogDefault` bind sets merge at priority 1400):

- global: the `C-c` command surface (`C-c M-x`/`h`/`k`/`m`/`i`), `C-x M-:`, `C-x 4 b`/`5 b`/`t b`, `C-x r b`, `C-x p b`, the register keys (`M-#`/`M-'`/`C-M-#`), `M-g e`/`f`/`M-g`/`o`/`m`/`k`/`I`, `M-s d`/`c`/`g`/`G`/`L`/`k`/`u`/`e`
- `bindLocal`: `isearch-mode-map` (`M-e`, `M-s e`, `M-s L`) and `minibuffer-local-map` (`M-s`, `M-r` → consult-history)
- `config`: extend `consult-customize`'s preview-key debounce to the full command list.

Rationale for tiers-not-one-set: the locked override-*replace* semantics mean a user who sets `usePackage.consult.bind` at all replaces the whole curated set — so "add a few later" is costly. Two curated tiers give the common minimal default and a one-toggle full set, without forcing the large surface on everyone.

______________________________________________________________________

## 3. The profiles mechanism (Plan 2)

A profile is a named, gated bundle of `usePackage` settings — the module-system-native way to offer curated config *tiers/bundles* without a second package entry, without user-facing path imports, and without breaking the catalog's `dir name = entry key = feature = package` invariant.
(Prototyped and eval-verified; chosen over the alternative of a `feature`-decoupling option on the type, which would have broken that invariant and introduced a double-enable footgun.)

### 3.1 Namespace and collector

- **`modules/profiles.nix`** — declares `options.profiles = attrsOf (submodule { options.enable = mkEnableOption …; })`.
- **`modules/eval.nix`** — a profiles collector mirroring the catalog collector: read `modules/profiles/<name>/` directories, **register `profiles.<name>` for each** (so every profile's `enable` toggle exists, defaulting `false`, even when the profile is off), and import each `modules/profiles/<name>/profile.nix` into `baseModules`.
  (Registering the toggles from the directory names — rather than each profile self-registering — keeps `profile.nix` files pure `mkIf` bodies.)
- `profiles.nix` joins `baseModules` beside `use-package.nix`/`generation.nix`/`build.nix`.

### 3.2 A profile module

`modules/profiles/<name>/profile.nix` is a gated module:

```nix
{ config, lib, mkCatalogDefault, ... }:
lib.mkIf config.profiles.<name>.enable {
  # any usePackage.* settings — merged onto catalog defaults at mkCatalogDefault priority
}
```

### 3.3 `modules/profiles/consult-full/profile.nix`

```nix
{ config, lib, mkCatalogDefault, ... }:
lib.mkIf config.profiles.consult-full.enable {
  usePackage.consult.enable = lib.mkDefault true;      # ensure consult is on (user may still disable)
  usePackage.consult.bind = mkCatalogDefault { … full-tier global binds … };
  usePackage.consult.bindLocal = mkCatalogDefault { … full-tier map-scoped binds … };
  usePackage.consult.config = mkCatalogDefault "… consult-customize full preview list …";
}
```

Because the profile's `bind`/`bindLocal`/`config` are at `mkCatalogDefault` (1400) and the base module's are too, they **merge** — so enabling `profiles.consult-full` yields base ∪ full.
A user override at plain priority still replaces the merged set wholesale (the locked semantics hold).
Verified end-to-end: `usePackage.consult.enable` → base six; `profiles.consult-full.enable` → base ∪ extended, same `(use-package consult …)` form.

### 3.4 Package coverage

`ennoix-emacs-full` enables `profiles.consult-full` (via its modules list) so the full tier is built in CI and runnable; `ennoix-emacs` keeps the base tier.

______________________________________________________________________

## 4. Tests

Following the re-architecture's four tiers:

- **Eval tests** (`modules/eval-tests.nix`): emitter-equality on the per-entry `assembly` for each new module — consult base (incl. the `bind`+`bindLocal`+`custom`+`runtimePackages` shape and that `build.package` becomes the `ennoix-`-prefixed wrapped derivation when ripgrep is present), embark, embark-consult (`:after` only), wgrep (`:demand t`). For Plan 2: a test that `profiles.consult-full.enable` merges the extended binds onto the base (exact `assembly` equality), and that it's off by default.
- **Build coverage**: `ennoix-emacs-full` (now including the four + the full-consult profile) must build — covers ripgrep wrapping and every new package.
- **`--batch` load gates**: the flagship and `-full` gates boot and assert no load errors (magit already; now the minibuffer stack too). Note the issue-#4 limitation (startup-time only) — embark's `C-.` binding and consult's deferred commands aren't exercised at load.
- **VM tests**: still deferred (no interactive surface tested yet).

______________________________________________________________________

## 5. Plan decomposition

- **Plan 1 — minibuffer stack**: `modules/catalog/{consult,embark,embark-consult,wgrep}/module.nix` (consult = base tier), the four in the flagship, eval + load tests, ripgrep runtime wrapping exercised. Ships and merges independently.
- **Plan 2 — profiles + consult-full**: `modules/profiles.nix`, the eval.nix collector, `modules/profiles/consult-full/profile.nix` (the full tier), `-full` enables it, tests for the profile. Depends on Plan 1's consult module.

Out of scope (later): the general profiles catalog beyond consult-full (doom-style multi-plugin bundles), HM/NixOS adapters, the rest of the roadmap.
