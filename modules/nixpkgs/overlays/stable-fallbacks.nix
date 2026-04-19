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
  flake.nixpkgsOverlays = [
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

        # atuin: pinned to stable while unstable build/cache is broken
        # Hydra: https://hydra.nixos.org/job/nixpkgs/trunk/atuin.aarch64-darwin
        # TODO: Remove when upstream fix lands in unstable
        # Date added: 2026-04-19
        atuin = final.stable.atuin;

        # dvc: pinned to stable while unstable build is broken
        # Hydra: https://hydra.nixos.org/job/nixpkgs/unstable/python313Packages.dvc.aarch64-darwin
        # Failing build: https://hydra.nixos.org/build/326554391
        # TODO: Remove when upstream fix lands in unstable
        # Date added: 2026-04-19
        dvc = final.stable.dvc;
      })
      // (prev.lib.optionalAttrs prev.stdenv.isLinux {
        # Linux-wide stable fallbacks
        # (Add Linux-specific stable fallbacks here as needed)
      })
    )
  ];
}
