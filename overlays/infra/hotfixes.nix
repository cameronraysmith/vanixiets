# Platform-specific hotfixes for broken unstable packages
#
# Strategy: Selectively inherit from final.stable when unstable packages break
# This avoids flake.lock rollbacks that affect ALL packages
#
# Pattern:
# - Use final.stable.packageName for stable fallback
# - Document with hydra link: https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM
# - Remove when upstream fixes land in unstable
#
# Prefer this over:
# - Flake.lock rollback (affects all packages)
# - Inline overrides in default.nix (clutters overlay)
#
final: prev:
{
  # Cross-platform hotfixes (all systems)
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-darwin
    # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.x86_64-linux
    # https://hydra.nixos.org/job/nixpkgs/trunk/micromamba.aarch64-linux
    # Error: fmt library compatibility issue across all platforms
    # - Formatter<fs::u8path> missing const qualifier on format method
    # - Darwin: clang 21.x exposes issue immediately
    # - Linux: Same underlying fmt library issue affects all platforms
    # - Breaks in unstable after 2025-09-28 (last successful hydra build)
    # - Stable version pulls compatible ghc_filesystem, solving both issues
    # - CI confirmed failure on Linux builds, not just Darwin
    # TODO: Remove when fmt compatibility fixed upstream
    # Added: 2025-10-13, expanded to all platforms: 2025-10-14
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
  # (Add as needed)
})
