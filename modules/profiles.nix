# The `profiles` namespace: each profile is a directory under modules/profiles
# whose profile.nix gates a bundle of usePackage settings behind its enable.
{ lib, ... }:
{
  options.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options.enable = lib.mkEnableOption "the ${name} profile";
        }
      )
    );
    default = { };
  };
}
