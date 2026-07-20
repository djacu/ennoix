{ mkCatalogDefault, ... }:
{
  # C-. / C-; are embark's canonical defaults but don't reach Emacs in a
  # terminal, and C-. is intercepted by GNOME emoji input; override `bind` on
  # affected setups. (C-; also clashes with flyspell-mode.) The display-buffer
  # entry hides the Embark Collect buffers' mode line (embark README).
  usePackage.embark = {
    init = mkCatalogDefault "(setq prefix-help-command #'embark-prefix-help-command)";
    config = mkCatalogDefault ''
      (add-to-list 'display-buffer-alist
                   '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                     nil
                     (window-parameters (mode-line-format . none))))'';
    bind = mkCatalogDefault {
      "C-." = "embark-act";
      "C-;" = "embark-dwim";
      "C-h B" = "embark-bindings";
    };
  };
}
