{ inputs, ... }:
{
  nixpkgsOverlays = [
    inputs.cognee-nix.overlays.default
  ];
}
