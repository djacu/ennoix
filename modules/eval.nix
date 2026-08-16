# ennoixEval's substance: assemble baseModules (namespace + generation +
# build + the collected catalog + the collected profiles) and evaluate user
# modules against them.
{ lib, pkgs }:
let
  catalogDir = ./catalog;
  # Every DIRECTORY under modules/catalog is an entry; its module MUST be
  # named module.nix. A misnamed module fails naturally at import
  # ("path '.../module.nix' does not exist", naming the entry).
  catalogModules = map (name: catalogDir + "/${name}/module.nix") (
    builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir catalogDir))
  );

  # Every DIRECTORY under modules/profiles is a profile; its module MUST be
  # named profile.nix. Toggles are registered here from the dir names so each
  # profile's `enable` materializes at its false default even when off — which
  # lets profile.nix stay a pure `mkIf config.profiles.<name>.enable {…}` body.
  profilesDir = ./profiles;
  profileNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir profilesDir)
  );
  profileModules = map (name: profilesDir + "/${name}/profile.nix") profileNames;
  profileToggles = {
    profiles = lib.genAttrs profileNames (_: { });
  };

  baseModules = [
    ./use-package.nix
    ./generation.nix
    ./build.nix
    ./profiles.nix
    profileToggles
  ]
  ++ catalogModules
  ++ profileModules;
in
modules:
(lib.evalModules {
  modules = baseModules ++ modules;
  specialArgs = {
    inherit pkgs;
    mkCatalogDefault = lib.mkOverride 1400;
  };
}).config
