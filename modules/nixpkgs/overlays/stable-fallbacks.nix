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
          # https://hydra.nixos.org/job/nixpkgs/trunk/argocd.aarch64-darwin
          # https://hydra.nixos.org/job/nixpkgs/trunk/argocd.x86_64-linux
          # https://hydra.nixos.org/job/nixpkgs/trunk/argocd.aarch64-linux
          # Error: argocd-ui yarn.lock mismatch in yarnConfigHook
          # - Offline cache yarn.lock diverges from source yarn.lock
          # - Version bumps in express, body-parser, cookie, finalhandler, etc.
          # - Upstream nixpkgs needs to regenerate the yarn offline cache
          # TODO: Remove when argocd-ui yarn.lock fixed upstream
          # Added: 2026-02-15
          argocd

          # https://hydra.nixos.org/job/nixpkgs/trunk/dvc.aarch64-darwin
          # https://hydra.nixos.org/job/nixpkgs/trunk/dvc.x86_64-linux
          # https://hydra.nixos.org/job/nixpkgs/trunk/dvc.aarch64-linux
          # Error: dvc-s3 3.3.0 postPatch fails - aiobotocore[boto3] pattern
          # removed from upstream pyproject.toml but nixpkgs patch still expects it
          # - Pinning entire dvc (not just dvc-s3) because dvc.override binds
          #   to its own python package set
          # - Upstream fix pending: nixpkgs PR #493981
          # TODO: Remove when nixpkgs PR #493981 merges
          # Added: 2026-02-27
          dvc

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
          # https://hydra.nixos.org/job/nixpkgs/trunk/colima.aarch64-darwin
          # colima 0.10.1 and qemu 10.2.1 pass on Hydra but nixpkgs rev is ahead of
          # cached evaluation — qemu rebuilds from source (~20min)
          # TODO: Remove when Hydra aarch64-darwin eval catches up to flake.lock nixpkgs rev
          # Added: 2026-03-07
          colima
          lima

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
