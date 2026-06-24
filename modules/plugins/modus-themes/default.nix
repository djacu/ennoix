{ mkPlugin }:
mkPlugin {
  name = "modus-themes";
  extraConfig = "(load-theme 'modus-operandi :no-confirm)";
}
