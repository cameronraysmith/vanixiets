# checks.x86_64-linux.nixbot-iets-evaluator (CAM-111 tasks 5.2 and 5.3):
# magnetite's nixbot evaluates with iets through the host evaluation lock at
# 5 x 3072. Its nix-eval-jobs package is the lock wrapper over
# config.vanixiets.nixbot.ietsEvaluator, which forwards the stock evaluator's
# `nix`, so NIXBOT_EVALUATOR names iets. The mutant ietsUnwrapped, magnetite
# selecting the iets package without the wrapper, must fail the lock's
# assertion (modules/nixos/nix-eval-lock.nix): a bare iets would evaluate
# outside /etc/nix/eval.lock.
{ self, lib, ... }:
let
  magnetite = self.nixosConfigurations.magnetite;
  cfg = magnetite.config;
  iets = cfg.vanixiets.nixbot.ietsEvaluator;
  selected = cfg.services.nixbot.packages.nix-eval-jobs;
  stock = magnetite.options.services.nixbot.packages.nix-eval-jobs.default;
  failingAssertions =
    system: map (a: a.message) (lib.filter (a: !a.assertion) system.config.assertions);
  isLock = lib.hasPrefix "nix-eval-lock:";

  ietsUnwrapped = magnetite.extendModules {
    modules = [ { services.nixbot.packages.nix-eval-jobs = lib.mkForce iets; } ];
  };

  clauses = [
    {
      label = "nixbot's nix-eval-jobs is the lock wrapper over the iets package";
      holds =
        selected ? unwrapped
        && selected.unwrapped.drvPath == iets.drvPath
        && (selected.unwrapped.evaluator or null) == "iets";
    }
    {
      label = "the wrapper forwards the stock evaluator's nix";
      holds = selected.nix.drvPath == stock.nix.drvPath;
    }
    {
      label = "NIXBOT_EVALUATOR names iets and its version";
      holds = cfg.systemd.services.nixbot.environment.NIXBOT_EVALUATOR == "iets ${iets.version}";
    }
    {
      label = "nixbot evaluates with 5 workers of 3072 MiB";
      holds = cfg.services.nixbot.evalWorkerCount == 5 && cfg.services.nixbot.evalMaxMemorySize == 3072;
    }
    {
      label = "magnetite fails no evaluation-lock assertion";
      holds = !lib.any isLock (failingAssertions magnetite);
    }
    {
      label = "mutant ietsUnwrapped (iets without the lock wrapper) fails the lock's assertion";
      holds = lib.any isLock (failingAssertions ietsUnwrapped);
    }
  ];
  failing = map (c: c.label) (lib.filter (c: !c.holds) clauses);
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nixbot-iets-evaluator =
          assert lib.assertMsg (
            failing == [ ]
          ) "nixbot-iets-evaluator check: ${lib.concatStringsSep "; " failing}";
          pkgs.runCommand "nixbot-iets-evaluator" {
            meta.description = "evaluation check: magnetite's nixbot evaluates with iets behind the evaluation lock at 5 x 3072; iets without the lock wrapper rejected";
          } "touch $out";
      };
    };
}
