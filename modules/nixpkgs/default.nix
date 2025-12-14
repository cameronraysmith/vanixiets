# nixpkgs integration + overlay export
#
# - Integration (this file) imports submodules
# - Configuration (per-system.nix) configures perSystem pkgs
# - Overlays (overlays/*.nix) append to flake.nixpkgsOverlays list
# - Composition (compose.nix) merges list into flake.overlays.default
# - Option declaration (overlays-option.nix) enables list concatenation
#
# Machine configs reference: nixpkgs.overlays = [ inputs.self.overlays.default ];
{ inputs, ... }:
{
  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
    ./overlays-option.nix
    ./per-system.nix
    ./compose.nix
  ];
}
