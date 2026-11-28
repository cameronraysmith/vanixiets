# The identity oracle for iets' classic mode as `nix` (flake.lib.nixClassic):
# stock nix and classic evaluate the configurations people evaluate, at one
# commit, and each must give the same drvPath and the same .drv closure.
# `just eval-identity` runs it after the nix-eval-jobs oracle, and an iets
# input bump is merged only after it passes; stock is the fleet's nix
# (flake.lib.fleetNix), the one classic wraps.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.nix-classic-identity = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nix-classic-identity";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.git
              pkgs.jq
            ];
            runtimeEnv = {
              NIX_STOCK = lib.getExe (flakeLib.fleetNix pkgs);
              NIX_CLASSIC = lib.getExe (flakeLib.nixClassic pkgs);
            };
            text = builtins.readFile ./nix-classic-identity.sh;
          }
        );
        meta.description = "Compare stock nix and iets' classic mode on configuration drvPaths and .drv closures of a commit";
      };
    };
}
