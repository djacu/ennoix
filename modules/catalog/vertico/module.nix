{ mkCatalogDefault, ... }:
{
  usePackage.vertico.init = mkCatalogDefault "(vertico-mode 1)";
}
