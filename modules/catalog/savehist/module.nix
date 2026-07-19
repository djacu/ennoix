{ mkCatalogDefault, ... }:
{
  usePackage.savehist = {
    package = mkCatalogDefault null; # ships with emacs; install nothing
    init = mkCatalogDefault "(savehist-mode 1)";
  };
}
