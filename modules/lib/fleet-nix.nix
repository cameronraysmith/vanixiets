# fleetNix: the Nix the fleet runs, for a package set. One value for the
# system's nix.package (system/nix-package.nix), the default devShell's `nix`
# and every tool that pins a Nix of its own, so they cannot drift apart.
#
# withFleetNix: a program that runs `nix` from PATH, with fleetNix first on
# its PATH, for programs whose result a host or a cluster consumes (nh's build
# before activation, nixidy's rendered manifests): they evaluate with the
# fleet's Nix whatever `nix` the caller has first.
{ config, lib, ... }:
{
  flake.lib.fleetNix = pkgs: pkgs.nixVersions.nix_2_35;

  flake.lib.withFleetNix =
    pkgs: name: package:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ (config.flake.lib.fleetNix pkgs) ];
      text = ''exec ${lib.getExe' package name} "$@"'';
    };
}
