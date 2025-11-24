# perSystem nixpkgs configuration
#
# Separated from default.nix for single responsibility
# This file configures pkgs for perSystem (checks, packages, devShells, etc.)
#
# Dendritic pattern: Uses config.flake.nixpkgsOverlays for overlay composition
# overlays/*.nix modules append to this list automatically via import-tree
{
  inputs,
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      # Configure nixpkgs with dendritic overlay architecture
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # Overlay composition from flake.nixpkgsOverlays list
        # Auto-populated by overlays/*.nix via dendritic list concatenation
        overlays =
          # Internal overlays (channels, hotfixes, overrides, nvim-treesitter-main)
          config.flake.nixpkgsOverlays
          # External overlays (nuenv)
          ++ [
            inputs.nuenv.overlays.nuenv
          ];
      };
    in
    {
      # Provide pkgs to perSystem context
      _module.args.pkgs = pkgs;

      # Expose pkgs to flake level for clan-core consumption
      # Clan-core looks for flake.legacyPackages.${system} when building machines
      # This ensures our allowUnfree config propagates to clan-managed NixOS systems
      legacyPackages = pkgs;

      # Custom packages via pkgs-by-name auto-discovery
      # Provides: Custom derivations (ccstatusline, etc.)
      # Standalone: No dependencies on other overlay layers
      pkgsDirectory = ../../pkgs/by-name;
    };
}
