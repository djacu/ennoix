{ mkCatalogDefault, ... }:
{
  # embark-consult self-registers all integration at load; :after is all
  # ennoix needs (embark also auto-loads it after consult).
  usePackage.embark-consult.after = mkCatalogDefault [
    "embark"
    "consult"
  ];
}
