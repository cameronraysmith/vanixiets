# Per-package build modifications
#
# Flake-parts module exporting override overlays via list concatenation
#
# Adapted from _overlays/overrides.nix
#
# This file contains per-package overrideAttrs customizations:
# - Test disabling
# - Build flag modifications
# - Patch applications
#
# vanixiets has auto-import infrastructure but no actual overrides yet.
# This is a placeholder for future package build modifications.
#
# See vanixiets overlays README.md for when to use overrides vs stable-fallbacks vs patches
#
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # Package-specific overrideAttrs customizations
      #
      # Example override (if needed):
      # somePackage = prev.somePackage.overrideAttrs (oldAttrs: {
      #   doCheck = false;  # Disable tests
      # });
    })
  ];
}
