# Experimental/debug packages for local development
#
# These packages are:
# - Available for manual builds: nix build .#debug.holos
# - NOT built automatically by omnix ci (legacyPackages.debug is ignored by devour-flake)
# - NOT in overlay, so they don't override nixpkgs or flake input packages
# - Can be promoted to active use by moving to overlays/packages/
#
# To use in home-manager or nixos: pkgs.legacyPackages.${system}.debug.holos
# (The ugly path is intentional to prevent accidental use)
#
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      legacyPackages = {
        debug = pkgs.lib.packagesFromDirectoryRecursive {
          callPackage = pkgs.lib.callPackageWith pkgs;
          directory = ../../overlays/debug-packages;
        };
      };
    };
}
