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

        # d2: pinned to stable while the unstable closure pulls libdrm-2.4.131
        # transitively via mesa-libgbm. libdrm declares meta.platforms
        # excluding darwin in the locked nixpkgs rev, so d2.drvPath eval-fails
        # on aarch64-darwin even though Hydra's d2 builds cleanly at trunk
        # (the cached d2 derivation does not match our locked rev's closure).
        # Hydra: https://hydra.nixos.org/job/nixpkgs/unstable/d2.aarch64-darwin
        # TODO: Remove when the mesa-libgbm/libdrm closure issue is resolved
        # upstream and our locked nixpkgs no longer pulls libdrm into d2.
        # Date added: 2026-04-28
        d2 = final.stable.d2;
      })
      // (prev.lib.optionalAttrs prev.stdenv.isLinux {
        # Linux-wide stable fallbacks
        # (Add Linux-specific stable fallbacks here as needed)
      })
    )
  ];
}
