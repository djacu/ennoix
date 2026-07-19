# ennoixEval's substance: assemble baseModules (namespace + generation +
# build + the collected catalog) and evaluate user modules against them.
{ lib, pkgs }:
let
  catalogDir = ./catalog;
  # Every DIRECTORY under modules/catalog is an entry; its module MUST be
  # named module.nix. A misnamed module fails naturally at import
  # ("path '.../module.nix' does not exist", naming the entry).
  catalogModules = map (name: catalogDir + "/${name}/module.nix") (
    builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir catalogDir))
  );
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
