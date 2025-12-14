# Multi-channel nixpkgs access layer
#
# Flake-parts module exporting channel overlays via list concatenation
#
# Adapted from _overlays/inputs.nix
#
# Exports to flake.nixpkgsOverlays list:
#   - inputs: Raw flake inputs reference
#   - nixpkgs: Main nixpkgs (unstable) - for reference
#   - patched: nixpkgs with patches applied (empty in test-clan)
#   - stable: OS-specific stable nixpkgs (darwin-stable or linux-stable)
#   - unstable: Explicit unstable nixpkgs (same as nixpkgs, for clarity)
#
# Usage in other overlays or configurations:
#   pkgs.stable.packageName       # Get package from stable channel
#   pkgs.unstable.packageName     # Explicit unstable reference
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (
      final: prev:
      let
        # Shared nixpkgs configuration
        # Must match configuration in modules/nixpkgs/per-system.nix
        nixpkgsConfig = {
          system = prev.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
          };
        };
      in
      {
        # Raw inputs access
        inherit inputs;

        # Main nixpkgs (unstable) - imported for reference
        # Note: prev is already from nixpkgs, this is explicit
        nixpkgs = import inputs.nixpkgs nixpkgsConfig;

        # Patched nixpkgs (empty patches in test-clan, vanixiets uses vanixiets/patches.nix)
        patched = import (prev.applyPatches {
          name = "nixpkgs-patched";
          src = inputs.nixpkgs.outPath;
          patches = [ ]; # Empty in test-clan
        }) nixpkgsConfig;

        # Stable channel (OS-specific: darwin-stable or linux-stable)
        # Direct conditional based on system (test-clan doesn't have lib'.systemInput)
        stable =
          if prev.stdenv.isDarwin then
            import inputs.nixpkgs-darwin-stable nixpkgsConfig
          else
            import inputs.nixpkgs-linux-stable nixpkgsConfig;

        # Explicit unstable (for clarity when pulling from unstable)
        unstable = import inputs.nixpkgs nixpkgsConfig;
      }
    )
  ];
}
