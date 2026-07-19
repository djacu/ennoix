# The ENTIRE catalog enabled — build coverage. Enables are derived
# structurally from the catalog directory names (dir name IS the
# usePackage key); never hand-listed.
{ ennoixEval, lib }:
(ennoixEval [
  {
    usePackage =
      lib.genAttrs
        (builtins.attrNames (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../../../modules/catalog)
        ))
        (_: {
          enable = true;
        });
  }
]).build.package
