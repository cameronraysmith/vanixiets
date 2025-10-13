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
  # Cross-platform hotfixes
  # Example:
  # inherit (final.stable)
  #   # https://hydra.nixos.org/job/nixpkgs/trunk/packageName.aarch64-linux
  #   packageName
  #   ;
}
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  # Darwin-wide hotfixes (both aarch64 and x86_64)
  # Example:
  # inherit (final.stable)
  #   # https://hydra.nixos.org/job/nixpkgs/trunk/time.aarch64-darwin
  #   time
  #   ;
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
