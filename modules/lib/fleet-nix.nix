# fleetNix: the Nix the fleet runs, for a package set. One value for the
# system's nix.package (system/nix-package.nix), the default devShell's `nix`
# and every tool that pins a Nix of its own, so they cannot drift apart.
{ ... }:
{
  flake.lib.fleetNix = pkgs: pkgs.nixVersions.nix_2_35;
}
