# Multi-channel nixpkgs access layer
#
# Flake-parts module exporting channel overlays through nixpkgsOverlaysByName
#
# Adapted from _overlays/inputs.nix
#
# Adds to the package set:
#   - inputs: Raw flake inputs reference
#   - nixpkgs: Main nixpkgs (unstable) - for reference
#   - stable: OS-specific stable nixpkgs (parked: commented out below)
#   - unstable: Explicit unstable nixpkgs (same as nixpkgs, for clarity)
#
# Usage in other overlays or configurations:
#   pkgs.unstable.packageName     # Explicit unstable reference
#
{ inputs, ... }:
{
  nixpkgsOverlaysByName.channels = [
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

        # ~keep Restore with nixpkgs-{darwin,linux}-stable in flake.nix inputs.
        # Stable channel (OS-specific: darwin-stable or linux-stable)
        # stable =
        #   if prev.stdenv.hostPlatform.isDarwin then
        #     import inputs.nixpkgs-darwin-stable nixpkgsConfig
        #   else
        #     import inputs.nixpkgs-linux-stable nixpkgsConfig;

        # Explicit unstable (for clarity when pulling from unstable)
        unstable = import inputs.nixpkgs nixpkgsConfig;
      }
    )
  ];
}
