{ mkCatalogDefault, ... }:
{
  # Self-installing (grep-setup-hook binds C-c C-p). wgrep-auto-save-buffer
  # makes C-c C-c (wgrep-finish-edit) write edits straight to disk — a
  # deliberate deviation from wgrep's default (nil), so bulk cross-file edits
  # persist without a separate C-x s.
  usePackage.wgrep = {
    demand = mkCatalogDefault true;
    custom = mkCatalogDefault { wgrep-auto-save-buffer = true; };
  };
}
