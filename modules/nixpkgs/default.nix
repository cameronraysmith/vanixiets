# nixpkgs integration + overlay export
#
# - Integration (this file) imports the pkgs-by-name-for-flake-parts flakeModule
# - Configuration (per-system.nix) configures perSystem pkgs
# - Overlays (overlays/*.nix) append to nixpkgsOverlays list
# - Composition (compose.nix) merges list into flake.overlays.default
# - Option declaration (overlays-option.nix) enables list concatenation
#
# Sibling modules (overlays-option.nix, per-system.nix, compose.nix) are
# auto-discovered by import-tree (see flake.nix). Machine configs reference
# the composed result via `nixpkgs.overlays = [ inputs.self.overlays.default ]`.
{ inputs, ... }:
{
  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
  ];
}
