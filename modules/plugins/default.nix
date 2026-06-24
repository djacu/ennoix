{ lib }:
let
  mkPlugin = import ../lib/mk-plugin.nix { inherit lib; };
  # ./. is modules/plugins/; the collector's own default.nix is a *file* (so it
  # is filtered out), and every *directory* beside it is a plugin.
  dir = ./.;
  names = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
in
map (name: import (dir + "/${name}") { inherit mkPlugin; }) names
