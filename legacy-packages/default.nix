inputs:
inputs.self.library.supportedSystems (
  system:
  import inputs.nixpkgs {
    inherit system;
    overlays = [ inputs.self.overlays.default ];
  }
)
