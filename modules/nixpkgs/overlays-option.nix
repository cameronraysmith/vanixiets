# Declare nixpkgsOverlays as a typed internal accumulator option
#
# Sibling overlay files in modules/nixpkgs/overlays/ contribute via
# `nixpkgsOverlays = [ (final: prev: { ... }) ];`. The composition step in
# modules/nixpkgs/compose.nix folds the list into flake.overlays.default.
#
# This option lives at the top level (not under `flake.*`) and is marked
# `internal = true` so it does not surface as a flake output. The pattern
# mirrors the precedent set by flake-parts core for `allSystems`
# (modules/perSystem.nix lines 141-145 in nix-workspace/flake-parts).
{ lib, ... }:
{
  options.nixpkgsOverlays = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    default = [ ];
    internal = true;
    description = ''
      Internal accumulator for nixpkgs overlays composed into
      flake.overlays.default by modules/nixpkgs/compose.nix. Sibling overlay
      files in modules/nixpkgs/overlays/ contribute via
      `nixpkgsOverlays = [ (final: prev: { ... }) ];`. Not a flake output.
    '';
  };
}
