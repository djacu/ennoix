{ pkgs, mkCatalogDefault, ... }:
{
  # consult-ripgrep shells out to `rg`, so ripgrep is bundled onto the built
  # emacs's PATH (the first runtimePackages use). Standard-key rebindings
  # (C-x b, M-y, M-g g) are drop-in enhanced replacements per upstream.
  usePackage.consult = {
    init = mkCatalogDefault ''
      (advice-add #'register-preview :override #'consult-register-window)
      (setq register-preview-delay 0.5)
      (setq xref-show-xrefs-function #'consult-xref
            xref-show-definitions-function #'consult-xref)'';
    config = mkCatalogDefault "(consult-customize consult-ripgrep :preview-key '(:debounce 0.4 any))";
    custom = mkCatalogDefault { consult-narrow-key = ''"<"''; };
    bind = mkCatalogDefault {
      "C-x b" = "consult-buffer";
      "M-y" = "consult-yank-pop";
      "M-s l" = "consult-line";
      "M-s r" = "consult-ripgrep";
      "M-g g" = "consult-goto-line";
      "M-g i" = "consult-imenu";
    };
    bindLocal = mkCatalogDefault {
      isearch-mode-map = {
        "M-s l" = "consult-line";
      };
    };
    runtimePackages = mkCatalogDefault [ pkgs.ripgrep ];
  };
}
