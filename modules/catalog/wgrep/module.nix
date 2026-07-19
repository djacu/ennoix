{ mkCatalogDefault, ... }:
{
  # Self-installing (grep-setup-hook binds C-c C-p); nothing to configure.
  usePackage.wgrep.demand = mkCatalogDefault true;
}
