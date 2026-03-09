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
        inherit (final.stable)
          # https://hydra.nixos.org/job/nixpkgs/trunk/google-cloud-sdk.aarch64-darwin
          # https://hydra.nixos.org/job/nixpkgs/trunk/google-cloud-sdk.x86_64-linux
          # Error: python3.12-freezegun test_asyncio_sleeping_not_affected_by_freeze_time
          # flaky timing assertion in transitive test dep of google-cloud-sdk's python312 env
          # - Linux: separate autoPatchelfHook issue (pyelftools, added 2025-11-19)
          # - Darwin: freezegun test failure blocks full python3.12 env rebuild
          # TODO: Remove when freezegun test fixed upstream or google-cloud-sdk bumps python
          # Added: 2026-03-07
          google-cloud-sdk

          ;
      }
      // (prev.lib.optionalAttrs prev.stdenv.isDarwin {
        # Darwin-wide stable fallbacks (both aarch64 and x86_64)
        inherit (final.stable)
          # https://hydra.nixos.org/job/nixpkgs/trunk/uv.aarch64-darwin
          # Hydra has uv 0.10.6 cached; nixpkgs has 0.10.8 uncached on aarch64-darwin
          # Rebuilds full Rust toolchain from source
          # TODO: Remove when Hydra aarch64-darwin builds uv 0.10.8+
          # Added: 2026-03-07
          uv

          ;
      })
      // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-darwin") {
        # x86_64-darwin specific stable fallbacks
        # Example:
        # ncdu = final.empty or (prev.runCommand "empty-ncdu" {} "mkdir -p $out");
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
