# Interleaved evaluation-cost measurement: one attribute at two commits with
# the fleet's stock nix, an untimed warm-up per commit, then before/after
# rounds in fresh processes with NIX_SHOW_STATS, every run and its conditions
# written to logs/. `just eval-cost` runs it; the committed baselines are in
# docs/notes/development/eval-cost-baselines.md.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.eval-cost = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "eval-cost";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gawk
              pkgs.git
              pkgs.jq
            ];
            runtimeEnv.NIX_STOCK = lib.getExe (flakeLib.fleetNix pkgs);
            text = builtins.readFile ./eval-cost.sh;
          }
        );
        meta.description = "Measure an attribute's evaluation cost at two commits in interleaved fresh runs";
      };
    };
}
