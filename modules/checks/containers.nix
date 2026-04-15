# Container image build-realization checks.
#
# Each fd/rg container variant is a distinct leaf derivation not reachable from
# any machine toplevel or home activationPackage, so wiring them individually
# preserves coverage of the image-build closure. Per-package bindings follow
# ironstar's package-as-check inheritance idiom (modules/rust.nix:249-251)
# rather than aggregating into a linkFarm.
#
# Phase 1 (nix-144.1) binds on x86_64-linux only. aarch64-darwin exposes the
# packages via pkgsCross + rosetta-builder, but evaluating those during
# CI requires the rosetta emulator which is not assumed present here.
# Manifest push variants (fdManifest*, rgManifest*) are intentionally dropped
# as effect-input-wire per the coverage map (impure ghcr.io push).
{ lib, ... }:
{
  perSystem =
    {
      self',
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit (self'.packages)
          fdContainer-aarch64
          fdContainer-x86_64
          rgContainer-aarch64
          rgContainer-x86_64
          ;
      };
    };
}
