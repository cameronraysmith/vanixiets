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
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 34 s, slowest 1433 s, all 18 runs 2026-08-29..2026-11-11
        fdContainer-aarch64.class = "small";
        # nixbot: median 37 s, slowest 181 s, all 18 runs 2026-08-29..2026-11-11
        fdContainer-x86_64.class = "small";
        # nixbot: median 10 s, slowest 1404 s, all 19 runs 2026-09-04..2026-11-11
        rgContainer-aarch64.class = "small";
        # nixbot: median 3.9 s, slowest 160 s, all 15 runs 2026-09-04..2026-11-11
        rgContainer-x86_64.class = "small";
      };
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
