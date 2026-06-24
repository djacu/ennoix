{ lib }:
[
  ./generation.nix
  ./build.nix
  ./assertions.nix
]
++ import ./plugins { inherit lib; }
