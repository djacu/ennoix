{ mkCatalogDefault, ... }:
{
  usePackage.which-key = {
    package = mkCatalogDefault null; # built into emacs >= 30
    init = mkCatalogDefault "(which-key-mode 1)";
  };
}
