{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrValues
    concatMap
    filterAttrs
    makeBinPath
    mkOption
    types
    unique
    ;
  enabled = attrValues (filterAttrs (_: p: p.enable) config.usePackage);
  # No name resolution: option values ARE the derivations (null = built-in).
  # extraPackages: per-entry elisp installed without a use-package form —
  # symmetric with runtimePackages (build-level coverage arrives with the
  # first catalog entry that uses it).
  elispPkgs = unique (
    map (p: p.package) (builtins.filter (p: p.package != null) enabled)
    ++ concatMap (p: p.extraPackages) enabled
  );
  runtimePkgs = unique (concatMap (p: p.runtimePackages) enabled);
  epkgs = pkgs.emacsPackages;
  # NOTE: build.initText is spliced verbatim into this '' string. Catalog
  # elisp containing a literal ${...} would be Nix-interpolated or error —
  # escape as ''${ when it first appears. https://github.com/djacu/ennoix/issues/2
  # Always wrap with a header + (provide 'default): a truly EMPTY default.el
  # fails native-compilation on emacs 30.2 (native-compiler-error-empty-byte).
  defaultEl = epkgs.trivialBuild {
    pname = "default";
    version = "0";
    src = pkgs.runCommand "ennoix-default-src" { } ''
      mkdir -p "$out"
      cp ${pkgs.writeText "default.el" ''
        ;;; default.el --- ennoix generated config  -*- lexical-binding: t; -*-
        ${config.build.initText}
        (provide 'default)
        ;;; default.el ends here
      ''} "$out/default.el"
    '';
    packageRequires = elispPkgs;
  };
  emacsPkg = epkgs.withPackages (_: elispPkgs ++ [ defaultEl ]);
  # runtimePackages: wrap EVERY binary (emacs, emacsclient, etags, ...) so
  # the binaries are on PATH purely (emacs derives exec-path from PATH).
  # When empty, the output is byte-identical to the unwrapped package.
  withRuntime =
    if runtimePkgs == [ ] then
      emacsPkg
    else
      pkgs.symlinkJoin {
        name = "ennoix-${emacsPkg.name}";
        paths = [ emacsPkg ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          for prog in "$out"/bin/*; do
            wrapProgram "$prog" --prefix PATH : "${makeBinPath runtimePkgs}"
          done
        '';
        inherit (emacsPkg) meta;
      };
in
{
  options.build.package = mkOption {
    type = types.package;
    description = "The final runnable emacs (runtime-wrapped when any entry declares runtimePackages).";
  };
  config.build.package = withRuntime;
}
