{ mkCatalogDefault, ... }:
{
  # :bind defers magit (autoloads on C-x g; not eager-loaded at startup).
  usePackage.magit.bind = mkCatalogDefault {
    "C-x g" = "magit-status";
  };
}
