# Platform-specific hotfixes for broken unstable packages
#
# flake-parts module exporting hotfix overlays via list concatenation
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
        # Cross-platform hotfixes (all systems)
        inherit (final.stable)
          # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-darwin
          # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.x86_64-linux
          # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-linux
          # Error: fmt library compatibility issue across all platforms
          # - Formatter<fs::u8path> missing const qualifier on format method
          # - Darwin: clang 21.x build fails
          # - Linux: Same underlying fmt library issue affects all platforms
          # - Breaks in unstable after 2025-09-28 (last successful hydra build)
          # - Stable version pulls compatible ghc_filesystem
          # - CI confirmed failure on both Linux and Darwin
          # TODO: Remove when fmt compatibility fixed upstream
          # Added: 2025-10-14
          micromamba
          ;
      }
      // (prev.lib.optionalAttrs prev.stdenv.isDarwin {
        # Darwin-wide hotfixes (both aarch64 and x86_64)
        # (Add Darwin-specific hotfixes here as needed)
      })
      // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-darwin") {
        # x86_64-darwin specific hotfixes
        # Example:
        # ncdu = final.empty or (prev.runCommand "empty-ncdu" {} "mkdir -p $out");
      })
      // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "aarch64-darwin") {
        # aarch64-darwin specific hotfixes
        # (Add as needed)
      })
      // (prev.lib.optionalAttrs prev.stdenv.isLinux {
        # Linux-wide hotfixes
        inherit (final.stable)
          # https://hydra.nixos.org/job/nixpkgs/trunk/google-cloud-sdk.x86_64-linux
          # Error: auto-patchelf missing pyelftools on rosetta-builder
          # - Component builds (withExtraComponents) fail with ImportError
          # - Basic google-cloud-sdk works, components use autoPatchelfHook
          # - auto-patchelf has pyelftools in buildInputs, needs propagatedBuildInputs
          # - Stable version is cached and proven working
          # TODO: Remove when auto-patchelf upstream fix lands (nixpkgs PR pending)
          # Added: 2025-11-19
          google-cloud-sdk
          ;
      })
    )
  ];
}
