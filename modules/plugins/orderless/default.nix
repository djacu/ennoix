{ mkPlugin }:
mkPlugin {
  name = "orderless";
  extraConfig = "(setq completion-styles '(orderless basic) completion-category-overrides '((file (styles basic partial-completion))))";
}
