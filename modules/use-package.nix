# The single flat namespace: usePackage.<name> — keys are emacs
# feature/package names; freeform (any key is a fully-typed entry).
{ lib, pkgs, ... }:
{
  options.usePackage = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [ ./lib/use-package-type.nix ];
        # Required: neither top-level specialArgs nor _module.args reach
        # submodules (verified in bare evalModules AND under NixOS).
        specialArgs = { inherit pkgs; };
        # REQUIRED: the type declares an option named `config`, and entries
        # set it in shorthand (usePackage.foo = { config = "..."; }). Raw
        # submoduleWith defaults shorthandOnlyDefinesConfig = false, which
        # parses such entries as full modules and breaks them
        # (types.submodule hardcodes true; verified).
        shorthandOnlyDefinesConfig = true;
      }
    );
    default = { };
    description = "use-package entries emitted into the generated init.";
  };
}
