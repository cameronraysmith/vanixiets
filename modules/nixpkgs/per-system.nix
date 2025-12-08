# perSystem nixpkgs configuration
#
# configures pkgs for flake-parts perSystem (checks, packages, devShells, etc.)
#
# Use config.flake.nixpkgsOverlays for overlay composition
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
      # Configure nixpkgs with overlays
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # Overlay composition from flake.nixpkgsOverlays list
        # Auto-populated by overlays/*.nix modules (including nuenv.nix)
        overlays = config.flake.nixpkgsOverlays;
      };
    in
    {
      # Provide pkgs to perSystem context
      _module.args.pkgs = pkgs;

      # Expose pkgs to flake level for clan-core consumption
      # Clan-core looks for flake.legacyPackages.${system} when building machines
      # This ensures our allowUnfree config propagates to clan-managed NixOS systems
      # Use lib.mkForce to override pkgs-by-name-for-flake-parts legacyPackages
      # (pkgs-by-name uses legacyPackages for its package scope, but we need full nixpkgs here)
      legacyPackages = lib.mkForce pkgs;

      # Custom packages via pkgs-by-name auto-discovery
      # Integrates custom derivations without depending on other overlay layers
      pkgsDirectory = ../../pkgs/by-name;
    };
}
