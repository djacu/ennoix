# ennoix architecture design

Status: draft for review · Date: 2026-06-20 · Companion: see
`2026-06-07-emacs-primer.md` for the emacs/nix background this assumes.

This document specifies the **architecture**. It backs a *sequence* of
implementation plans, not one (see §11); the first plan is a Phase-0
vertical slice. Fine-grained implementation detail (exact option names,
the full serializer) is settled in that plan, not here.

## 1. Vision and scope

**ennoix is nixvim's UX, for emacs.** Per-plugin Nix modules that each
encode a *working, community-recommended default configuration*, so that

```nix
ennoix.plugins.vertico.enable = true;
```

yields a loaded **and activated** plugin — not a bare `(require 'vertico)`
that does nothing. Everything is configurable in the Nix expression
language, and every curated default is overridable. ennoix is usable as a
standalone runnable emacs (`nix run`) and as a home-manager module.

The product is **the curated catalog**. The generation engine is largely
solved prior art (rycee); the differentiator and the bulk of the ongoing
work is hand-authoring correct, opinionated per-plugin defaults. The
catalog grows in phases (§9).

## 2. Why this is not redundant (prior art)

All claims verified against fresh clones.

- **emacs-overlay** is a *packaging* overlay only — a repo-wide grep finds
  no `mkOption`/`nixosModule`/`homeManagerModule`. It provides emacs
  binaries, daily archives, and helpers that *parse hand-written elisp* to
  discover packages. **No module system, no config generation.** ennoix
  reuses its binaries/packages; it does not compete.
- **rycee's `programs.emacs.init`** (NUR) *is* a Nix→elisp use-package
  compiler (`usePackageType` submodule) — the closest prior art and the
  emitter to mine — but it ships the *schema* with **no curated default
  values** (you still write each package's config). It is also
  home-manager-only (no standalone) and lives in NUR, not upstream.
  (Note: both upstream `programs.emacs` and rycee actually bake config
  into the package via a `trivialBuild` `default.el`/`hm-init`; rycee
  additionally writes thin `~/.emacs.d/{early-init,init}.el` shims via
  `home.file` for the early-init split.)
- **nixvim** is the architectural model: per-plugin modules over a
  host-agnostic module-eval core, delivered to standalone/HM/NixOS. We
  copy the *shape* but not flake-parts (§4.3).

The genuine differentiators: **curated working defaults + standalone
delivery + fail-loud package resolution**, none of which the prior art
combines.

## 3. The core problem the design must solve

Neovim has a universal activation convention — `require('x').setup({})` —
so a nixvim plugin module is mostly a typed schema and "enable → works" is
nearly free. **Emacs has no such convention.** Each package is activated
differently (a global minor mode, a per-buffer hook, an autoloaded
command + keybind, a pre-load variable, …) and that knowledge is not
machine-derivable.

So each ennoix catalog module must **hand-encode that package's
activation and recommended configuration**, expressed through
`use-package` keywords, with the curated values as the module's option
*defaults*. This per-plugin authoring is the central cost and value.

## 4. Architecture

### 4.1 Two substrates

| Layer | Substrate | Why |
|---|---|---|
| **Catalog** (typed per-plugin config, curated overridable defaults, conflict assertions) | NixOS module system (`lib.evalModules`) | Only it provides option types, `mkDefault`/priority resolution, `mkIf`, and auto-merging `assertions`. |
| **Package set** (the elisp derivations) | reused `emacsPackagesFor` scope + an ennoix overlay (`overrideScope`) | The package set already *is* a scope; extending it with `overrideScope` is the canonical idiom. |

The package set is extended the canonical way — `overrideScope` on the
`emacsPackagesFor` scope (the same fixed-point-scope pattern as
`pythonPackagesExtensions`, but applied *per-scope* since emacs has no
global extensions list; §5.3). That is the right tool for
*adding/overriding derivations* but **not** for the typed catalog:
verified empirically, `lib.mkDefault "x"` is inert data
(`{ _type="override"; priority=1000; content="x"; }`) that only
`evalModules` interprets — a `//`-merged scope cannot express overridable
curated defaults. Hence the split.

### 4.2 The eval core

A single host-agnostic core (nixvim's runnable-package builder has zero
references to `home.`/`xdg.`/`programs.`/`environment.`, i.e. it is
provably host-independent):

```nix
# illustrative
evalEnnoix = { pkgs ? null, system ? null, modules ? [ ] }:
  assert (pkgs != null || system != null);   # standalone needs one
  lib.evalModules {
    modules = baseModules ++ modules ++ [ (nixpkgsModule { inherit pkgs system; }) ];
    specialArgs = { inherit lib; };
  };
```

It produces several `build.*` outputs (§6):

- `build.emacsWithPackages` — emacs with the plugin packages on the
  load-path, **no config baked**.
- `build.initText` / `build.earlyInitText` — the generated config text.
- `build.package` — `build.emacsWithPackages` with the config baked as a
  `default.el`, for targets that can't write per-user files.
- `build.homeModule` / `build.nixosModule` — the in-core deferred adapters.

**Invariants** (the verified source of nixvim's multi-target
correctness):

1. **`pkgs` resolved *inside* the eval** via a `nixpkgs.pkgs`/`hostPlatform`
   option (standalone wires `system → nixpkgs.hostPlatform`; host adapters
   inherit the host `pkgs.stdenv.hostPlatform`). One `pkgs`/`lib` source of
   truth; cannot drift.
1. **Host adapters emitted as in-core `build.*Module` deferred modules**,
   so assertions/warnings propagate uniformly and delivery wiring is
   additive.

**Host-adapter mechanism — use `submoduleWith`, not `valueMeta`.** The
HM/NixOS adapters declare `programs.ennoix` (or the NixOS equivalent) as
an option whose **type is `lib.types.submoduleWith { modules = baseModules; … }`**. The host's own module system then evaluates ennoix's
modules merged with the user's settings, so `config.programs.ennoix` *is*
the evaluated ennoix config and `config.programs.ennoix.build.package` is
read directly — no extraction step. The host `pkgs` is threaded in via a
small module (`{ nixpkgs.pkgs = pkgs; }`) satisfying invariant 1.

This is deliberately **not** nixvim's approach. nixvim borrows the
submodule type from a separate base eval and reaches into
`options.programs.nixvim.valueMeta.configuration` to extract the merged
sub-config — which requires nixpkgs lib **≥ 25.11** (the `valueMeta`
feature). `submoduleWith` needs no such extraction (the evaluated config
is a plain attribute, supported in lib for years), so ennoix takes **no
hard lib floor**. The cost is minor: the adapter restates `modules = baseModules` (a small duplication with the standalone path) and threads
`pkgs` explicitly. `submoduleWith` is a standard, widely-used nixpkgs
pattern; its exact wiring for ennoix (pkgs threading, `build.package`
exposure, assertion propagation) is the trickiest **not-yet-built** piece
(§10) but carries no version dependency. (`valueMeta`/`extendModules`
remains a fallback if single-source-of-truth type sharing later proves
worth the floor.)

### 4.3 Delivery — hand-wired flake outputs (no flake-parts)

flake-parts is **not used** (project constraint). Verified: nixvim's
multi-target reuse is pure `lib` (`evalModules` + `extendModules` +
`importApply`); flake-parts is only output-shaping. We hand-wire outputs
in `flake.nix`, matching this repo's per-directory style. A small
`genAttrs`-over-systems helper recovers per-system `packages`/`checks`.

**Public lib API (frozen names):**

| name | signature | returns |
|---|---|---|
| `evalEnnoix` | `{ pkgs ? null, system ? null, modules ? [] }` | the full `evalModules` result (`config`, `options`, `extendModules`) |
| `makeEnnoix` | `{ pkgs ? null, system ? null, modules ? [] }` | `config.build.package` (the runnable emacs) |
| `makeEnnoixWithModule` | `{ pkgs/system, module }` | `config.build.package` from a single user module |

These live under the repo's existing **`library`** flake output (built
via `makeExtensible`), not a new `lib` output — match repo convention.

```nix
# illustrative flake outputs
packages.<system>.default  = makeEnnoix { inherit system; modules = [ … ]; }   # nix run
homeManagerModules.default = (evalEnnoix { … }).config.build.homeModule
# nixosModules.default     = …build.nixosModule   # slot designed; NOT shipped in v1 (§6, §8)
```

## 5. Plugin module design

### 5.1 Schema and the authoring contract

Each plugin is its own module under a `by-name/<plugin>` layout. Its
options are **modeled on rycee's `usePackageType`** keyword set — `enable`,
`init`, `config`, `hook`, `bind`, `mode`, `custom`, `after`, `defer`,
`demand`, `command` (rycee's singular name), `extraConfig` — a curated
subset (rycee has more: `bindLocal`, `diminish`, `chords`, …; ennoix
adopts what it needs). Generation emits one `use-package` form per enabled
plugin.

Each module also declares:

- **its package binding** — what derivation backs the plugin (an
  `epkgs`-selector defaulting to `epkgs.<name>`), or a **built-in marker**
  for packages shipped with emacs (`savehist`, `which-key` ≥30,
  `modus-themes` ≥28, `electric-pair`) that have **no derivation**;
- **a `runtimePackages` list** for non-elisp binaries (§5.3);
- its contribution to generation, gated by `mkIf cfg.enable`.

Two worked examples (the catalog template) — *illustrative*:

```nix
# by-name/vertico/default.nix — an archive package
{ ennoix.plugins.vertico = {
    package = mkOption { default = epkgs: epkgs.vertico; … };
    init    = mkOption { default = "(vertico-mode 1)"; … };   # the curated activation
  };
}
# by-name/savehist/default.nix — a built-in (no derivation)
{ ennoix.plugins.savehist = {
    builtIn = true;                                           # no epkgs lookup
    init    = mkOption { default = "(savehist-mode 1)"; … };
  };
}
```

### 5.2 Curated defaults, override, and profiles

Curated values are set as the option **`default` attribute**. Verified
(`lib/modules.nix`, empirically):

- the `default` attribute is applied at `mkOptionDefault` priority (1500),
- a `default` is **dropped entirely** once the user defines the option, so
  a user override **replaces** it — *including `listOf`/`lines` keywords*
  (`default = ["a"]`, user `["b"]` → `["b"]`, not concatenated). This is
  the fix for rycee's bug, where curated values set as plain `config`
  definitions (priority 100) on list options **concatenate** with the
  user's value.

Rules: set curated values via the option **`default`** attribute (no
wrapper needed); if a default must come from a `config` block, use
`mkOptionDefault` (not `mkDefault`); **never** plain `config` definitions
for curated values; emit the user's freeform `extraConfig` **last** (§7).

**Profiles are a third definer and need a priority discipline** (verified
with `nix-instantiate`). A profile cannot use the `default` attribute (one
per option). A profile setting a list keyword via plain `config`
re-introduces the concat bug; via `mkOptionDefault` it ties the plugin
default at 1500. **Profiles must set keywords at `mkDefault` (1000)** so a
user's plain `config` (100) still wins and the plugin's `default` (1500) is
overridden. For list keywords, profile+user **replace** (the user value
wins outright), they do not merge. (Profiles remain a deferred §8 feature,
but the discipline is fixed now so it is additive.)

### 5.3 Package resolution, the ennoix overlay, and runtime binaries

**Elisp package set.** The catalog evaluates against
`emacsPackagesFor cfg.package` extended with a single composed
`overrideScope`: **ennoix's overlay first, then the user's** (so the
overlay is applied exactly once). ennoix's overlay (a new emacs slot in
`overlays/`) provides any catalog package missing upstream (added via
`overrideScope`, e.g. a `fetchurl` + `trivialBuild`, as rycee does for
`cue-mode`). v1 source is **nixpkgs `emacsPackages` only**; `emacs-overlay`
is *not* a flake input in v1 (it can be added later for fresher archives /
`emacs-git`). The user extends the set via a module option
(`ennoix.package-overlay`, an overlay-typed `overrideScope` function).

**Catalog packages are guaranteed present** (nixpkgs, or ennoix's overlay)
— never silently dropped. **User-referenced packages absent** from the
final scope **fail loudly**: package references are accepted only on a
defined surface (the per-plugin `package` selector and a user
`extraPackages`), looked up against the final extended scope, and a miss
is surfaced via `config.assertions` with a clear message. **Every delivery
target must read `config.assertions`** (the `build.package` `apply` does,
so a failed assertion throws when the package is realized) so it cannot be
silently skipped. Catalog refs are guaranteed and so are not asserted;
only *user* refs can fail.

**Runtime (non-elisp) binaries.** The emacs wrapper only puts emacs's own
`bin` on `exec-path`; it does **not** add arbitrary binaries, and both
`nix run` and the `services.emacs` daemon otherwise fall back to ambient
`$PATH`. So a plugin needing a binary (consult→`ripgrep` in Phase 1,
envrc→`direnv`, treesit tooling) declares it:

```nix
ennoix.plugins.consult.runtimePackages = [ pkgs.ripgrep ];
```

`build.package` is then wrapped (`makeWrapper --prefix PATH`) so the
collected `runtimePackages` are on `PATH`/`exec-path` **purely**,
independent of `$HOME`/login shell, and identically across all delivery
targets.

### 5.4 use-package under nix (autoloads — corrected)

`use-package` is the generation target (built-in since 29.1; we target
emacs 30.2 as nixpkgs ships, so it is always present). Emit **no
`:ensure`** (`use-package-always-ensure nil`); the package set is owned
structurally by nix.

**Autoloads (verified by spike, corrects an earlier claim):** keeping
`package.el` *enabled* is required. The wrapper places each package's
`elpa` dir on `package-directory-list`, and `package-activate-all` — which
runs at startup because `package-enable-at-startup` is `t` — loads each
package's `*-autoloads.el` (spike: `package-activated-list` held the
enabled package; its mode was autoloaded). This is **automatic**; there is
**no `package-quickstart` step** and nothing for ennoix to arrange.
**Do not disable `package.el`** — that skips activation and deferred
packages silently never load.

### 5.5 Generation

The generation pipeline (concrete option names finalized in the Phase-0
plan, §11):

1. **Collect** enabled plugins (`mkIf cfg.enable` gates each contribution).
1. **Emit** one `use-package` form per plugin from its keyword values, by
   **adapting rycee's `.assembly` emitter** (`emacs-init.nix:263-340`,
   verified safe to port; do *not* port rycee's defaults convention).
1. **Assemble** into ordered buckets — `prelude` → per-plugin forms (in a
   deterministic order, e.g. by plugin name; cross-package *load* order is
   handled by `:after`/hooks, not text order — §7) → `postlude` →
   **user freeform last**. Buckets are `lines`-typed options.
1. **Serialize** keyword values: `config`/`init`/`extraConfig` are literal
   elisp strings; structured keywords (`hook`/`bind`/`mode`/`custom`) are
   Nix data serialized to elisp by an emitter adapted from rycee.
1. **Expose** the assembled text as `build.initText` (and a small
   `build.earlyInitText` from an `early-init` bucket / per-plugin
   `earlyInit` contributions). Standalone/NixOS **bake** `build.initText`
   as a `default.el` `trivialBuild` into `build.package`; home-manager
   **writes** both texts to `~/.config/emacs/{init,early-init}.el` (§6).

## 6. Config injection and delivery (verified by spike)

A spike built a real wrapped emacs (30.2 + `vertico` + a baked
`default.el`) and ran real startup with an empty `$HOME`: the baked config
loaded, its curated `(vertico-mode 1)` ran (mode active), and the only
thing written to `$HOME` was a native-comp `eln-cache` — **no config
files**.

`build.emacsWithPackages` = `emacsWithPackages` over
`emacsPackagesFor cfg.package |> overrideScope (ennoix-then-user)`,
`makeWrapper`-wrapped to add `runtimePackages` to `PATH` (§5.3). The two
delivery shapes differ in *where the config goes*:

- **Standalone:** `nix run` **`build.package`** — `build.emacsWithPackages`
  with the config baked as a `default.el` `trivialBuild`. Pure and
  `$HOME`-independent. (The spike verified this loads and runs.) `default.el`
  loads *after* init, so standalone has **no early-init**.
- **Home-manager (Strategy B — write the files):** ennoix ships its own
  `programs.ennoix` module (`programs.emacs` doesn't map cleanly — its only
  config sink is `extraConfig` → a single `default.el`). The module
  installs **`build.emacsWithPackages`** (the *bare* package, so the config
  is not also baked) into `home.packages`, writes `build.earlyInitText` and
  `build.initText` to `~/.config/emacs/early-init.el` and `init.el` via
  `xdg.configFile`, and sets `services.emacs.package = build.emacsWithPackages`
  (the user daemon reads those files). This is rycee's approach and the
  reason for it: owning `init.el`/`early-init.el` is the **only** way to get
  early-init (frame-flicker/pre-load), and HM is where that matters. ennoix
  owns those two files; the user configures via Nix, not by hand-editing
  them (§7).
- **NixOS:** system-wide, no per-user `~/.config`, so it uses the **baked
  `build.package`** like standalone. Stock `services.emacs.package` is
  settable (`mkPackageOption`, verified), so
  `services.emacs.package = build.package` gives a configured system daemon
  with **no ennoix NixOS module required**; the in-core `build.nixosModule`
  slot is designed but **not shipped/tested in v1**. (NixOS therefore also
  has no early-init in v1.)

## 7. Override and load-order semantics

Two override channels, kept distinct:

- **In Nix (the supported channel):** override a curated option default
  (replaces, even lists — §5.2), or use the freeform escape hatch. The
  user never manages file order — ennoix controls it and emits freeform
  **last** so the user's elisp wins. From the user's side this is
  file-order-independent.
- **A separate hand-written `init.el` (not supported):** load order is
  `site-start.el` → user `init.el` → `default.el` (verified:
  `startup.el:1520` site-start before the regular init; `:1044`/`:1112-1116`
  default.el after init). On **standalone/NixOS** ennoix injects via
  `default.el` (loads last), which would override a user's own init.el; on
  **home-manager** ennoix *owns* `~/.config/emacs/init.el` directly (no
  `default.el` indirection). Either way we do not support a competing
  hand-written `init.el` — raw elisp goes in ennoix's freeform option.

## 8. Decisions

| Decision | Resolution |
|---|---|
| Catalog substrate | **Module system** (`evalModules`); scope is for the package set only. |
| Delivery | **Hand-wired** flake outputs; no flake-parts; public API under the `library` output. |
| Home-manager | **Own `programs.ennoix`** module; **Strategy B** — install `build.emacsWithPackages` + write `build.earlyInitText`/`build.initText` to `~/.config/emacs/{early-init,init}.el` via `xdg.configFile` + set `services.emacs.package`. Gets early-init. |
| NixOS | **Stock `services.emacs.package`**; in-core slot designed, shipping deferred. |
| Missing package | **Fail loudly** via `config.assertions` (read by `build.package`); ennoix overlay backstops catalog packages; only user refs can fail. |
| Curated defaults | Option **`default`** attribute (`mkOptionDefault`-priority; replaces, even lists); `mkOptionDefault` if set from `config`; **profiles set keywords at `mkDefault`**. |
| Config injection | **Standalone/NixOS:** config baked as `default.el` `trivialBuild` in `build.package` (spike-verified). **Home-manager:** config text written to `~/.config/emacs/{early-init,init}.el` (Strategy B). |
| Runtime binaries | Per-plugin **`runtimePackages`**, baked onto `PATH` via `makeWrapper --prefix` on `build.package`. |
| Autoloads / package.el | **Keep `package.el` enabled** (`package-enable-at-startup t`); autoloads load via `package-activate-all` + `package-directory-list`; no `package-quickstart`; no `:ensure`. |
| Generation | Adapt rycee's `.assembly` emitter; ordered buckets (`prelude`/per-plugin/`postlude`/freeform-last); structured keywords serialized to elisp. |
| `custom-file` | v1: set `custom-file` to a writable `$HOME` path **or** declare interactive `customize` unsupported; generator emits `:custom`/`setopt` (not `setq`). |
| Conflicts | Best-effort `config.assertions` for known mutually-exclusive sets (first: vertico/ivy/helm); otherwise the user's responsibility. |
| Host-adapter mechanism | **`submoduleWith`** (host module system evaluates the ennoix submodule; `config.programs.ennoix.build.package` read directly) — **no hard nixpkgs lib floor**. `valueMeta`/`extendModules` is the fallback (would require lib ≥ 25.11). |
| Build gate | Adopt rycee's `emacs --batch` load check as a flake `check` (the "feature works, not just typechecks" gate). |

### Deferred / out of scope for v1

- early-init **on standalone/NixOS only** (those bake `default.el`, which
  loads *after* package activation and init, so no curated default can
  affect *pre-load* behavior — frame parameters, GC tuning). **Home-manager
  gets early-init** (Strategy B writes `early-init.el`); standalone/NixOS
  early-init is deferred. (Correctness is unaffected everywhere:
  `package.el` activation with an empty user dir is harmless — verified.)
- Shipping/testing the NixOS module (slot designed).
- Profiles — 1–2 curated Doom-flavored bundles (priority discipline fixed
  in §5.2).
- The heavy opt-in tier (org-roam/sqlite, vterm/libvterm, forge, treemacs,
  dap, …).
- Keybinding stance (evil/meow/vanilla): **independent per-plugin enables,
  no cross-cutting enum** in v1; revisit if a stance option is wanted.
- `leaf`, org-babel literate config — not load-bearing.
- Pre-native-compiling the generated `default.el` (a non-blocking build
  optimization; default: do not, in v1).

## 9. Catalog roadmap (emacs 30.2)

Each phase is a shippable milestone; low-complexity / no-external-dep /
available-in-nixpkgs packages first. (External binaries noted; they use
the `runtimePackages` channel, §5.3.)

- **Phase 0 — MVP:** `vertico`, `orderless`, `marginalia`, `savehist`
  (built-in), `which-key` (built-in ≥30), `modus-themes` (built-in ≥28),
  `magit` (+ `git`). → modern minibuffer + theme + git on launch.
- **Phase 1 — minibuffer stack:** `consult`, `embark`, `embark-consult`,
  `wgrep` (+ `ripgrep` runtime binary — first `runtimePackages` use).
- **Phase 2 — editing + keybinding:** `electric-pair`/`subword` (built-in),
  `avy`, `vundo`, + a keybinding path (evil+evil-collection / meow /
  vanilla, independent enables).
- **Phase 3 — in-buffer completion + polish + org:** `corfu`, `cape`,
  `kind-icon`, `yasnippet`, `nerd-icons`(+completion, + `nerd-fonts` font),
  `doom-modeline`, `rainbow-delimiters`, `hl-todo`, `diredfl`, `org`,
  `org-modern`, `denote`.
- **Phase 4 — IDE:** built-in `eglot`/`eldoc`/`flymake`/`project`/`treesit`
  - `treesit-grammars.with-grammars`, per-language servers (runtime
    binaries), `envrc` (+ `direnv` runtime binary), `diff-hl`.

Shipped defaults (each overridable): vertico stack, modus themes,
nerd-icons, flymake, built-in project, corfu — alternatives (ivy/helm,
doom-themes, flycheck, projectile, company) supported but not default.

## 10. Risks and what is verified vs. not

Verified (source or spike): substrate choice; host-agnostic single core;
`default.el` injection + `$HOME` purity; curated-default override
(including lists); autoload mechanism (`package-activate-all` +
`package-directory-list`, package.el must stay on); stock
`services.emacs.package`; load order; the runtime-binary gap; profile
priority discipline.

Not yet built (engineering, not porting): the in-core host-adapter
plumbing (`submoduleWith`-based: host `pkgs` threading and assertion
propagation) — the trickiest part, though it carries no version
dependency (choosing the `valueMeta`/`extendModules` fallback instead
would require nixpkgs lib ≥ 25.11); the generation engine; the catalog.

Risks:

- **Catalog authoring is the dominant, unbounded effort** and is what
  differentiates ennoix; a thin catalog leaves it close to rycee.
- Cross-plugin conflict assertions are only as good as we author them.
- nix-doom-emacs / -unstraightened occupy an adjacent "curated emacs via
  nix" niche (different angle) — worth watching, not yet surveyed.

## 11. Implementation sequencing

v1 is too large for one plan; it decomposes into a sequence, each a
shippable milestone:

- **Plan 1 — Phase-0 vertical slice (prove `enable → works` end-to-end):**
  the eval core (one invariant set, standalone only), the generation
  pipeline (§5.5), `default.el` injection, the `makeEnnoix` standalone
  flake output (`nix run`), the ennoix overlay slot + fail-loud assertion,
  and the **7 Phase-0 plugins**. Defer HM/NixOS adapters, runtime binaries,
  conflict assertions, profiles. Gate: the `emacs --batch` load check + a
  manual `nix run` smoke test.
- **Plan 2 — delivery + extension:** `programs.ennoix` HM module
  (Strategy B — write `~/.config/emacs/{early-init,init}.el`, install
  `build.emacsWithPackages`) + in-core `build.homeModule`/`build.nixosModule`
  plumbing, the `runtimePackages` channel, the user `package-overlay`
  extension point.
- **Plan 3+ — catalog phases 1–4** as additive milestones (Phase 1
  introduces `runtimePackages` via `ripgrep`).

This spec backs Plan 1 first; we write that plan next.
