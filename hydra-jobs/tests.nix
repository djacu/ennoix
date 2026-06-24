{
  supportedSystems ? [
    "aarch64-linux"
    "x86_64-linux"
  ],
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
