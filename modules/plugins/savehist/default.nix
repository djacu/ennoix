{ mkPlugin }:
mkPlugin {
  name = "savehist";
  builtIn = true;
  init = "(savehist-mode 1)";
}
