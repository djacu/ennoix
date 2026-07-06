# ennoix re-architecture design

Status: replaces the package-set/eval/option-namespace parts of `2026-06-20-ennoix-architecture-design.md` (the emacs mechanics in that document — default.el injection, autoloads, use-package targeting — remain valid and are referenced, not repeated).
Every decision below was settled in dialogue and verified by running code before being recorded; spikes live in the session scratchpad and the findings are summarized inline.
Revised after a three-lens adversarial review (fidelity / technical refutation / migration-completeness); the technical lens independently re-verified every load-bearing claim.

## 1. Motivation — what Phase 0 got structurally wrong

Phase 0 works (merged, tested), but its wiring violates the repository's layering rules and re-implements module-system behavior:

1. **The `library` flake output was misused.**
   `library` is for repository/flake-level plumbing only (`defaultSystems`, `getDirectoryNames`).
   Phase 0 put `evalEnnoix` there, and the `ennoix` overlay reached *out* of the package set to `inputs.self.library.ennoix.evalEnnoix` — an overlay depending on a flake output.
   Functionality belongs *inside* the package set.
1. **`library/ennoix.nix` re-implemented the module system.**
   It hand-rolled assertion filtering and a `throw` that `evalModules` + natural evaluation failure already provide.
   It also imported nixpkgs itself (`resolvePkgs`) and manually composed the emacs-packages overlay — both artifacts of living outside the package set.
1. **Per-plugin declared options can't express freeform.**
   Phase 0's `mkPlugin` declared `options.plugins.<name>.*` per plugin; a package outside the 7-module catalog could not be configured at all.
   rycee's `usePackageType` shape (one `attrsOf` submodule option) provides freeform-anything plus a catalog, with less machinery.
1. **String-typed package references were an artifact.**
   `package : nullOr str` existed to feed a `hasAttr`-based assertions layer.
   With that layer gone, name-indirection serves nothing; hardcoded derivations (the `mkPackageOption` idiom) are simpler and strictly more capable.

## 2. Layering

- **`library/`** returns to flake plumbing only (`paths.nix`, `systems.nix`).
  `library/ennoix.nix` is deleted.

- **All ennoix functionality lives in the package set**, spread across the repo's overlay slots, all composed into `overlays.default` (there is no bespoke `ennoix` overlay):

  - **functions with dependencies are ordinary `callPackage`'d members of the `top-level` slot** — `ennoixEval` lives at `overlays/top-level/ennoixEval/package.nix` (`{ lib, pkgs }: …`).
    Rationale: `callPackage` is the dependency-injection mechanism that comes with an override seam — verified: `pkgs.ennoixEval.override { pkgs = …; }` swaps the injected dependencies, and the `makeOverridable` functor result remains callable (`ennoixEval [ … ]`).
    Hand-applying the fixpoint (a `final: <value>` file contract) was rejected as an antipattern: it injects the same dependencies with no way to override them.
    (An import-only `top-level-functions` slot — dir name = attr, no arguments supplied — remains the recorded convention for argument-*free* functions; ennoix has none, so the slot is not created.);
  - **packages** ride the existing `top-level` slot (`overlays/top-level/<name>/package.nix`, `packagesFromDirectoryRecursive`);
  - **test derivations** ride a **new `tests` slot** (`overlays/tests/<name>/package.nix`, same directory convention) so `hydra-jobs/tests.nix` collects purely by path — the same jobset↔directory pairing as `packages.nix` ↔ `top-level`; the existing `verification` slot keeps the `verify-hydra-jobset` tool, in no jobset, as today (§8);
  - a small **`emacs-packages` overlay** applies the `emacsPackagesFor` override below.

  Downstream consumers use **`overlays.default`** — it is the only complete surface; individual slots stay exported per the existing `inherit` pattern (`overlays.ennoix` ceases to exist).

- **Flat top-level, no scope, no nested attrset.**
  Decision record: a `makeScope` was investigated in depth (semantics from `lib/customisation.nix`, empirical tests, ecosystem survey).
  Tooling is a wash (nix-eval-jobs ignores scope machinery; flake check indifferent in `legacyPackages`), but a scope adds a second, non-commuting override mechanism (`//`-merges silently fail to rewire and are destroyed by later `overrideScope`), member-shadowing of pkgs attrs, and injected function attrs — while its unique power (ad-hoc `overrideScope`) targets machinery users customize through the *module system* anyway.
  nixpkgs' own direction for new families is flat (RFC-140 by-name; `gnome/default.nix`: "new packages should go to top-level").
  **Re-open criterion:** adopt a scope only if ennoix becomes a genuinely interdependent package family whose members users swap wholesale.

- **Naming: `ennoix-` prefix** for collision-safety and tab-completion discovery.
  Packages hyphenated (`ennoix-emacs`, `ennoix-tests-eval`); functions family-first camelCase (**`ennoixEval`** — precedent: `nixosTest`, `nixosOptionsDoc`).
  `makeEnnoix` is dropped; the package projection is `(ennoixEval [ … ]).build.package` (§3).

- **The emacs package scope extension is baked into the package set once**: the `emacs-packages` overlay wraps the **function**, applying a scope overlay that collects `overlays/emacs-packages/<name>/package.nix` — the `python-packages` double-nested-overlay pattern applied to the emacs scope:

  ```nix
  emacsPackagesFor = emacs:
    (prev.emacsPackagesFor emacs).overrideScope (
      eself: _esuper:
      packagesFromDirectoryRecursive {
        inherit (eself) callPackage newScope;
        directory = ./emacs-packages;
      }
    );
  ```

  Verified: an empty slot (`.gitkeep` only, the repo convention) yields `{ }` harmlessly; a `<name>/package.nix` is `callPackage`'d against the *scope* with pkgs fallback (spike: `trivialBuild` resolved from the scope, `writeText` from pkgs) and lands in `pkgs.emacsPackages` and `emacs.pkgs` alike; members gain per-member `.override`, consistent with the callPackage rule above.
  Adding a catalog-gap package = dropping in a directory; no overlay code is edited.
  Not expressible in this form: *overriding an existing* scope member (`foo/package.nix` taking `{ foo }` would recurse) — if an emacs-scope fix is ever needed, compose an additional fixes-style scope overlay at that point.
  The extension mechanism IS `overrideScope`; wrapping the function (rather than overriding the `emacsPackages` attr) is the attach point that covers **all** scope paths — verified: an attr-level `prev.emacsPackages.overrideScope` extends only `pkgs.emacsPackages`, leaving `pkgs.emacs.pkgs`, direct `emacsPackagesFor` calls, and **variant-base scopes** (`emacsPackagesFor pkgs.emacs-nox`) unextended, which would break the §3 base-emacs-variant story; the function wrap covers all four (and is exactly emacs-overlay's own mechanism, `overlays/package.nix:3-4`).
  Verified: the function wrap **propagates into top-level `pkgs.emacsPackages`** through the fixpoint (`pkgs.emacsPackages` is derived from `emacs.pkgs`, which `emacsPackagesFor` produces), and `pkgs.emacsPackages` is derivation-identical to `emacsPackagesFor pkgs.emacs` (and carries `withPackages` / `trivialBuild`).
  Consequently ennoix has **no separate emacs-package-set value** ("epkgs"), and **ennoix itself never calls `emacsPackagesFor`** — the overlay decorates it once; every consumer reads `pkgs.emacsPackages`.
  Users extend the scope with their own overlay the same way (their wrap composes on top via `prev`).

### Resulting repository layout

New/rewritten files annotated; deletions listed in §9; everything else is unchanged.

`modules/` is the shared module-system substance, deliberately at the repo root rather than inside a consumer.
Current consumers: `ennoixEval` (via `eval.nix`, transitively everything but the test suite) and the tests slot (`ennoix-tests-eval` imports `eval-tests.nix`).
Planned consumer: the home-manager/NixOS host adapters — their `submoduleWith` design (old spec §4.2, still valid) embeds the raw `baseModules` list directly and structurally cannot go through `ennoixEval` (they need modules, not an evaluated config), so `baseModules` gains an export point in that plan.

```
.
├── flake.nix                                  # rewritten: packages.default → ennoix-emacs
├── checks/default.nix                         # unchanged (formatting check only)
├── formatter/ · formatterModule/              # unchanged
├── hydra-jobs/
│   ├── common.nix                             # unchanged
│   ├── packages.nix                           # unchanged (collects overlays/top-level → builds ennoix-emacs*)
│   └── tests.nix                              # rewritten: collects overlays/tests by directory name (§8)
├── legacyPackages/default.nix                 # unchanged (applies overlays.default)
├── library/
│   ├── default.nix                            # rewritten: ennoix export removed (flake plumbing only)
│   ├── paths.nix                              # unchanged
│   └── systems.nix                            # unchanged
├── modules/
│   ├── eval.nix                               # new: ennoixEval body — baseModules + catalog collector (§3, §5)
│   ├── use-package.nix                        # new: the flat usePackage option (§4)
│   ├── generation.nix                         # rewritten: concatenates per-entry assemblies (§6)
│   ├── build.nix                              # rewritten: withPackages + runtimePackages wrapper → build.package (§6)
│   ├── eval-tests.nix                         # rewritten: emitter equality + override-replacement (§8)
│   ├── lib/
│   │   └── use-package-type.nix               # new: the shared type (§4)
│   └── catalog/                               # new: one dir per entry; dir name == usePackage key (§5)
│       ├── magit/module.nix
│       ├── marginalia/module.nix
│       ├── modus-themes/module.nix
│       ├── orderless/module.nix
│       ├── savehist/module.nix
│       ├── vertico/module.nix
│       └── which-key/module.nix
├── nixosConfigurations/ · nixosModules/       # unchanged
└── overlays/
    ├── default.nix                            # rewritten: composes the slots below; the ennoix overlay is deleted
    ├── emacs-packages/.gitkeep                # catalog-gap slot: <name>/package.nix into the emacs scope (empty here)
    ├── fixes/ · python-packages/              # unchanged
    ├── tests/                                 # NEW SLOT: test derivations; source of hydra-jobs/tests.nix
    │   ├── ennoix-tests-eval/package.nix      # new: realizes modules/eval-tests.nix (§8)
    │   ├── ennoix-tests-load/package.nix      # new: --batch gate for ennoix-emacs (§8)
    │   └── ennoix-tests-load-full/package.nix # new: --batch gate for ennoix-emacs-full (§8)
    ├── top-level/                             # existing slot (packagesFromDirectoryRecursive / callPackage)
    │   ├── ennoixEval/package.nix             # new: the eval function, callPackage'd → .override (§3)
    │   ├── ennoix-emacs/package.nix           # new: flagship starter (§7)
    │   └── ennoix-emacs-full/package.nix      # new: whole catalog, build coverage (§7)
    └── verification/                          # unchanged: repo CI tooling, in no jobset
        └── verify-hydra-jobset/package.nix
```

## 3. `ennoixEval`

```nix
# overlays/top-level/ennoixEval/package.nix — callPackage'd by the
# top-level slot; .override { pkgs = …; lib = …; } comes for free.
{ lib, pkgs }:
import ../../../modules/eval.nix { inherit lib pkgs; }
```

```nix
# modules/eval.nix
{ lib, pkgs }:
let
  # baseModules is assembled HERE (modules/default.nix is deleted):
  # the usePackage namespace module, generation/build, and the collected
  # catalog (§5 collector, a let-binding in this file).
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

- Signature: **`modules: config`**.
  `callPackage` injects `lib`/`pkgs`; no `resolvePkgs`, no nixpkgs import, no overlay composition.
  `pkgs.ennoixEval` is a `makeOverridable` functor attrset — callable as a function, with `.override` for swapping the injected dependencies (verified).
  The packages hydra jobset maps this non-derivation member to a harmless empty job (release-lib reads `recurseForDerivations or false` and emits no platforms — the same junk-job class nixpkgs itself tolerates).
- **The package projection:** `build.package` (and `build.initText`) survive from Phase 0 as the output options; `build.package` holds the final, runtimePackages-wrapped emacs (§6).
  A user's runnable emacs is **`(pkgs.ennoixEval [ ./my.nix ]).build.package`**.
- **Base emacs is fixed to `pkgs.emacs`** (via `pkgs.emacsPackages`).
  Users pick a variant (pgtk, nox, emacs-git) by overlaying `emacs` in their own nixpkgs — per-eval base-emacs selection from the old design (§5.3/§6 there) is deliberately dropped.
  Re-open if a delivery target ever needs a different base per config.
- **No assertions layer, no wrapper `throw`.**
  A missing package fails at evaluation naturally (verified: `mkPackageOption`'s default throws `"<name> cannot be found in pkgs.emacsPackages"`; a nonexistent attr access errors).
  We do not re-implement or re-test platform behavior.

## 4. The `usePackage` namespace and shared type

One flat option — no category namespaces (survey result: emacs has no canonical plugin taxonomy; the only stable identity is the flat package name; semantic taxonomies churn — nixvim's renames, Doom's module-tree relocation).
Declared in **`modules/use-package.nix`**:

```nix
# modules/use-package.nix
{ lib, pkgs, ... }:
{
  options.usePackage = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submoduleWith {
      modules = [ ./lib/use-package-type.nix ];
      specialArgs = { inherit pkgs; };  # required: verified that neither
      # top-level specialArgs nor _module.args reach submodules (true in
      # bare evalModules AND under a real NixOS eval — submoduleWith spins
      # up a fresh isolated eval; lib/types.nix:1410)
    });
    default = { };
  };
}
```

`modules/lib/use-package-type.nix` — the shared type, adapted from rycee's `usePackageType` (nur-expressions `hm-modules/emacs-init.nix`), one module file usable by any future namespace:

- `enable` — `mkEnableOption`, gates emission and installation.
- `package` — **`lib.mkPackageOption pkgs.emacsPackages name { nullable = true; pkgsText = "pkgs.emacsPackages"; }`** → type `nullOr package`, default the *hardcoded* `pkgs.emacsPackages.<name>` derivation (the `attrsOf` key), `null` = built-in (install nothing).
  Spike-verified: default resolves through `attrsOf`/`submoduleWith`; users may hardcode any derivation (rycee's function-variant capability, first-class); a freeform name missing from the set fails at eval with the friendly message.
- `runtimePackages` — **`listOf package`**, default `[ ]`.
  Non-elisp binaries put on the built emacs's PATH (§6).
  Catalog modules write `{ pkgs, ... }: … runtimePackages = mkCatalogDefault [ pkgs.ripgrep ]`.
- use-package keyword fields — adopted from rycee's field definitions and emitter (`assembly`) for the subset ennoix ships: `init`, `config` (lines), `bind` (structured `attrsOf str`, key = keybinding, value = command, emitted with rycee's quoting/escaping), `custom` (rycee's structured shape, `attrsOf` primitive — a deliberate change from Phase-0's raw-elisp list; no carried config uses it), `hook`, `after`, `mode` (lists), `commands` (**deliberate rename** of rycee's singular `command`, matching the `:commands` keyword and Phase-0 naming), `defer`, `demand`.
  Additional rycee fields (`bindLocal`, `bindKeyMap`, `diminish`, `chords`, `earlyInit`, …) are added to the shared type as need arises.
- `assembly` — internal, read-only: the complete generated `use-package` form for this entry (rycee's design).
  Generation concatenates enabled entries' assemblies; tests assert on exact per-entry attribute paths.

**Freeform is native:** `usePackage.<anything>` is a legal, fully-typed entry whether or not a catalog module exists — `package` defaults by name, all keywords available.
A user's freeform module file has the identical shape to a catalog module and can be PR'd into the catalog unchanged.

## 5. Catalog

```
modules/catalog/
  vertico/module.nix
  orderless/module.nix      # helper files may sit beside module.nix
  magit/module.nix
```

- One directory per package; **the directory name IS the `usePackage` key**, and **the module must be named `module.nix`** (mirrors `overlays/top-level/<name>/package.nix`).
  Helper files (e.g. a large curated `init.el` read via `builtins.readFile`) live beside it.

- **Collector:** `readDir` → directories → import `<dir>/module.nix` (a let-binding in `modules/eval.nix`, §3).
  No strictness code: an entry directory whose module is misnamed fails naturally at import (`path '…/module.nix' does not exist`, naming the entry).
  Verified.
  Stray files at the root are ignored (accepted).

- **Catalog modules set entry defaults at `mkCatalogDefault` = `mkOverride 1400`** (received via `specialArgs`):

  ```nix
  # modules/catalog/vertico/module.nix
  { mkCatalogDefault, ... }:
  { usePackage.vertico.init = mkCatalogDefault "(vertico-mode 1)"; }
  ```

  Priority ladder (all transitions spike-verified): `mkForce (50) < user plain (100) < user mkDefault (1000) <` **`catalog (1400)`** `< type declaration defaults (1500)`.
  `mkOptionDefault` (1500) is NOT usable for the catalog: the shared type's own declaration defaults are injected as definitions at 1500, so a catalog definition there *merges* (lines: stray leading newline) or *hard-conflicts* (scalars: verified with the built-in `package = null` case).
  `mkDefault` (1000) would collide with a user's own `mkDefault`.
  1400 sits cleanly between.
  **Contract:** `mkCatalogDefault` is a catalog-authoring convention only — user modules must not use it (same-priority definitions merge or conflict, per the ladder above); it reaches user modules via `specialArgs` as an accepted implementation artifact.

- **Accepted silent-degradation class** (all verified): (a) an *uncollected* catalog module leaves the entry legal-but-uncurated (freeform: bare `(use-package consult)` emitted; builds and boots); (b) catalog defaults **materialize their entries disabled** — the full catalog appears in `config.usePackage` with `enable = false`, so generation/build filtering on `enable` is load-bearing (§6 does); (c) a typo'd entry key *inside* a `module.nix` silently creates a phantom disabled entry.
  The `module.nix` convention plus natural import failure covers the misnamed-module case; the rest is risk accepted by decision — no integrity test.

## 6. Generation and build

Mechanics carry over from Phase 0 (all previously verified) with the namespace/type swapped.
`modules/generation.nix` and `modules/build.nix` survive as the `build.*` modules (options `build.initText`, `build.package`); generation.nix's central `form` emitter is replaced by the shared type's per-entry `assembly`:

- Per-entry `assembly` (shared type) → concatenated init text — **entries in attribute-name (lexicographic) order, joined with blank lines, Phase-0 behavior; the old design's prelude/postlude/global freeform buckets are dropped (per-entry `init`/`config` is the only elisp channel)** — → wrapped `default.el` (`trivialBuild`, header + `(provide 'default)` — the native-comp requirement) → `pkgs.emacsPackages.withPackages (elispPkgs ++ [ defaultEl ])` where `elispPkgs = map (p: p.package) (filter (p: p.enable && p.package != null) entries)` — **no name resolution; the option values are the derivations.**
- **`runtimePackages`**: collected across enabled entries (`lib.unique`); when non-empty, the `withPackages` output is wrapped — `symlinkJoin` + `wrapProgram` (makeBinaryWrapper) over **every** `bin/*` with `--prefix PATH : ${lib.makeBinPath runtimePkgs}` — and **the wrapped result is what `build.package` holds**.
  Spike-verified (and independently re-verified by the review): in a clean `env -i` the wrapped emacs resolves `(executable-find "rg")` to the store path (emacs derives `exec-path` from PATH); `emacsclient`/`etags` preserved; elisp load-path and native-comp intact through the join.
  When empty, the output is byte-identical to the unwrapped package (Phase-0 parity).
- The `${…}` interpolation hazard for future catalog elisp (issue #2) carries over to the generation site unchanged.

## 7. Package family

`overlays/top-level/<name>/package.nix` — auto-collected into the package set *and* the hydra packages jobset (`getDirectoryNames`):

- **`ennoix-emacs`** — the flagship `nix run` demo: curated starter (initially the Phase-0 seven: vertico, orderless, marginalia, savehist, which-key, modus-themes, magit).
  Flake `packages.<system>.default` points here.
- **`ennoix-emacs-full`** — the entire catalog enabled: build coverage (every catalog package must resolve and build on hydra) and the kitchen-sink demo.
  **Enables are derived structurally** — `getDirectoryNames` over `modules/catalog` mapped to `usePackage.<name>.enable = true` (valid because the directory name IS the entry key, §5) — never hand-listed.
- **`ennoix-emacs-<profile>`** (later, e.g. `-doom`) — a profile is a *module* (importable, tweakable); the package wraps it.

Each `package.nix` is `{ ennoixEval }: (ennoixEval [ ./config.nix ]).build.package` (or an inline module) — `callPackage` hands it `ennoixEval` from the package set; the **`.build.package` projection** is what makes the result a derivation (§3).

## 8. Tests — four tiers, each catching only what cheaper tiers cannot

1. **Eval tests** (`modules/eval-tests.nix`, source of truth next to the modules): **emitter-shape equality** — a handful of entries exercising each keyword emitter, asserted by *string equality* on the per-entry `assembly` attribute path (no `hasInfix`) — **plus one override-replacement test**: a user plain definition replaces a `mkCatalogDefault` value for a list/structured field (exact assembly equality).
   That single test locks *ennoix's own* 1400 catalog layer — the product's replace-not-merge contract, previously locked by `b32f224` — at the exact moment its mechanism changes; it does not test the module system itself.
   Dropped deliberately: per-plugin activation strings (tautological under catalog-as-modules), further priority-layering tests (platform behavior), missing-package tests (natural eval failure), catalog-integrity count (risk accepted, §5).
1. **Build coverage** — building `ennoix-emacs-full` *is* the test; packages jobset, zero new wiring.
1. **`--batch` load gates** — `runCommand` boots each `ennoix-emacs*` package headlessly: Phase-0-parity gate (`package-activate-all` + load `default` + error grep + success marker).
   Runs in the ordinary build sandbox; no VM.
   Known limitation carried from Phase 0 (issue #4): only startup-time errors are caught.
1. **NixOS VM tests** (`testers.runNixOSTest`) — tier adopted, first test deferred until VM-specific surface exists (interactive keybindings, theme rendering, `services.emacs` daemon, HM/NixOS modules).
   Requires a one-time KVM check on the hydra builders.

**Placement and mechanism:** test derivations live at `overlays/tests/<name>/package.nix` — the new `tests` slot (§2), flat in the package set, *not* in the packages jobset.
`ennoix-tests-eval/package.nix` imports `modules/eval-tests.nix` (`lib.runTests`): a non-empty failure list `throw`s at evaluation (a per-attr eval error in the jobset), otherwise the derivation is `runCommand … touch $out` — Phase 0's mechanism, relocated.
`hydra-jobs/tests.nix` **keeps its single-eval-system `recurseIntoAttrs` shape** (no `mapTestOn`) and collects `getAttrs (getDirectoryNames ../overlays/tests) pkgs` — pure path-based collection, the same jobset↔directory idiom as `packages.nix` ↔ `top-level`; no name filter needed because `verify-hydra-jobset` stays in `verification`, in no jobset.

## 9. Migration from Phase 0

**Deleted:** `library/ennoix.nix` (and the `library.ennoix` export), `modules/default.nix` (baseModules assembly moves into `modules/eval.nix`), `modules/lib/mk-plugin.nix`, `modules/assertions.nix`, `modules/plugins/*` (content transliterated into `modules/catalog/*`), `overlays/emacs-packages/default.nix` (the Phase-0 stub scope overlay — replaced by the `<name>/package.nix` directory convention + `.gitkeep`, §2), generation.nix's central `form` emitter (emission moves into the shared type), the `pkgs.ennoix.{tests,examples}` nested attrset, `testFailLoud` and the per-plugin eval tests (the override-replacement lock survives as the §8 tier-1 test).

**Rewritten:** `modules/{generation,build,eval-tests}.nix`, `overlays/default.nix` (the `ennoix` overlay is deleted; the new `emacs-packages` and `tests` slots join the compose list and the exports — `overlays.ennoix` disappears from the flake's exported overlays), `hydra-jobs/tests.nix` (§8), `flake.nix` (`packages.<system>.default` → `ennoix-emacs`).

**Carried** (content, into the new shape): the seven curated configs (only magit's `bind` changes shape — structured `attrsOf str`; the rest are `init`/`config` lines; modus-themes stays a package per the recorded policy; **magit takes no `runtimePackages` in this refactor** — `git` rides Phase 1's first `runtimePackages` use), the default.el/native-comp mechanics, the load-gate script, the **two-jobset (packages/tests) split** (the tests jobset's internal shape changes per §8).

**Docs:** amend the old architecture spec's Status line to "partially superseded by this document (package-set/eval/namespace sections replaced; emacs mechanics remain valid)".

Issue dispositions: #2 (`${` hazard) carries to the new generation site; #3 (untested keyword shapes) is addressed by the tier-1 equality tests covering every shipped emitter; #4 (deferred-`:config` gate limitation) carries, documented at the gate; #5 (`build.emacsWithPackages`) — the option is dropped in the re-architecture; the HM adapter plan will re-introduce what it actually needs.

Out of scope here (unchanged roadmap): Phase-1 plugins (consult, embark, embark-consult, wgrep — research complete, lands as catalog entries after this refactor), HM/NixOS adapters, profiles, early-init.
