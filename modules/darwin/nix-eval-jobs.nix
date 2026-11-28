# The darwin host's nix-eval-jobs, chosen by its memory in flake.lib.hosts
# (modules/lib/nix-eval-jobs-host.nix): iets, bounded in workers only, with
# stock beside it as nix-eval-jobs-stock, or stock alone. darwin has no host
# evaluation lock, so the packages are installed as they are.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.darwin.base-nix-eval-jobs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.nixEvalJobs;
      evaluators = flakeLib.nixEvalJobsPackages pkgs { inherit (cfg) bound; };
    in
    {
      options.vanixiets.nixEvalJobs = {
        bound = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = flakeLib.nixEvalJobsBound config.networking.hostName;
          defaultText = lib.literalExpression "flake.lib.nixEvalJobsBound config.networking.hostName";
          readOnly = true;
          description = "iets' bound (workers) from the host's memory in flake.lib.hosts, or null where the host keeps stock nix-eval-jobs.";
        };
        package = lib.mkOption {
          type = lib.types.package;
          default = evaluators.package;
          defaultText = lib.literalExpression "iets at config.vanixiets.nixEvalJobs.bound, or pkgs.nix-eval-jobs where it is null";
          readOnly = true;
          description = "The nix-eval-jobs on the system PATH.";
        };
        stockPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = evaluators.stockPackage;
          defaultText = lib.literalExpression "nix-eval-jobs-stock where package is iets; null otherwise";
          readOnly = true;
          description = "Stock nix-eval-jobs as nix-eval-jobs-stock where package is iets, for what iets refuses (import-from-derivation, --override-input, --override-flake, --repair, --help).";
        };
      };

      # A stock host's system profile is left as it was: its homes install
      # stock nix-eval-jobs (modules/home/development/nix-tools.nix).
      config.environment.systemPackages = lib.optionals (cfg.bound != null) [
        cfg.package
        cfg.stockPackage
      ];
    };
}
