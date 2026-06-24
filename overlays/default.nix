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

  ennoix = final: _prev: {
    ennoix = {
      examples.full = inputs.self.library.ennoix.makeEnnoix {
        pkgs = final;
        modules = [ ];
      }; # empty for now; Task 5 fills it
      tests.unit =
        let
          failures = import ../modules/eval-tests.nix {
            inherit (final) lib;
            pkgs = final;
            evalEnnoix = inputs.self.library.ennoix.evalEnnoix;
          };
        in
        if failures == [ ] then
          final.runCommand "ennoix-tests-unit" { } "touch $out"
        else
          throw "ennoix unit tests failed:\n${final.lib.generators.toPretty { } failures}";
      tests.loads = final.runCommand "ennoix-tests-loads" { } ''
        export HOME=$(mktemp -d)
        ${final.ennoix.examples.full}/bin/emacs --batch \
          --eval '(package-activate-all)' \
          --eval '(load (locate-library "default") nil t)' \
          --eval '(message "ennoix-config-loaded-ok")' > log 2>&1 \
          || { echo "emacs exited non-zero:"; cat log; exit 1; }
        if grep -qiE 'error \(|lisp error|definition is void|wrong type|void-(function|variable)' log; then
          echo "config produced an error at load:"; cat log; exit 1
        fi
        grep -q 'ennoix-config-loaded-ok' log || { echo "missing success marker:"; cat log; exit 1; }
        touch $out
      '';
    };
  };

  default = composeManyExtensions [
    fixes
    top-level
    python-packages
    verification
    ennoix
  ];

in
{
  inherit
    default
    ennoix
    fixes
    python-packages
    top-level
    ;
}
