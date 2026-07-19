# The flagship `nix run` demo: curated starter (the Phase-0 seven,
# hand-listed — the flagship's contents are editorial).
{ ennoixEval }:
(ennoixEval [
  {
    usePackage = {
      consult.enable = true;
      embark.enable = true;
      embark-consult.enable = true;
      magit.enable = true;
      marginalia.enable = true;
      modus-themes.enable = true;
      orderless.enable = true;
      savehist.enable = true;
      vertico.enable = true;
      wgrep.enable = true;
      which-key.enable = true;
    };
  }
]).build.package
