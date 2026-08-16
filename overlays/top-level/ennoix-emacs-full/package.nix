# The ENTIRE catalog enabled — build coverage. Enables are derived
# structurally from the catalog directory names (dir name IS the
# usePackage key); never hand-listed. The consult-full profile is enabled
# explicitly (the structural catalog enable does not reach profiles).
# NOTE: flakes copy the git INDEX — `git add` new catalog entries or local
# -full builds will include drafts that CI (clean checkout) will not see.
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
  { profiles.consult-full.enable = true; }
]).build.package
