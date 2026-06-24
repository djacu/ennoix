{ lib, nixpkgs }:
let
  baseModules = import ../modules/default.nix { inherit lib; };

  # Phase 0 callers always pass `pkgs` (from legacyPackages, already overlaid);
  # the system-only fallback does NOT apply the repo overlay and is unexercised.
  resolvePkgs =
    { pkgs, system }:
    if pkgs != null then
      pkgs
    else
      import nixpkgs {
        inherit system;
        config = {
          allowAliases = false;
          allowUnfree = true;
        };
      };

  evalEnnoix =
    {
      pkgs ? null,
      system ? null,
      modules ? [ ],
    }:
    assert lib.assertMsg (
      pkgs != null || system != null
    ) "ennoix: evalEnnoix needs either `pkgs` or `system`.";
    let
      pkgs' = resolvePkgs { inherit pkgs system; };
      epkgs = (pkgs'.emacsPackagesFor pkgs'.emacs).overrideScope (
        import ../overlays/emacs-packages/default.nix
      );
      cfg =
        (lib.evalModules {
          modules = baseModules ++ modules;
          specialArgs = {
            pkgs = pkgs';
            inherit epkgs;
          };
        }).config;
      failed = builtins.filter (a: !a.assertion) cfg.assertions;
    in
    if failed != [ ] then
      throw "ennoix assertions failed:\n${lib.concatStringsSep "\n" (map (a: a.message) failed)}"
    else
      cfg;

  makeEnnoix = args: (evalEnnoix args).build.package;
in
{
  inherit evalEnnoix makeEnnoix;
}
