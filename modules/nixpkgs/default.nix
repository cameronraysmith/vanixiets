# nixpkgs integration + overlay export
#
# - Integration (this file) imports the pkgs-by-name-for-flake-parts flakeModule
# - Configuration (per-system.nix) configures perSystem pkgs
# - Overlays (overlays/*.nix) add to nixpkgsOverlaysByName under their names
# - Composition (compose.nix) orders them and folds them into flake.overlays.default
# - Option declaration (overlays-option.nix) declares both options
#
# Sibling modules (overlays-option.nix, per-system.nix, compose.nix) are
# auto-discovered by import-tree (see flake.nix). Machines and standalone homes
# consume the composed result through the per-system fleetPkgs instance
# (base-defaults.nix).
{ inputs, ... }:
{
  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
  ];
}
