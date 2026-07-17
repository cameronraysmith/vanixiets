# nixos-facter 0.4.4 aborts on MacBookPro14,1 SPI touchpad ("unsupported bus type: Spi")
#
# Fix: nix-community/nixos-facter PR #672 (issue #339), unreleased as of 0.4.4
# Reference: https://github.com/nix-community/nixos-facter/pull/672
# TODO: Remove when a nixos-facter release > 0.4.4 carrying this fix reaches nixpkgs
# Date added: 2026-07-17
#
# Guarded to Linux: the fix branch exposes no darwin package, and the only
# consumer is bare-metal x86_64-linux hardware detection (pyrite). The overlay
# applies fleet-wide via base-defaults.nix, so darwin laptops keep stock 0.4.4.
{ ... }:
{
  nixpkgsOverlays = [
    (
      final: prev:
      prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
        nixos-facter = prev.nixos-facter.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (prev.fetchpatch {
              name = "spi-touchpad-bus.patch";
              url = "https://github.com/nix-community/nixos-facter/commit/4f27becd3b432eabf4f7faca7f14025c69684130.patch";
              hash = "sha256-QOpZgXdxV0q46TMt3SErb4mLekgt0LoYxH/tJlYhtU0=";
            })
          ];
        });
      }
    )
  ];
}
