# The ennoix eval entrypoint: modules -> config. callPackage'd by the
# top-level slot, so pkgs.ennoixEval gains .override { pkgs = ...; }.
{ lib, pkgs }: import ../../../modules/eval.nix { inherit lib pkgs; }
