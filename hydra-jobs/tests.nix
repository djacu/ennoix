{
  supportedSystems ? [
    "aarch64-linux"
    "x86_64-linux"
  ],
  evalSystem ? builtins.currentSystem or "x86_64-linux",
  nixpkgs ? null,
}@args:
let
  inherit (import ./common.nix args) lib releaseLib self;
  inherit (releaseLib) pkgs;
  inherit (self.library.paths) getDirectoryNames;
  inherit (lib.attrsets) getAttrs recurseIntoAttrs;
in
# Single-eval-system jobset (no mapTestOn; test derivations carry no
# meta.platforms). Collected purely by path from overlays/tests — the same
# jobset<->directory pairing as packages.nix <-> overlays/top-level.
recurseIntoAttrs {
  ennoix = recurseIntoAttrs (getAttrs (getDirectoryNames ../overlays/tests) pkgs);
}
