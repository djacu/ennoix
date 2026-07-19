{ config, lib, ... }:
let
  inherit (lib)
    filterAttrs
    mapAttrsToList
    concatStringsSep
    mkOption
    types
    ;
  enabled = filterAttrs (_: p: p.enable) config.usePackage;
in
{
  options.build.initText = mkOption {
    type = types.lines;
    default = "";
    description = "Generated init.el body: enabled entries' use-package forms in attribute-name order.";
  };
  config.build.initText = concatStringsSep "\n\n" (mapAttrsToList (_: p: p.assembly) enabled);
}
