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
    ;
  # `config.plugins or { }`: with an empty catalog (zero plugin modules) the
  # `plugins` option is undeclared, so a bare `config.plugins` throws
  # `attribute 'plugins' missing`. The `or { }` makes the empty case safe.
  enabledWithPkg = filterAttrs (_: p: p.enable && p.package != null) (config.plugins or { });
  pluginPkgs = mapAttrsToList (_: p: epkgs.${p.package}) enabledWithPkg;
  # Always wrap with a header + `(provide 'default)`. A truly EMPTY (or
  # comment-only) default.el fails native-compilation on emacs 30.2
  # (`native-compiler-error-empty-byte`); a single real form fixes it.
  # The initText option itself stays "" when nothing is enabled.
  defaultEl = epkgs.trivialBuild {
    pname = "default";
    version = "0";
    src = epkgs.callPackage (
      { runCommand, writeText }:
      let
        text = writeText "default.el" ''
          ;;; default.el --- ennoix generated config  -*- lexical-binding: t; -*-
          ${config.build.initText}
          (provide 'default)
          ;;; default.el ends here
        '';
      in
      runCommand "ennoix-default-src" { } ''
        mkdir -p "$out"
        cp ${text} "$out/default.el"
      ''
    ) { };
    packageRequires = pluginPkgs;
  };
in
{
  options.build.emacsWithPackages = mkOption { type = types.package; };
  options.build.package = mkOption { type = types.package; };
  config.build.emacsWithPackages = epkgs.withPackages (_: pluginPkgs);
  config.build.package = epkgs.withPackages (_: pluginPkgs ++ [ defaultEl ]);
}
