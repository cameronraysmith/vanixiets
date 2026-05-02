# Platform-specific stable fallbacks for broken unstable packages
#
# flake-parts module exporting stable fallback overlays via list concatenation
#
# Selectively inherits from final.stable when unstable packages break
#
# - Use final.stable.packageName for stable fallback
# - Document build failure with hydra job link from https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM
# - Should be removed when upstream fixes land in unstable
#
# This is preferred over flake.lock rollback or inline overrides in nixpkgs.nix
#
{ ... }:
{
  nixpkgsOverlays = [
    (
      final: prev:
      {
        # Cross-platform stable fallbacks (all systems)
        # (Add as needed)
      }
      // (prev.lib.optionalAttrs prev.stdenv.isDarwin {
        # Darwin-wide stable fallbacks (aarch64-only fleet)
        # (Add as needed)
      })
      // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "aarch64-darwin") {
        # aarch64-darwin specific stable fallbacks

        # d2: pinned to stable because the unstable closure pulls
        # libdrm-2.4.131 transitively via mesa-libgbm, and libdrm's meson
        # build refuses to configure on darwin:
        #   meson.build:38:2: ERROR: Problem encountered: unsupported OS: darwin
        # Even though Hydra publishes some d2 derivation for aarch64-darwin,
        # our locked rev's d2 evaluates to a different outPath whose closure
        # includes libdrm, so activation triggers a local rebuild that can
        # never succeed. The stable fallback's d2 closure does not pull
        # libdrm and is cache-resident.
        # Hydra: https://hydra.nixos.org/job/nixpkgs/unstable/d2.aarch64-darwin
        # TODO: Remove when libdrm gains darwin support upstream OR nixpkgs
        # stops pulling libdrm into d2's closure on darwin.
        # Date verified broken: 2026-05-02 (nh darwin switch on stibnite)
        d2 = final.stable.d2;
      })
      // (prev.lib.optionalAttrs prev.stdenv.isLinux {
        # Linux-wide stable fallbacks
        # (Add Linux-specific stable fallbacks here as needed)
      })
    )
  ];
}
