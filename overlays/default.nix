inputs:
let

  # inherits

  inherit (builtins)
    attrValues
    ;

  inherit (inputs.nixpkgs)
    lib
    ;

  inherit (lib.fixedPoints)
    composeManyExtensions
    ;

  inherit (inputs.self.library)
    genDirectories
    ;

  # overlays

  allLocalOverlays = (genDirectories ../overlays) (
    dir: final: prev: {
      "${dir}" = final.callPackage ../overlays/${dir}/overlay.nix { };
    }
  );

  allLocalPackages = (genDirectories ../packages) (
    dir: final: prev: {
      "${dir}" = final.callPackage ../packages/${dir}/package.nix { };
    }
  );

  default = composeManyExtensions ((attrValues allLocalOverlays) ++ (attrValues allLocalPackages));

in
allLocalOverlays // allLocalPackages // { inherit default; }
