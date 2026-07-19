inputs:
let

  # inherits

  inherit (inputs.nixpkgs-lib)
    lib
    ;

  inherit (lib.filesystem)
    listFilesRecursive
    packagesFromDirectoryRecursive
    ;

  inherit (lib.fixedPoints)
    composeManyExtensions
    ;

  inherit (lib.lists)
    filter
    ;

  # overlays

  # Fixes for upstream nixpkgs packages with broken hashes or other issues
  fixes = composeManyExtensions (
    map import (filter (path: baseNameOf path == "overlay.nix") (listFilesRecursive ./fixes))
  );

  top-level =
    final: prev:
    packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      inherit (prev) newScope;
      directory = ./top-level;
    };

  python-packages = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (
        python-final: _python-prev:
        packagesFromDirectoryRecursive {
          inherit (python-final) callPackage newScope;
          directory = ./python-packages;
        }
      )
    ];
  };

  verification =
    final: prev:
    packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      inherit (prev) newScope;
      directory = ./verification;
    };

  # ennoix test derivations; hydra-jobs/tests.nix collects this slot by
  # directory name (the same jobset<->directory pairing as packages.nix).
  tests =
    final: prev:
    packagesFromDirectoryRecursive {
      inherit (final) callPackage;
      inherit (prev) newScope;
      directory = ./tests;
    };

  # ennoix's emacs-scope extension: catalog-gap packages as
  # emacs-packages/<name>/package.nix, callPackage'd against the SCOPE
  # (with pkgs fallback). Wraps the FUNCTION so every produced scope —
  # pkgs.emacsPackages, emacs.pkgs, variant bases — carries the extension.
  emacs-packages = _final: prev: {
    emacsPackagesFor =
      emacs:
      (prev.emacsPackagesFor emacs).overrideScope (
        eself: _esuper:
        packagesFromDirectoryRecursive {
          inherit (eself) callPackage newScope;
          directory = ./emacs-packages;
        }
      );
  };

  default = composeManyExtensions [
    fixes
    top-level
    python-packages
    verification
    tests
    emacs-packages
  ];

in
{
  inherit
    default
    emacs-packages
    fixes
    python-packages
    tests
    top-level
    ;
}
