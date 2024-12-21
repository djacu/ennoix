inputs:
let
  inherit (builtins)
    attrNames
    readDir
    ;

  inherit (inputs.nixpkgs)
    lib
    ;

  inherit (lib.attrsets)
    filterAttrs
    genAttrs
    ;
in
rec {
  genDirectories = dir: genAttrs (getDirectories dir);

  getDirectories =
    path: attrNames (filterAttrs (_: fileType: fileType == "directory") (readDir path));

  supportedSystems = genAttrs [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-darwin"
    "x86_64-linux"
  ];
}
