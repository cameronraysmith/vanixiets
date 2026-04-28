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

        # direnv: pinned to stable while local rebuild on our locked nixpkgs
        # rev fails. Hydra builds direnv cleanly at trunk, but our pin lags
        # the channel and the cached derivation does not match our closure,
        # forcing a local rebuild that fails in this repo's environment.
        # Hydra: https://hydra.nixos.org/job/nixpkgs/unstable/direnv.aarch64-darwin
        # TODO: Remove when the nixpkgs pin advances to a rev whose direnv
        # derivation matches Hydra's cache.
        # Date added: 2026-04-28
        direnv = final.stable.direnv;

        # quarto: same channel-lag situation as direnv. Hydra builds quarto
        # cleanly at trunk; our locked rev's derivation closure differs and
        # is not on cache.nixos.org, so activation falls back to a local
        # rebuild that fails on aarch64-darwin.
        # Hydra: https://hydra.nixos.org/job/nixpkgs/unstable/quarto.aarch64-darwin
        # TODO: Remove when the nixpkgs pin advances to a rev whose quarto
        # derivation matches Hydra's cache.
        # Date added: 2026-04-28
        quarto = final.stable.quarto;
      })
      // (prev.lib.optionalAttrs prev.stdenv.isLinux {
        # Linux-wide stable fallbacks
        # (Add Linux-specific stable fallbacks here as needed)
      })
    )
  ];
}
