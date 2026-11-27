# The drvPath-identity oracle between stock nix-eval-jobs and iets: the
# host's nix-eval-jobs-stock and nix-eval-jobs (iets, where the host's
# memory gives it iets: modules/lib/nix-eval-jobs-host.nix) both evaluate
# checks.<system> of one commit with the same arguments, and every attribute
# must have the same drvPath, system and outputs, and fail in both or in
# neither. By default both are the host configuration's evaluators built at
# that commit, so an iets input bump is tested with the iets it pins; on
# NixOS those are lock-wrapped, so both runs stay behind the host's
# evaluation lock. `--evaluators path` runs the names on PATH instead.
# `just eval-identity` runs it. It is the evidence behind evaluating with
# iets: run it after an iets bump or before widening iets' use.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    {
      apps.nix-eval-jobs-identity = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nix-eval-jobs-identity";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.git
              pkgs.jq
            ];
            runtimeEnv.NIX_STOCK = lib.getExe (flakeLib.fleetNix pkgs);
            text = builtins.readFile ./nix-eval-jobs-identity.sh;
          }
        );
        meta.description = "Compare stock nix-eval-jobs and iets drvPaths over checks.<system> of a commit";
      };
    };
}
