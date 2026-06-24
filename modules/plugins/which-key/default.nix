{ mkPlugin }:
mkPlugin {
  name = "which-key";
  builtIn = true;
  init = "(which-key-mode 1)";
}
