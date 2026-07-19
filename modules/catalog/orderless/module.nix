{ mkCatalogDefault, ... }:
{
  usePackage.orderless.config = mkCatalogDefault "(setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))";
}
