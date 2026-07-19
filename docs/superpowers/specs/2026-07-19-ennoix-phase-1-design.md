# ennoix Phase 1 design — minibuffer stack + profiles

Status: design for the roadmap's Phase 1 (consult/embark/embark-consult/wgrep, first `runtimePackages` use) plus a `profiles` mechanism pulled forward to host curated config *tiers*.
Builds on the re-architecture (`2026-07-06-ennoix-rearchitecture-design.md`), whose foundation ships on `main`.
Every config in this spec was re-derived from the pinned upstream sources (consult @ `8c6787e`, embark, wgrep) and its emission verified through the real `pkgs.ennoixEval`; the profiles mechanism (collector registration, `mkDefault`-flips-enable, equal-priority merge of `bind`/`bindLocal`/`config`) was verified by direct `nix eval` against the flake.
Exact, implementable content (elisp bodies, the full consult binding table, the collector expression) is inline here and in Appendix A — nothing is left to reconstruct at plan time.

This spec spans two subsystems and is implemented as **two sequential plans** (see §5):

- **Plan 1 — the minibuffer stack**: four catalog modules + ripgrep runtime binary. Ships independently.
- **Plan 2 — profiles + `consult-full`**: the `profiles` namespace/collector and the first profile. Builds on Plan 1.

______________________________________________________________________

## 1. The four catalog modules (Plan 1)

Each is `modules/catalog/<name>/module.nix`, auto-collected by `eval.nix`, with curated values set at `mkCatalogDefault` (`lib.mkOverride 1400`).
All four packages (`consult`, `embark`, `embark-consult`, `wgrep`) and `ripgrep`/`gnugrep`/`findutils` are present in the pinned nixpkgs.

### 1.1 consult — the base (minimal) tier

`modules/catalog/consult/module.nix` sets, at `mkCatalogDefault`:

- `init` (from consult's README `:init`, verbatim, comments dropped):
  ```elisp
  (advice-add #'register-preview :override #'consult-register-window)
  (setq register-preview-delay 0.5)
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  ```
- `config`: `(consult-customize consult-ripgrep :preview-key '(:debounce 0.4 any))` — the base tier binds `consult-ripgrep`, so it customizes exactly that one command's preview debounce. (The README customizes a longer list in one form; the base tier carries only the part covering commands it binds. See the F5 deviation note below.)
- `custom`: `{ consult-narrow-key = ''"<"''; }` → emits `:custom ((consult-narrow-key "<"))`. (Deviation F4: the README sets this via `(setq consult-narrow-key "<")` in `:config`; `consult-narrow-key` is a `defcustom`, so `:custom` is semantically equivalent and is the deliberate ennoix idiom. The string value carries its own quotes because `:custom` string values are emitted verbatim.)
- `bind` (global — the six headline commands): see Appendix A "base" rows.
- `bindLocal`: `{ isearch-mode-map = { "M-s l" = "consult-line"; }; }` (README: "needed by consult-line to detect isearch").
- `runtimePackages = [ pkgs.ripgrep ]` — **the first `runtimePackages` use.** Of the six base commands, only `consult-ripgrep` shells out to a binary (`rg`); the other five are pure elisp (verified against consult source). Declaring `runtimePackages` flips `build.package` from the bare emacs to the `symlinkJoin`-wrapped emacs that puts `rg` on `exec-path` (verified: `build.package.name` gains the `ennoix-` prefix).

Standard-key rebindings (`C-x b`/switch-to-buffer, `M-y`/yank-pop, `M-g g`/goto-line) are drop-in enhanced replacements per upstream's own inline comments.

### 1.2 embark

`modules/catalog/embark/module.nix`, at `mkCatalogDefault`:

- `init`: `(setq prefix-help-command #'embark-prefix-help-command)`
- `config` (embark README's exact `:config` snippet — must be written in a Nix indented string `''…''` so the elisp backslash escapes survive verbatim into `assembly`):
  ```elisp
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none))))
  ```
- `bind`: `{ "C-." = "embark-act"; "C-;" = "embark-dwim"; "C-h B" = "embark-bindings"; }`

Documented caveat (decision B(a): ship the author's defaults and document): the embark README itself notes `C-.`/`C-;` "are unlikely to work in the terminal," and `C-.` is intercepted by some desktop emoji-input methods. The README's own suggested alternatives are `M-.` for `embark-dwim` (which shadows `xref-find-definitions`) and rebinding `embark-act`. This caveat goes in the module comment; users on affected setups override `bind`.

### 1.3 embark-consult

`modules/catalog/embark-consult/module.nix`: **only** `after = [ "embark" "consult" ]` → emits `(use-package embark-consult\n  :after (embark consult)\n  )`.
Re-confirmed from source (`embark-consult.el`, all at load time / top level after `(require 'embark)`/`(require 'consult)`): the Consult preview hook (`(add-hook 'embark-collect-mode-hook 'consult--default-completion-list-preview-setup)`, :490), the marker upgrade (`(cl-pushnew #'embark-consult--upgrade-markers embark-collect-mode-hook)`, :192), exporters, and the `embark-consult-search-map` wiring are all self-registered on load.
Additionally, `embark.el` auto-`require`s `embark-consult` via `(with-eval-after-load 'consult …)` — so the embark README installs embark-consult with `:ensure t` and *no* `:after`. ennoix's explicit `:after [embark consult]` is a slightly-more-conservative superset (defers until both are loaded); nothing else is user-facing, so ennoix adds nothing beyond it.

### 1.4 wgrep

`modules/catalog/wgrep/module.nix`: `demand = true` → emits `:demand t`, nothing else.
Verified against wgrep source: `(add-hook 'grep-setup-hook 'wgrep-setup)` is an autoloaded top-level form; `wgrep-setup` installs `wgrep-enable-key` (defcustom, default `C-c C-p`) into each grep buffer's local map. The three README setqs (`wgrep-auto-save-buffer`, `wgrep-enable-key`, `wgrep-change-readonly-file`) are genuinely optional. So there is nothing to configure. `demand = true` mirrors the README's canonical `(require 'wgrep)`, costs ~nothing (tiny dependency-free file), and marks a deliberate "self-installing, nothing to configure" entry rather than an accidentally-empty module.

### 1.5 Flagship + coverage packages (Plan 1 wiring)

- **`ennoix-emacs`** (flagship, `nix run`): the four are added to the **hand-listed** `usePackage = { … }` starter attrset in `overlays/top-level/ennoix-emacs/package.nix` — four new lines: `consult.enable = true; embark.enable = true; embark-consult.enable = true; wgrep.enable = true;`. consult ships the **base** tier here.
- **`ennoix-emacs-full`**: needs **zero edits in Plan 1.** It derives its enables structurally via `lib.genAttrs (attrNames (readDir modules/catalog)) …` in `overlays/top-level/ennoix-emacs-full/package.nix`, so the moment the four `modules/catalog/<name>/` dirs exist, `-full` enables them automatically. (Its consult-full profile enable is a Plan-2 edit; see §3.4.)

______________________________________________________________________

## 2. consult's two tiers

Decision A: ship two curated tiers of consult.

- **base** (option a) = the six bindings above, in `consult/module.nix` — everyone gets this on `usePackage.consult.enable`.
- **full** (option c) = consult's *complete README use-package binding surface, restricted to what the emitter can express* — delivered as a **profile** (§3), not a second catalog entry. See Appendix A for the exact key→command table (base + full), transcribed from consult README @ `8c6787e`.

**Faithfulness scope of the "full" tier** (the honest boundary):

- **Included**: every global and map-local binding in the README `:bind` block that the `attrsOf str` `bind`/`bindLocal` options can express — including `M-g r → consult-grep-match` (F1) and the duplicate `M-g M-g → consult-goto-line` alias (F6), both of which the earlier prose draft had dropped.
- **Excluded — one binding, by hard emitter limitation (F2)**: `[remap Info-search] → consult-info`. Verified: the emitter wraps every `bind` key in `"…"`, producing `("[remap Info-search]" . consult-info)`, which `kbd` cannot turn into a remap. `consult-info` remains reachable via `C-c i` (also bound), so the command is not lost — only its remap alias is. This is a documented cut, not a silent omission; expressing remaps would require an emitter change, which is out of scope.
- **Runtime binaries (F3)**: the full tier binds `consult-grep` (`grep`), `consult-find` (`find`), `consult-git-grep` (`git`), `consult-locate` (`locate`). Decision: the `consult-full` profile bundles **`gnugrep` + `findutils`** via `runtimePackages` (the stateless tools where bundling makes the command work standalone, consistent with the ripgrep precedent). `git` is left to the ambient PATH (near-universal for git users; bundling it adds a large closure and `consult-git-grep` only works inside a repo regardless). `locate` is **un-bundleable**: it queries a `locate` database built by a system-level `updatedb` job, which a build-time emacs derivation cannot provision; the binary alone is inert. Both `git` and `locate` reliance are documented in the profile comment.
- **config (F5)**: the base module customizes only `consult-ripgrep`; the full tier's `config` is a **second** `consult-customize` form (see §3.3) covering the README's remaining customized commands (`consult-theme` at `:debounce 0.2`, and `consult-git-grep`/`consult-grep`/`consult-man`/`consult-bookmark`/`consult-recent-file`/`consult-xref`/the four `consult-source-*` at `:debounce 0.4`). Base ∪ profile = the README's single `consult-customize` set, split across two emitted forms.

Rationale for tiers-not-one-set: the locked override-*replace* semantics mean a user who sets `usePackage.consult.bind` at all replaces the whole curated set — so "add a few later" is costly. Two curated tiers give the common minimal default and a one-toggle full set, without forcing the large surface on everyone.

______________________________________________________________________

## 3. The profiles mechanism (Plan 2)

A profile is a named, gated bundle of `usePackage` settings — the module-system-native way to offer curated config *tiers/bundles* without a second package entry, without user-facing path imports, and without breaking the catalog's `dir name = entry key = feature = package` invariant.
(Prototyped and eval-verified; chosen over the alternative of a `feature`-decoupling option on the type, which would have broken that invariant and introduced a double-enable footgun.)

### 3.1 Namespace, collector, and toggle registration

- **`modules/profiles.nix`** (new) declares the namespace:
  ```nix
  { lib, ... }:
  {
    options.profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: { options.enable = lib.mkEnableOption "the ${name} profile"; }
        )
      );
      default = { };
    };
  }
  ```
- **`modules/eval.nix`** gains a profiles collector mirroring the catalog collector. It reads `modules/profiles/<name>/` directory names, **registers each toggle** so `profiles.<name>.enable` materializes at its `false` default even when the profile is off, and imports each `profile.nix`:
  ```nix
  profilesDir = ./profiles;
  profileNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir profilesDir)
  );
  profileModules = map (name: profilesDir + "/${name}/profile.nix") profileNames;
  # materialize every profile toggle (enable defaults false), mirroring how
  # catalog modules materialize disabled entries. Without this, a pure-`mkIf`
  # profile.nix reading `config.profiles.<name>.enable` throws "attribute
  # '<name>' missing" when the profile is off.
  profileToggles = { profiles = lib.genAttrs profileNames (_: { }); };
  ```
  and `baseModules` becomes:
  ```nix
  baseModules = [
    ./use-package.nix
    ./generation.nix
    ./build.nix
    ./profiles.nix
    profileToggles
  ]
  ++ catalogModules
  ++ profileModules;
  ```
  **Ordering contract (load-bearing for the §4 assembly test):** `profileModules` is appended **after** `catalogModules`, and `attrNames (readDir …)` is lexicographically sorted, so the merge/concatenation order of any option a catalog module and a profile both define (notably `config`, type `lines`) is deterministically **catalog-then-profile**. The `consult-full` assembly test hard-codes that order; do not interleave the collectors.
  (Registering the toggles in the collector — rather than each `profile.nix` self-registering — keeps `profile.nix` files pure `mkIf` bodies.)

### 3.2 A profile module

`modules/profiles/<name>/profile.nix` is a gated module — a pure `mkIf` body:

```nix
{ config, lib, mkCatalogDefault, ... }:
lib.mkIf config.profiles.<name>.enable {
  # any usePackage.* settings — merged onto catalog defaults at mkCatalogDefault priority
}
```

### 3.3 `modules/profiles/consult-full/profile.nix`

```nix
{ config, lib, mkCatalogDefault, pkgs, ... }:
lib.mkIf config.profiles.consult-full.enable {
  usePackage.consult.enable = lib.mkDefault true;      # ensure consult is on; user may still disable
  usePackage.consult.bind = mkCatalogDefault { … full-tier global binds (Appendix A) … };
  usePackage.consult.bindLocal = mkCatalogDefault { … full-tier map-scoped binds (Appendix A) … };
  usePackage.consult.config = mkCatalogDefault ''
    (consult-customize
     consult-theme :preview-key '(:debounce 0.2 any)
     consult-git-grep consult-grep consult-man consult-bookmark
     consult-recent-file consult-xref
     consult-source-bookmark consult-source-file-register
     consult-source-recent-file consult-source-project-recent-file
     :preview-key '(:debounce 0.4 any))'';
  usePackage.consult.runtimePackages = [ pkgs.gnugrep pkgs.findutils ];
}
```

Semantics (all verified by `nix eval` against the flake):

- **`mkDefault true` flips enable on.** `mkEnableOption`'s default is a bare `false` at option-default priority (1500); `mkDefault` (1000) beats it, so the profile turns consult on. A user's plain `usePackage.consult.enable = false` (100) still wins and disables. (`mkForce` would have blocked the user; `mkDefault` is the deliberate, more-polite choice. In `-full`, the structural catalog-enable already sets `consult.enable = true` at plain priority, so this line is redundant-but-harmless there; it matters for a user who enables *only* the profile.)
- **`bind` / `bindLocal` MERGE onto the base.** Both the base module's and the profile's definitions are at `mkCatalogDefault` (1400); `attrsOf` (and nested `attrsOf (attrsOf str)`) definitions at equal priority merge, so enabling the profile yields base ∪ full — one `:bind (…)` with the union of global keys and one `:bind (:map isearch-mode-map …)` with the union of that map's keys, plus a new `:bind (:map minibuffer-local-map …)`.
- **`config` CONCATENATES (does not conflict).** `lines`-typed defs at equal priority concatenate; enabling the profile emits **two** top-level `consult-customize` forms in `:config` — base's `consult-ripgrep` form, then the profile's form for the rest. This is why the profile form omits `consult-ripgrep` (base already covers it): base ∪ profile = the README's single customized set, no double-customization. (Cosmetic: the concatenated second line lands at column 0 in the emitted `:config`; the assembly test must encode that exactly.)
- **Merge vs replace (callout).** The equal-priority *merge* here is catalog-layer ∪ catalog-layer. It is distinct from the repo's locked contract that a **user** definition (plain priority 100) *replaces* a `mkCatalogDefault` set wholesale — that contract still holds: a user who sets `usePackage.consult.bind` overrides the entire merged base ∪ full set.
- Base-only fields (`init`, `custom`, base `runtimePackages`) are untouched by the profile (single-definer fields pass through the merge).

### 3.4 Package coverage (Plan 2 wiring)

`overlays/top-level/ennoix-emacs-full/package.nix` is edited to add an explicit `{ profiles.consult-full.enable = true; }` module to its `ennoixEval` module list (the structural catalog-dir enable reads `modules/catalog` only and will **never** auto-pick-up a `profiles.*` toggle). Concretely, its single-module eval list becomes a two-element list: the existing structural-enable attrset plus `{ profiles.consult-full.enable = true; }`. This builds the full tier in CI and makes it runnable. `ennoix-emacs` keeps the base tier.

______________________________________________________________________

## 4. Tests

Following the re-architecture's four tiers:

- **Eval tests** (`modules/eval-tests.nix`, whose helper is `assemblyOf = name: modules: (cfg modules).usePackage.${name}.assembly`):
  - Per-module emitter-equality on `assembly` for each new module — consult base (the `bind` + `bindLocal` + `custom` + `init` + `config` shape), embark, embark-consult (`:after` only), wgrep (`:demand t`).
  - **Runtime-wrap branch check** (per the existing `testRuntimeWrapsPackage` precedent, eval-tests.nix): assert `lib.hasPrefix "ennoix-" (cfg [ { usePackage.consult.enable = true; } ]).build.package.name` — i.e. declaring consult (with `runtimePackages = [ripgrep]`) selects the wrapper branch. This asserts the *branch was taken*, not that `rg` resolves at runtime — actual `rg`-on-PATH is build-tier/interactive only (issue #4).
  - **Plan 2 — profile merge**: `assemblyOf "consult" [ { profiles.consult-full.enable = true; } ]` equals the exact expected base ∪ full form (encoding the catalog-then-profile `config` order and its column-0 second line).
  - **Plan 2 — off by default**: `(cfg [ ]).profiles.consult-full.enable == false` (relies on the `profileToggles` registration from §3.1, which materializes the toggle even when off).
- **Build coverage**: `ennoix-emacs-full` (now including the four packages + the `consult-full` profile) must build — covers ripgrep + gnugrep + findutils wrapping and every new elisp package.
- **`--batch` load gates**: the flagship and `-full` gates boot and assert no load errors (now including the minibuffer stack). Startup-time only (issue #4): embark's `C-.` binding and consult's deferred commands are not exercised at load.
- **VM tests**: still deferred (no interactive surface tested yet).

______________________________________________________________________

## 5. Plan decomposition

- **Plan 1 — minibuffer stack**: `modules/catalog/{consult,embark,embark-consult,wgrep}/module.nix` (consult = base tier), the four added to the flagship's hand-listed starter, eval + load tests, ripgrep runtime wrapping exercised. `-full` picks up the four automatically (no `-full` edit). Ships and merges independently.
- **Plan 2 — profiles + consult-full**: `modules/profiles.nix`, the `eval.nix` collector + `profileToggles` registration, `modules/profiles/consult-full/profile.nix` (the full tier, incl. `gnugrep`+`findutils`), the explicit `-full` profile-enable edit, and the profile merge / off-by-default tests. Depends on Plan 1's consult module.

Out of scope (later): the general profiles catalog beyond `consult-full` (doom-style multi-plugin bundles), a `bind` emitter that can express `[remap …]` vectors, HM/NixOS adapters, the rest of the roadmap.

Explicitly deferred to its own design pass — a **personal vim-experience profile** (evil-mode + evil-collection + leader-key framework + terminal-safe/leader embark bindings). Unlike `consult-full` (additive), such a profile *replaces* curated defaults; the verified idiom for that is a three-layer priority ladder — catalog (`mkOverride 1400`) ← profile (`mkOverride ≈500`) ← user (plain 100), each layer replacing the one below (confirmed by `nix eval`). Phase 1 therefore ships **additive-only** profiles (all `consult-full` needs); the replacing-priority idiom is not built until that profile is.

______________________________________________________________________

## Appendix A — exact consult binding table (verified against consult README @ `8c6787e`)

Legend: **base** rows live in `consult/module.nix`; **full** rows are added by `consult-full/profile.nix`. `[remap Info-search] → consult-info` is in the README but **excluded** (emitter can't express it; `C-c i` covers the command).

### Global `bind`

| key | command | tier |
|-----|---------|------|
| `C-c M-x` | `consult-mode-command` | full |
| `C-c h` | `consult-history` | full |
| `C-c k` | `consult-kmacro` | full |
| `C-c m` | `consult-man` | full |
| `C-c i` | `consult-info` | full |
| `C-x M-:` | `consult-complex-command` | full |
| `C-x b` | `consult-buffer` | **base** |
| `C-x 4 b` | `consult-buffer-other-window` | full |
| `C-x 5 b` | `consult-buffer-other-frame` | full |
| `C-x t b` | `consult-buffer-other-tab` | full |
| `C-x r b` | `consult-bookmark` | full |
| `C-x p b` | `consult-project-buffer` | full |
| `M-#` | `consult-register-load` | full |
| `M-'` | `consult-register-store` | full |
| `C-M-#` | `consult-register` | full |
| `M-y` | `consult-yank-pop` | **base** |
| `M-g e` | `consult-compile-error` | full |
| `M-g r` | `consult-grep-match` | full (F1) |
| `M-g f` | `consult-flymake` | full |
| `M-g g` | `consult-goto-line` | **base** |
| `M-g M-g` | `consult-goto-line` | full (F6, alias) |
| `M-g o` | `consult-outline` | full |
| `M-g m` | `consult-mark` | full |
| `M-g k` | `consult-global-mark` | full |
| `M-g i` | `consult-imenu` | **base** |
| `M-g I` | `consult-imenu-multi` | full |
| `M-s d` | `consult-find` | full (needs `find`) |
| `M-s c` | `consult-locate` | full (needs `locate`; un-bundleable) |
| `M-s g` | `consult-grep` | full (needs `grep`) |
| `M-s G` | `consult-git-grep` | full (needs `git`) |
| `M-s r` | `consult-ripgrep` | **base** (needs `rg`) |
| `M-s l` | `consult-line` | **base** |
| `M-s L` | `consult-line-multi` | full |
| `M-s k` | `consult-keep-lines` | full |
| `M-s u` | `consult-focus-lines` | full |
| `M-s e` | `consult-isearch-history` | full |

### `bindLocal` — `isearch-mode-map`

| key | command | tier |
|-----|---------|------|
| `M-e` | `consult-isearch-history` | full |
| `M-s e` | `consult-isearch-history` | full |
| `M-s l` | `consult-line` | **base** |
| `M-s L` | `consult-line-multi` | full |

### `bindLocal` — `minibuffer-local-map`

| key | command | tier |
|-----|---------|------|
| `M-s` | `consult-history` | full |
| `M-r` | `consult-history` | full |
