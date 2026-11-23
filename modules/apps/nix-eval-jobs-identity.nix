# The drvPath-identity oracle between stock nix-eval-jobs and iets
# (flake.lib.mkNixEvalJobsIets): both evaluate checks.<system> of one commit
# with the same arguments, and every attribute must have the same drvPath,
# system and outputs, and fail in both or in neither. `just eval-identity`
# runs it. It is the evidence behind using iets for many-attribute evaluation
# (modules/home/development/nix-tools.nix, `just check-fast`, `just
# check-ifd`): run it after an iets bump or before widening iets' use.
# Stock is nixpkgs' nix-eval-jobs, the one a workstation would otherwise run.
{ config, inputs, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    {
      pkgs,
      lib,
      system,
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
            runtimeEnv = {
              NIX_EVAL_JOBS_STOCK = lib.getExe pkgs.nix-eval-jobs;
              NIX_EVAL_JOBS_IETS = lib.getExe (
                flakeLib.mkNixEvalJobsIets pkgs inputs.iets.packages.${system}.default pkgs.nix-eval-jobs
              );
            };
            text = builtins.readFile ./nix-eval-jobs-identity.sh;
          }
        );
        meta.description = "Compare stock nix-eval-jobs and iets drvPaths over checks.<system> of a commit";
      };
    };
}
