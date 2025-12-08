# Overlay composition using dendritic list concatenation
#
# This module composes all overlays from the auto-discovered flake.nixpkgsOverlays list
# into a single flake.overlays.default for use in machine configurations.
#
# Architecture:
# - overlays/*.nix each append to flake.nixpkgsOverlays list (NixOS module system feature)
# - This module composes that list with lib.composeManyExtensions
# - External overlays and custom packages merged in composition order
#
# Machine configs reference: nixpkgs.overlays = [ inputs.self.overlays.default ];
#
{
  config,
  lib,
  withSystem,
  ...
}:
{
  # Compose all overlays into flake.overlays.default
  flake.overlays.default =
    final: prev:
    let
      # Internal overlays auto-collected via list concatenation
      # overlays/*.nix modules append to this list automatically
      internalOverlays = lib.composeManyExtensions config.flake.nixpkgsOverlays;

      # Custom packages from pkgs-by-name
      # Provides: Project-specific packages (ccstatusline, etc.)
      # Use withSystem to access perSystem packages for the target system
      customPackages = withSystem prev.stdenv.hostPlatform.system (
        { config, ... }: config.packages or { }
      );
    in
    # Compose all (order matters!)
    # 1. Internal overlays (channels, hotfixes, overrides, nvim-treesitter, nuenv) via composeManyExtensions
    # 2. Custom packages (standalone derivations)
    (internalOverlays final prev) // customPackages;
}
