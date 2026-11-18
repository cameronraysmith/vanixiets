# Behavioural check of magnetite's memory-budget probe (CAM-111 design D11):
# given systemctl show output recorded on magnetite on 2026-11-18, with two
# blocks edited (gitea-mq.service's MemoryCurrent as [not set], and a
# gitea-runner-nix1.service block marked deactivating while systemd still
# reports its memory), and zram0's mm_stat, the probe writes exactly
# ./magnetite-memory-budget/expected.prom: both values of each active unit
# that has them, the owner's unit under its alias, nothing for a unit that is
# not active or a [not set] value, and zram's three sizes. Defined for
# x86_64-linux only: the evaluation host is x86_64-linux.
{ config, ... }:
let
  budget = config.flake.lib.magnetiteMemoryBudget;
in
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        magnetite-memory-budget =
          pkgs.runCommand "magnetite-memory-budget"
            {
              nativeBuildInputs = [ pkgs.diffutils ];
              config = builtins.toJSON budget.probeConfig;
              passAsFile = [ "config" ];
              meta.description = "behavioural check: magnetite's memory-budget probe formats systemd's unit memory and zram";
            }
            ''
              ${lib.getExe (budget.probe pkgs)} --format "$configPath" \
                ${./magnetite-memory-budget/show.txt} ${./magnetite-memory-budget/mm_stat.txt} > got.prom
              diff -u ${./magnetite-memory-budget/expected.prom} got.prom
              mkdir -p $out
              cp got.prom $out/
            '';
      };
    };
}
