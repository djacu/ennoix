{ mkCatalogDefault, ... }:
{
  # Deliberately a PACKAGE (package defaults to pkgs.emacsPackages.modus-themes):
  # emacs bundles the modus library only under etc/themes (off load-path), so
  # use-package's require fails for the built-in; the package also keeps the
  # entry overridable. See the builtIn-vs-package policy record.
  usePackage.modus-themes.config = mkCatalogDefault "(load-theme 'modus-operandi :no-confirm)";
}
