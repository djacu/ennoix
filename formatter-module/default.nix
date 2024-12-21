inputs:
inputs.self.library.supportedSystems (
  system:
  let
    pkgs = inputs.self.legacyPackages.${system};
  in
  (inputs.treefmt-nix.lib.evalModule pkgs (
    { ... }:
    {
      config = {
        enableDefaultExcludes = true;
        projectRootFile = "flake.nix";
        programs = {
          mdformat.enable = true;
          mdsh.enable = true;
          nixfmt.enable = true;
          shellcheck.enable = true;
        };
        settings.global.excludes = [
          "LICENSE"
          ".git-blame-ignore-revs"
        ];
      };
    }
  ))
)
