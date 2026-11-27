# The cross-revision drvPath oracle: every nixos and darwin toplevel, every
# home activationPackage, checks.<system> and vmTests.<system> at two
# commits, diffed against an allow-list of declared differences; nothing is
# built. `just drv-diff` runs it. It holds the evaluator fixed (the fleet's
# stock nix, and the host's nix-eval-jobs-stock or nix-eval-jobs) and varies
# the revision, where `just eval-identity` holds the revision and varies the
# evaluator. drv-diff-base-allow.txt holds the checks built from the whole
# flake source, allowed on every run.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.drv-diff = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "drv-diff";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.git
              pkgs.jq
            ];
            runtimeEnv = {
              NIX_STOCK = lib.getExe (flakeLib.fleetNix pkgs);
              DRV_DIFF_BASE_ALLOW = "${./drv-diff-base-allow.txt}";
            };
            text = builtins.readFile ./drv-diff.sh;
          }
        );
        meta.description = "Diff drvPaths of every system, home, check and runtime test between two commits";
      };
    };
}
