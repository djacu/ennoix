{
  config,
  lib,
  epkgs,
  ...
}:
let
  inherit (lib)
    types
    mkOption
    filterAttrs
    mapAttrsToList
    hasAttr
    ;
in
{
  options.assertions = mkOption {
    default = [ ];
    type = types.listOf (
      types.submodule {
        options = {
          assertion = mkOption { type = types.bool; };
          message = mkOption { type = types.str; };
        };
      }
    );
  };
  config.assertions = mapAttrsToList (name: p: {
    assertion = p.package == null || hasAttr p.package epkgs;
    message = "ennoix: plugin '${name}' references package '${toString p.package}' not in the emacs package set.";
  }) (filterAttrs (_: p: p.enable) (config.plugins or { })); # or {}: empty catalog (see build.nix)
}
