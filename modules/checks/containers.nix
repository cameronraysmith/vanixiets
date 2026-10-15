# Container image build-realization checks.
#
# Each fd/rg container variant is a distinct leaf derivation not reachable from
# any machine toplevel or home activationPackage, so wiring them individually
# preserves coverage of the image-build closure. Per-package bindings follow
# ironstar's package-as-check inheritance idiom (modules/rust.nix:249-251)
# rather than aggregating into a linkFarm.
#
# Bound on x86_64-linux only: aarch64-darwin exposes these same x86_64-linux
# derivations under legacyPackages, so a darwin binding would duplicate them.
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
