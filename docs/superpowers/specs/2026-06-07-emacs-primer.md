# Emacs primer for ennoix

You're building a Nix configuration tool for emacs. This primer covers the
emacs concepts you'll need shared vocabulary for. It does **not** teach you
to use emacs day-to-day — it teaches you what emacs *configuration* is made
of, so design discussions land.

Non-obvious factual claims are cited to source files in the emacs,
nixpkgs, and emacs-overlay trees (e.g. `doc/misc/use-package.texi`,
`pkgs/applications/editors/emacs/...`). Line numbers drift between emacs
versions — treat them as approximate anchors within the named file/node,
not exact. If a claim isn't cited, it's a definitional statement or a
high-level summary.

______________________________________________________________________

## 1. The mental model

An emacs installation is three things stacked on top of each other:

```
  ┌─────────────────────────┐
  │  Your init file (.el)   │  ← elisp code that runs at startup
  ├─────────────────────────┤
  │  Installed packages     │  ← elisp libraries on the load-path
  ├─────────────────────────┤
  │  The emacs binary       │  ← C + bundled elisp ("built-in" packages)
  └─────────────────────────┘
```

The binary is a complete Lisp environment. "Configuring emacs" means
*writing a Lisp program* that customizes it at startup. There's no
configuration DSL — every setting, every keybind, every plugin enablement
is just elisp code in a file. This is the central thing to absorb: an
emacs "config" is a **program**, not a settings file.

(Caveat: emacs also ships `customize`, an interactive UI that writes
settings to a "custom file" automatically. Most config guides — and most
emacs users we want to attract — eschew it in favor of explicit elisp,
but it exists, and it collides with a read-only nix-generated config in a
way that forces a design decision — see §7.3.)

The init file is normal Emacs Lisp. Everything else — `use-package`, the
package manager, third-party plugins — is *also* normal Emacs Lisp,
running in the same Lisp environment, on top of which the init file just
happens to be the entry point.

______________________________________________________________________

## 2. The init file: `init.el`

### Where it lives

Emacs has two tiers of search (`doc/emacs/custom.texi:3040`).

**Traditional paths** (checked first, in order):

1. `~/.emacs.el`
1. `~/.emacs`
1. `~/.emacs.d/init.el`

**XDG fallback** (only if none of the above exist):

4. `~/.config/emacs/init.el` (or `$XDG_CONFIG_HOME/emacs/init.el`)

Quote (`custom.texi:3050`):

> However `~/.emacs.d`, `~/.emacs`, and `~/.emacs.el` are always preferred
> if they exist, which means that you must delete or rename them in order
> to use the XDG location.

And (`custom.texi:3054`): if neither XDG nor `~/.emacs.d` exists, emacs
*creates* `~/.emacs.d` — fresh installs default to the legacy path.

Modern convention: `~/.emacs.d/init.el` or `~/.config/emacs/init.el`.

For ennoix we'll generate the file and point emacs at it. Note a
subtlety we'll have to design around: `--init-directory`
(`doc/emacs/cmdargs.texi`, the `--init-directory` item) **only sets
`user-emacs-directory`; it does not suppress the legacy `~/.emacs` /
`~/.emacs.el` search, and if there's no `init.el` in the named directory
emacs falls back to the init file it would have used anyway.** So the
flag alone doesn't guarantee our file is used — an `init.el` must
actually exist in the target directory. (Owning the init files vs.
injecting via `default.el` is a real design fork — see §5.4.)

### Loading order at startup

There's a second file, `early-init.el` (`doc/emacs/custom.texi:3152`):

> This file is loaded before the package system and GUI is initialized, so
> in it you can customize variables that affect the package initialization
> process, such as `package-enable-at-startup`, `package-load-list`, and
> `package-user-dir`.

Order: `early-init.el` → package activation → `init.el`.

### What goes in init.el

Plain emacs lisp. Examples of the kinds of things you'd write:

```elisp
;; Set a variable
(setq inhibit-startup-screen t)

;; Bind a key
(global-set-key (kbd "C-c f") 'find-file)

;; Add a hook (run a function whenever a mode activates)
(add-hook 'prog-mode-hook 'display-line-numbers-mode)

;; Load a package and configure it
(require 'magit)
(setq magit-completing-read-function 'ivy-completing-read)
```

The boilerplate gets repetitive fast — you `require`, you `setq`, you
`add-hook`, you `global-set-key`. `use-package` exists to consolidate this
(see §4).

### Modes and hooks (vocabulary)

Nearly every per-plugin enable/attach surface is built on three concepts
(`doc/lispref/modes.texi`, "Major and Minor Modes"):

- **Major mode** — exactly one per buffer; sets the buffer's primary
  behavior (e.g. `python-mode`). Usually selected by file extension via
  `auto-mode-alist` — which is what `use-package`'s `:mode` populates.
- **Minor mode** — a toggleable feature; many can be active per buffer,
  globally or buffer-locally (e.g. `display-line-numbers-mode`). Enabling
  a package's feature is often "turn on its minor mode."
- **Hook** — a variable holding a list of functions a mode runs when it
  activates, named `<mode>-hook` (e.g. `prog-mode-hook`). Attaching a
  feature to a context = adding a function to that context's hook, which
  is what `use-package`'s `:hook` does.

The design's "enable globally" vs "enable per filetype" choice maps
directly onto: a global minor mode, vs `add-hook` on a major-mode hook,
vs a `:mode`/`auto-mode-alist` entry.

______________________________________________________________________

## 3. The package landscape

### Built-in: `package.el`

`package.el` is emacs's built-in package manager, added in emacs **24.1**
(`etc/NEWS.24:2545`, under heading "Changes in Emacs 24.1" at line 2452).
It downloads `.el` files from "package archives" (HTTP servers serving an
index + tarballs).

**Default archives** (`doc/emacs/package.texi:419`):

- **GNU ELPA** — GNU packages "considered part of GNU Emacs but
  distributed separately from the core" (`package.texi`). (They generally
  require FSF copyright assignment, but the manual states that criterion
  explicitly only for NonGNU ELPA, below — so treat it as background, not
  a cited fact.)
- **NonGNU ELPA** — third-party packages whose copyright is *not* assigned
  to the FSF, but still maintained by the emacs developers.

Both are at `elpa.gnu.org` / `elpa.nongnu.org`. These are the "blessed"
sources.

**Third-party archive**:

- **MELPA** (Milkypostman's Emacs Lisp Package Archive,
  `melpa.org`) — the de-facto largest archive. *Not* endorsed by GNU. The
  emacs manual gives a generic warning about third-party archives
  (`package.texi:437`):

  > do so at your own risk, and use only third parties that you think you
  > can trust!

  In practice, ~everyone uses MELPA. Most of the emacs ecosystem
  publishes there.

**Important emacs 27+ behavior change** (`etc/NEWS.27:226`):

> Installed packages are now activated *before* loading the init file. As
> a result of this change, it is no longer necessary to call
> `package-initialize` in your init file.

Pre-27 emacs would *automatically insert* `(package-initialize)` into
your init.el when it started — that's why so many old configs have it.
Don't add it yourself. (Unless you target emacs \<27.) The variable that
gates the new behavior is `package-enable-at-startup`.

**Important for ennoix (verified by spike):** do **not** disable
`package.el`. nix-built packages are placed on `package-directory-list`
(the wrapper's `elpa` dir), and it is `package-activate-all` — which runs
at startup precisely *because* `package-enable-at-startup` is `t` — that
loads each package's `*-autoloads.el`. With `package-enable-at-startup nil`, those autoloads never load and deferred packages (and even
`fboundp` checks) silently break. So nix replaces the *install/fetch*
role of `package.el`, but its *activation* role is load-bearing and must
stay on.

### Alternative: `straight.el`

`straight.el` is a third-party package manager that fetches directly from
git repositories instead of pre-built archives. Its "reproducibility" is
config-side commit pinning — **not** a nix-store-level guarantee; don't
equate the two in design comparisons. *(Unverified — not cited from a
primary source; check before relying on details.)*

### Alternative: `elpaca`

Another third-party manager, newer, designed for parallel/async installs.
*(Unverified.)*

**For ennoix:** nix replaces the **fetch/install** role of these tools —
the `.el` files come from `nixpkgs` (or `emacs-overlay`) as nix-built
derivations on the load-path. But "bypassed entirely" is wrong on two
counts: (1) `package.el` stays *loaded and active*, and its activation is
**required** — it's what loads the nix packages' autoloads (above); (2) a
stray `:ensure t` can still trigger a network install even though nix
already supplied the package. So the correct stance is *keep package.el
enabled, but never `:ensure`*. We unpack what `use-package` keeps doing
under nix in §4 ("use-package's role under nix").

______________________________________________________________________

## 4. `use-package`

`use-package` is a macro that wraps the boilerplate of "load this
package, configure it, bind some keys, add some hooks" into one
declaration. The emacs manual describes it (`doc/misc/use-package.texi`):

> The `use-package` macro allows you to set up package customization in
> your init file in a declarative way.

It became **built-in in emacs 29.1** (`etc/NEWS.29:2929`, under heading
"New Modes and Packages in Emacs 29.1" at line 2916). Before that you
had to install it as a regular package. Now `(use-package ...)` is
available out of the box.

It is **not required** to configure emacs — it's convention. You can
write the same effects in plain elisp. But ~every modern config uses it,
and our generated init.el will too, because it's the cleanest mapping
from "structured nix config" to "lisp code".

### The shape

```elisp
(use-package PACKAGE-NAME
  :ensure t                ; install via package.el if missing
  :defer t                 ; don't load eagerly
  :hook (prog-mode . my-function)
  :bind (("C-c f" . find-file))
  :init  (setq foo-var t)  ; runs before package loads
  :config (foo-mode 1))    ; runs after package loads
```

Keywords (all source-verified from `doc/misc/use-package.texi`):

| Keyword | What it does |
|---|---|
| `:ensure t` | At runtime, install via package.el if missing (`:1678`). The runtime installer *can* be redirected by setting `use-package-ensure-function` (`:1827`) — but note **emacs-overlay does not do this**; it reads `:ensure` at nix-eval time to pick which packages to bake in (see §6.3), it does not swap the runtime installer. Under nix, `:ensure` is a hazard — see §4 "use-package's role under nix". |
| `:defer t` | Don't load the package eagerly; wait for a trigger (`:331`). Accepts numeric N to load after N idle seconds. The manual notes (`:343`) `:defer t` by itself is rarely useful — usually combined with `:config`, `:bind`, etc. |
| `:hook (mode . fn)` | Add `fn` to `mode-hook`. The `-hook` suffix is appended for you (`:1247`). Implies `:defer t` (`:1354`). |
| `:bind (("KEY" . cmd))` | Globally bind a key to a command. Creates autoloads (`:919`). |
| `:init` | Code that runs *before* the package loads (`:799`). |
| `:config` | Code that runs *after* the package loads (`:811`). |
| `:commands` | Declare interactive commands as autoloads — package loads when one is invoked (`:715`). |
| `:mode "REGEX"` | Register a `auto-mode-alist` entry — package loads when a matching file opens (`:1365`). |
| `:after pkg` | Don't configure until `pkg` has loaded (`:505`). |
| `:custom (var val)` | Set a customizable variable. Preferred over `setq` in a `:config` block because some variables have setter logic that `setq` skips (`:1466`). In emacs 29+ the built-in `setopt` macro does the same. (The manual itself recommends `M-x customize` for most users — `:1450` — which is a different tradeoff.) |
| `:preface` | Code that runs before *everything else except `:disabled` and `:ensure`* (`:774`). Evaluated at both byte-compile and load time — avoid side effects. |
| `:demand t` | Force eager loading, overriding deferral triggers (`:394`). Note: if both `:demand t` and `:defer t` are given, `:defer` wins (`:401`). |
| `:disabled` | Skip this declaration entirely (`:2037`). |
| `:if FORM` / `:when` / `:unless` | Conditional load based on a runtime expression (`:412`). Does **not** gate `:ensure` or `:preface` (`:484`). |

Best-practice nudge from the manual (`use-package.texi:825`):

> Where possible, it is better to avoid `:preface`, `:config` and
> `:init`. Instead, prefer autoloading keywords such as `:bind`, `:hook`,
> and `:mode`, as they will take care of setting up autoloads for you
> without any need for boilerplate code.

Translation: a well-designed `use-package` form expresses *triggers* (the
hooks, modes, keys that should cause the package to load) rather than
side-effects (eager `:config` blocks). For a *generator* this is sharper:
the **shape** of the emitted form controls startup cost. Emitting
`:hook`/`:bind`/`:mode` yields lazy loading automatically; a bare
`:config` block forces an eager load. With a large nix-bundled package
set, eagerly loading everything inflates startup — so the design should
prefer mapping declarative triggers onto autoloading keywords.

(`leaf` is a `use-package`-like alternative macro. It is **not**
load-bearing for the design: a generator owns which macro it emits, and
`use-package` is the built-in, de-facto target. Design against
`use-package`; defer any macro-choice debate.)

### use-package's role under nix

This is the single most important thing to get right, because the primer
taught `package.el`, `:ensure`, and "nix supplies packages" as separate
facts that must now be **composed**.

Nix replaces **only** the fetch/install role. Everything else
`use-package` does still happens at startup, unchanged, because it runs
regardless of where the `.el` files came from:

- `require`/autoload wiring, `:init`/`:config` evaluation,
- `:defer` lazy-loading, and the `:hook`/`:bind`/`:mode` triggers.

The trap is `:ensure`. The correct design stance for a *generating* tool
is to emit **no** `:ensure` (set `use-package-always-ensure nil`): the
tool already knows the exact package list, so the declared set *is* the
closure set and cannot drift. `:ensure t` expands to `package-install` /
`package-refresh-contents` for any package `package-installed-p` deems
missing (`use-package-ensure.el:127-139`) — a network fetch that defeats
reproducibility. Whether a given nix package counts as "installed"
depends on whether `package-activate-all` registered it, so the only safe
rule is **never `:ensure`**. (This is why emacs-overlay's
parse-then-`alwaysEnsure` approach is the inverse of what we want; §6.3.)

### Autoloads — the deferral mechanism (and how nix changes it)

`use-package`'s deferral works **entirely via autoloads**: `:bind`,
`:hook`, `:commands`, `:mode` register autoload stubs so the package
loads on first use. The manual warns explicitly that if you use no
autoload-registering keyword *and* your package manager doesn't provide
autoloads, "it is possible that your package will never be loaded if you
do not add `:demand t`" (`doc/misc/use-package.texi`).

Under nix this works **automatically** (verified by spike): the wrapper
places each package's `elpa` dir on `package-directory-list`, and
`package-activate-all` — which runs at startup *because*
`package-enable-at-startup` is `t` — loads every package's
`*-autoloads.el` (spike: `package-activated-list` held the enabled
package and its mode was autoloaded). No `package-quickstart` call and no
special config arrangement is needed. The **one rule**: don't disable
`package.el` — that skips activation and the autoloads never load, at
which point deferred forms silently never load (the manual's
`:demand t`-or-nothing warning, `doc/misc/use-package.texi`). So
"autoloads via package activation" is a property of the wrapper we rely
on, not something ennoix must build.

______________________________________________________________________

## 5. Emacs in nixpkgs

This is where it gets nix-y. There are three layers to know.

### 5.1 `emacsPackages` — the elisp package set

`pkgs.emacsPackages` is an attribute set with thousands of emacs
packages, each a nix derivation. The actual *scope* is constructed by
`emacsPackagesFor` in `pkgs/top-level/emacs-packages.nix` via
`lib.makeScope`; `pkgs.emacsPackages` is a `recurseIntoAttrsWith` view
of `emacs.pkgs` defined at `pkgs/top-level/all-packages.nix:8918`.
Source categories (`emacs-packages.nix:80-86`):

- `elpaPackages`, `elpaDevelPackages` (GNU ELPA stable + devel)
- `nongnuPackages`, `nongnuDevelPackages` (NonGNU ELPA)
- `melpaStablePackages`, `melpaPackages` (MELPA stable + unstable)
- `manualPackages` (hand-curated entries in
  `pkgs/applications/editors/emacs/elisp-packages/manual-packages/`)

Top-level alias (`pkgs/top-level/all-packages.nix:8918`):

```nix
emacsPackages = recurseIntoAttrsWith {
  hydra = false;
  eval = false;
} emacs.pkgs;
```

Note: `pkgs.emacsPackages` is just a search-visible view onto
`pkgs.emacs.pkgs`. They are the same scope.

### 5.2 `emacsWithPackages` — bundle emacs with packages

The wrapper that produces "emacs that knows about these elisp packages"
is at `pkgs/applications/editors/emacs/build-support/wrapper.nix`.
Signature (lines 33-49):

```nix
{ lib, lndir, makeBinaryWrapper, runCommand, }:
self:
let inherit (self) emacs; …
in
packagesFun:               # a list, OR a function epkgs -> [pkg]
…
```

You typically use it like:

```nix
emacs.pkgs.withPackages (epkgs: [
  epkgs.magit
  epkgs.which-key
  epkgs.vertico
])
```

This produces a derivation that:

1. Uses `lndir` to mirror each requested package's `share/emacs/site-lisp/`
   tree (plus native-compiled `share/emacs/native-lisp/` and tree-sitter
   `lib/`) into the output. `bin/` executables are handled differently —
   symlinked by resolved (`realpath`) path rather than `lndir`'d, to avoid
   breaking relative symlinks (`wrapper.nix`, `linkPath`).
1. Generates a `site-start.el` that re-loads the original site-start and
   extends `exec-path`. The site-lisp load-path entry itself is wired by
   the shell wrapper around the emacs binary (see the
   `;; "$out/share/emacs/site-lisp" is added to load-path in wrapper.sh`
   comment at `wrapper.nix:180`).
1. (If `withNativeCompilation`) links the `.eln` native-compiled files.

The result *is* emacs — running it gives you a normal emacs that has
those packages on its load-path. No init.el involvement.

### 5.3 Three names for the same thing

`emacs.pkgs.withPackages`, `emacs.pkgs.emacsWithPackages`, and
`(emacsPackagesFor emacs).withPackages` are all aliases
(`pkgs/top-level/emacs-packages.nix:139`):

```nix
emacsWithPackages = emacsWithPackages { inherit pkgs lib; } self;
withPackages = emacsWithPackages { inherit pkgs lib; } self;
```

`emacsPackagesFor` is the *function* that builds the scope for an
arbitrary emacs derivation (`all-packages.nix:8909`). This matters for
ennoix: if you want a different emacs (say `emacs-pgtk` or a custom
override), you do `emacsPackagesFor my-emacs` to get the matching
package set.

### 5.4 But where does init.el go?

Nixpkgs proper has **no built-in idiom** for "emacs with these packages
*and* this init.el." The `emacsWithPackages` wrapper doesn't accept an
init-file argument.

There are two strategies, and choosing between them is a real design
fork:

**Strategy A — `default.el` injection (emacs-overlay style).** Write the
config into a tiny package named `default` via `epkgs.trivialBuild` and
include it in the package list. Emacs auto-loads `default.el` from
`site-lisp` *after* the user's init.el, and skips it if
`inhibit-default-init` is non-nil (`emacs/lisp/startup.el`, "load
default.el after the init-file unless inhibit-default-init"). Additive,
needs no `~/.emacs.d/` management — but because it runs **after** user
init it cannot override the user's own config, and it **cannot host
early-init concerns** (frame setup, GC tuning, `package-quickstart`),
which must run *before* package activation.

**Strategy B — own the init files (rycee style).** Write
`early-init.el` + `init.el` stubs into the user's emacs directory (rycee
emits stubs that `(require 'hm-early-init)` / `(require 'hm-init)` against
generated trivialBuild packages). Full control, can host early-init and
`package-quickstart` — at the cost of taking over those files.

**The full startup timeline** (compose §2's order with the `default.el`
fact):

```
early-init.el → package activation → init.el (user) → default.el (nix-injected, unless inhibit-default-init)
```

Design consequence: with Strategy A, nix-injected config runs **last** so
it can override emacs defaults, but a user's own init.el runs **first**
and is *not* overridden — the inverse of what a source-of-truth tool
usually wants. Strategy B is the way to be authoritative and to own
early-init. This interacts with the `--init-directory` caveat in §2.

______________________________________________________________________

## 6. `emacs-overlay` (nix-community)

The community overlay at github.com/nix-community/emacs-overlay does two
big things plus some niceties.

### 6.1 Daily-refreshed package archives

The overlay overrides `emacsPackagesFor` to point the existing nixpkgs
package generators at its own JSON/nix files
(`overlays/package.nix:1-20`):

```nix
self: super:
{
  emacsPackagesFor = emacs: (
    (super.emacsPackagesFor emacs).overrideScope (
      eself: esuper: let
        melpaStablePackages = esuper.melpaStablePackages.override {
          archiveJson = ../repos/melpa/recipes-archive-melpa.json;
        };
        melpaPackages = esuper.melpaPackages.override {
          archiveJson = ../repos/melpa/recipes-archive-melpa.json;
        };
        elpaDevelPackages = esuper.elpaDevelPackages.override {
          generated = ../repos/elpa/elpa-devel-generated.nix;
        };
        …
```

The archive JSON/nix files are updated via the overlay's `./update`
script (which calls nixpkgs's own `update-melpa`). nixpkgs's archives
update on a slower cadence; emacs-overlay's are claimed to be daily (see
its README).

### 6.2 Bleeding-edge emacs

The overlay exposes `emacs-git`, `emacs-git-pgtk`, `emacs-git-nox`,
`emacs-unstable`, `emacs-unstable-pgtk`, `emacs-unstable-nox`,
`emacs-igc`, `emacs-igc-pgtk` (`overlays/emacs.nix:176-183`). These
override `super.emacs` with sources pulled from emacs git, pinned in
single-line JSON files in `repos/emacs/`.

### 6.3 `emacsWithPackagesFromUsePackage`

This is the most relevant thing for ennoix. Defined in
`emacs-overlay/elisp.nix:14-24`:

```nix
{ config
, defaultInitFile ? false
, alwaysEnsure ? false
, alwaysTangle ? false
, extraEmacsPackages ? epkgs: [ ]
, package ? pkgs.emacs
, override ? (self: super: { })
}:
```

What it does:

1. Takes `config`: a string, path, derivation, or `.org` file containing
   `(use-package …)` declarations.
1. If `.org`, tangles it first with `emacs -Q --batch ./config.org -f org-babel-tangle` (`elisp.nix:78-84`).
1. Parses the config by reading it into an elisp AST with a
   Nix-implemented Emacs Lisp reader (`fromElisp`), then walking the tree
   for literal `(use-package …)` / `(leaf …)` forms (`parse.nix`, the
   `recurse` walk descends into every sub-list). Because it operates on
   *unexpanded source*, it **does** find forms nested inside conditionals
   like `(when cond (use-package foo))` — but it **cannot** see
   declarations produced by macro expansion, or package names that aren't
   literal symbols. (Regex is used only for the separate
   `;; Package-Requires:` header path, not for use-package extraction.)
1. Looks each up in the (overlayed) `epkgs` scope.
1. Calls `emacsWithPackages` with the resulting package list.
1. The `defaultInitFile` argument controls config injection:
   - `true` → wraps the (tangled, parsed) config into a `default.el`
     package via `epkgs.trivialBuild` and includes it.
   - a derivation (whose name must be `default.el`) → used as the **src**
     of the same `trivialBuild` `default` package (byte-compiled and
     installed to site-lisp), not consumed as-is.
   - `false` (default) → no init injection; you only get the packages.

In one function: "give me emacs with packages derived from this init.el
*and* (optionally) my init.el preloaded." This is the bridge between
"declarative emacs config" and "single nix-built emacs derivation."

It's also a pattern we should not blindly inherit. Parsing `use-package`
text to extract package names is one route; **generating** the init.el
*from* a declarative nix structure (which is what nixvim does, and which
rycee already does for emacs — §8) is another. With generation the
package list is known structurally, so parsing is unnecessary — and the
generate path is categorically immune to the parser's limits (no
unicode-in-config restriction, no token-length caps, no
computed-name blind spots). We'll pick a side at design time.

(Org-babel tangling here is an *input* convenience: user `.org` →
tangle to `.el` → parse. A generating design produces `.el` from nix
options directly and doesn't need it; literate/org support, if wanted, is
a separable optional input layer. Note the overlay's org detection is
narrow — only a path or store-path string ending in `.org` triggers
tangling, not an inline org string.)

______________________________________________________________________

## 7. Generating config: design-critical mechanics

Three cross-cutting concerns a *generating* tool must handle. None are
optional details; each has a silent-failure mode.

### 7.1 Config ordering — three layers

The brief asked how nixvim's `extraConfigLuaPre`/`Post` ordering maps to
elisp. nixvim assembles one file from ordered buckets
(`extraConfigLuaPre → … → extraConfigLua → extraConfigLuaPost`;
`modules/output.nix`). Elisp has **three distinct ordering layers**, and
only two map onto nixvim:

1. **`early-init.el` vs `init.el` boundary** — a hard "Pre" that runs
   *before* package activation (rycee's `earlyInit`, merged with
   `mkBefore`). No nixvim analog this strong.
1. **Textual order within init.el** — prelude / per-package forms /
   postlude. This is the direct `Pre`/`Post` analog.
1. **Deferred load order via `:after` and hooks** — and this is the
   trap: **a deferred package's `:config` does not run in text order; it
   runs when its trigger fires.** Text position in init.el does *not*
   determine when deferred code executes; `:after`/hooks do. **No nixvim
   equivalent.** A design that exposes only Pre/Mid/Post buckets (mirroring
   nixvim 1:1) will mislead users about deferred-load ordering.

The design should expose all three explicitly so "where my config sits in
the file" is never confused with "when my config runs."

### 7.2 Compilation of the generated config

The nixvim model ships config as a derivation; the emacs analog (rycee,
overlay) ships the generated init as a `trivialBuild` package — which
**byte-compiles at build time** (and native-compiles to `.eln` when the
emacs has native-comp; native compilation is emacs 28+, opt-in via the
emacs derivation, `etc/NEWS.28`). Consequences for the design:

- **Every package referenced in the config must be in the build
  closure** — byte-compilation resolves references at build time (rycee
  passes them via `packageRequires`). A reference to a package not in the
  closure fails the **build**, not silently at runtime. (That's mostly a
  feature — errors surface early.)
- **`use-package` has byte-compile-*time* semantics**, not just load
  time: `:preface` is evaluated at both compile and load time, and
  `:defines`/`:functions` exist specifically to quiet the byte-compiler.
- **Edits couple to rebuilds** — a compiled, store-immutable config can't
  be hot-edited; changing config means `nix build` again.

### 7.3 `customize` / `custom-file` (honoring §1's promise)

§1 flagged `customize`. Here's why it's a design fork, not a detail:
emacs's interactive `M-x customize` writes settings to a *custom file* at
**runtime** (by default appended into `init.el` via
`custom-set-variables`). But a nix-generated `init.el`/`default.el` lives
**read-only in `/nix/store` and is byte-compiled** — it cannot host
runtime customize writes. The "config is a program" framing (§1) quietly
assumes all state lives in the program text, which is exactly the
intuition `customize` violates.

So the design must pick one: (a) point `custom-file` at a writable
`$HOME` path and load it, (b) generate `:custom`/`setopt` forms from nix
and declare the program text authoritative, or (c) declare interactive
`customize` unsupported. Related concrete choice: the **variable-setting
output format** — `:custom`/`setopt` (runs setter logic) vs `setq` (skips
it) — is a generator decision the tool must make.

______________________________________________________________________

## 8. Where the prior art lives

All three below are now source-verified (against fresh clones).

**rycee's home-manager module — the closest prior art, and it is a
Nix→elisp use-package *compiler* (not a bare wrapper).**
`nur-combined/repos/rycee/hm-modules/emacs-init.nix` defines a
`usePackageType` submodule and `programs.emacs.init.usePackage.<name>`
(an `attrsOf` that type), with typed per-package sub-options — `config`,
`hook`, `bind`, `bindLocal`, `bindKeyMap`, `custom`, `defer`, `demand`,
`diminish`, `chords`, `mode`, `interpreter`, `after`, `command`,
`functions`, `init`, `extraConfig`, `earlyInit`, `extraPackages` — and
assembles `use-package` forms into a generated init. It already solves
several things ennoix will face: ordering buckets (`prelude`/`postlude`),
shipping the config as a byte-compiled `trivialBuild` package, an
`early-init`/`init` split, and `package-quickstart` for autoloads. It
layers on top of upstream `programs.emacs` (keyed under
`programs.emacs.init.*`).

Two important boundaries (verified): this compiler is **only** in
rycee's third-party NUR repo — stock home-manager `programs.emacs` has
just `enable`/`package`/`extraConfig`(raw text)/`extraPackages`/
`overrides`/`finalPackage`, **no** usePackage tree. And rycee does **not**
ship a nixvim-style *catalog* of pre-wired plugin modules (its
`emacs-init-defaults.nix` is ~thin mode/path glue, plus a couple of
integrations) — the user still writes the per-package config, just as
nix attrs instead of elisp text. So rycee is the proof that the
generation engine is tractable for emacs; it is **not** a pre-configured
plugin catalog.

**nixvim — the architectural target.** `github.com/nix-community/nixvim`
wraps neovim with per-plugin nix modules (452 `plugins/by-name/<name>`
dirs + ~33 colorschemes) and assembles a final config from declarative
module options. A `wrappers/` dir provides standalone / home-manager /
nixos / darwin delivery over a shared module-eval core, and a public
`flake.lib` exposes `evalNixvim` / `makeNixvim` / `makeNixvimWithModule`.
Caveat worth carrying into design: each nixvim plugin module is *cheap*
because neovim has a universal `require('x').setup({…})` convention — a
freeform settings table serialized to one call. **Emacs has no such
universal convention** (config is heterogeneous `setq`/`hook`/`bind`/
`defcustom`), so an emacs catalog module looks more like a rycee
per-package entry than a one-line nixvim wrapper. The catalog is the
expensive part.

**Adjacent prior art to examine (not yet surveyed):**
nix-doom-emacs / nix-doom-emacs-unstraightened occupy the
"curated, batteries-included emacs via nix" niche from a different angle
(consuming Doom's module catalog rather than generating from typed nix).
Worth understanding before committing to the catalog framing.

The gap ennoix would fill, stated precisely: a **nixvim-style catalog of
pre-wired, richly-typed per-plugin modules** for emacs, plus **standalone
`nix run` delivery** — built on emacs-overlay's binaries/package-sets/
wrapper, with a generation engine of the kind rycee proves works.

______________________________________________________________________

## 9. Glossary cheat-sheet

- **elisp / Emacs Lisp** — the language emacs and its config are written in.
- **`init.el`** — the user's entrypoint file. Plain elisp.
- **`early-init.el`** — runs before package activation and GUI setup.
- **`package.el`** — built-in package manager (since emacs 24.1).
- **GNU ELPA / NonGNU ELPA** — official package archives.
- **MELPA** — third-party archive; not endorsed but ubiquitous.
- **`use-package`** — declarative macro for per-package setup. Built-in since emacs 29.1.
- **`emacsPackages`** — nixpkgs attrset of nix-built emacs packages.
- **`emacsWithPackages`** — function: bundles emacs with a set of packages into one derivation.
- **`emacsPackagesFor`** — function: given an emacs derivation, returns its package scope.
- **`emacs-overlay`** — nix-community overlay providing daily archives + bleeding-edge emacs + the `emacsWithPackagesFromUsePackage` helper.
- **`trivialBuild`** — generic nixpkgs builder for simple elisp packages (single source dir, byte-compiled, installed to `site-lisp`). One use is shipping init code as `default.el`.

______________________________________________________________________

## 10. What you don't need to know yet

Deliberately omitted from this primer (we'll cover when relevant):

- elisp syntax beyond the snippets above
- specific plugins and what they do (magit, evil, vertico, etc.)
- doom-emacs / spacemacs architecture (though nix-doom-emacs is worth a
  look as adjacent prior art — §8)
- treesitter integration
- the emacs daemon / `services.emacs` (a *delivery* concern — running a
  configured emacs as a background server for fast `emacsclient` frames;
  orthogonal to *configuring* emacs, revisit at design time)
