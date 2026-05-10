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
        # (Add as needed)
      })
      // (prev.lib.optionalAttrs prev.stdenv.isLinux {
        # Linux-wide stable fallbacks
        # (Add Linux-specific stable fallbacks here as needed)
      })
    )
  ];
}
