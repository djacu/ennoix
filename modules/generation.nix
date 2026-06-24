{ config, lib, ... }:
let
  inherit (lib)
    types
    mkOption
    filterAttrs
    mapAttrsToList
    concatStringsSep
    optional
    ;
  # `or { }`: the empty catalog leaves `plugins` undeclared; a bare
  # `config.plugins` throws `attribute 'plugins' missing` (see build.nix).
  enabled = filterAttrs (_: p: p.enable) (config.plugins or { });
  # emit one use-package keyword (passthrough: list items / lines are literal elisp)
  listKw = kw: items: optional (items != [ ]) "  :${kw} (${concatStringsSep " " items})";
  boolKw = kw: b: optional b "  :${kw} t";
  linesKw = kw: s: optional (s != "") "  :${kw} ${s}";
  form =
    name: p:
    concatStringsSep "\n" (
      [ "(use-package ${name}" ]
      ++ boolKw "demand" p.demand
      ++ boolKw "defer" p.defer
      ++ listKw "after" p.after
      ++ listKw "commands" p.commands
      ++ listKw "mode" p.mode
      ++ listKw "hook" p.hook
      ++ listKw "bind" p.bind
      ++ listKw "custom" p.custom
      ++ linesKw "init" p.init
      ++ linesKw "config" p.config
      ++ [ "  )" ]
    );
in
{
  options.build.initText = mkOption {
    type = types.lines;
    default = "";
    description = "Generated init.el body (use-package forms for enabled plugins).";
  };
  config.build.initText = concatStringsSep "\n\n" (mapAttrsToList form enabled);
}
