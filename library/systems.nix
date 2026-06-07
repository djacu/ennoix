{
  lib,
  ...
}:
let

  inherit (lib.attrsets)
    genAttrs
    ;

in
{

  defaultSystems = genAttrs [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

}
