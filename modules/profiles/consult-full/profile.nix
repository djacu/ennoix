# consult's complete README binding surface (the "full" tier), merged onto the
# base six. All at mkCatalogDefault so bind/bindLocal/config MERGE with the base
# consult module. `[remap Info-search]` is omitted (the bind emitter can't
# express a remap vector); consult-info stays on C-c i. consult-locate needs a
# system-provided locate db and binary; consult-git-grep uses ambient `git`.
{
  config,
  lib,
  mkCatalogDefault,
  pkgs,
  ...
}:
lib.mkIf config.profiles.consult-full.enable {
  usePackage.consult.enable = lib.mkDefault true;
  usePackage.consult.bind = mkCatalogDefault {
    "C-c M-x" = "consult-mode-command";
    "C-c h" = "consult-history";
    "C-c k" = "consult-kmacro";
    "C-c m" = "consult-man";
    "C-c i" = "consult-info";
    "C-x M-:" = "consult-complex-command";
    "C-x 4 b" = "consult-buffer-other-window";
    "C-x 5 b" = "consult-buffer-other-frame";
    "C-x t b" = "consult-buffer-other-tab";
    "C-x r b" = "consult-bookmark";
    "C-x p b" = "consult-project-buffer";
    "M-#" = "consult-register-load";
    "M-'" = "consult-register-store";
    "C-M-#" = "consult-register";
    "M-g e" = "consult-compile-error";
    "M-g r" = "consult-grep-match";
    "M-g f" = "consult-flymake";
    "M-g M-g" = "consult-goto-line";
    "M-g o" = "consult-outline";
    "M-g m" = "consult-mark";
    "M-g k" = "consult-global-mark";
    "M-g I" = "consult-imenu-multi";
    "M-s d" = "consult-find";
    "M-s c" = "consult-locate";
    "M-s g" = "consult-grep";
    "M-s G" = "consult-git-grep";
    "M-s L" = "consult-line-multi";
    "M-s k" = "consult-keep-lines";
    "M-s u" = "consult-focus-lines";
    "M-s e" = "consult-isearch-history";
  };
  usePackage.consult.bindLocal = mkCatalogDefault {
    isearch-mode-map = {
      "M-e" = "consult-isearch-history";
      "M-s e" = "consult-isearch-history";
      "M-s L" = "consult-line-multi";
    };
    minibuffer-local-map = {
      "M-s" = "consult-history";
      "M-r" = "consult-history";
    };
  };
  usePackage.consult.config = mkCatalogDefault ''
    (consult-customize
     consult-theme :preview-key '(:debounce 0.2 any)
     consult-git-grep consult-grep consult-man consult-bookmark
     consult-recent-file consult-xref
     consult-source-bookmark consult-source-file-register
     consult-source-recent-file consult-source-project-recent-file
     :preview-key '(:debounce 0.4 any))'';
  usePackage.consult.runtimePackages = mkCatalogDefault [
    pkgs.gnugrep
    pkgs.findutils
  ];
}
