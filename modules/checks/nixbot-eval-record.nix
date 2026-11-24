# Behavioural check of nixbot-evaluation-record.patch (CAM-111 design D5,
# D6): the patched evaluation runner logs one `evaluation finished` record per
# evaluation, on success, failure and timeout, reads the evaluation cgroup's
# counters before the cgroup is removed, counts nix-eval-jobs' two kill lines,
# and keeps no text from the evaluator's output. The cases are in
# ./nixbot-eval-record/test_eval_record.py and run against nixbot built from
# the pinned input with flake.lib.nixbotPatches, the same list magnetite's
# nixbot is built with, so no host configuration is evaluated here. A plain
# directory stands in for the delegated cgroup subtree, as nixbot's own
# cgroup tests do. Defined for x86_64-linux only: nixbot runs on magnetite.
{ config, inputs, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      nixbot = inputs.nixbot.packages.${system}.nixbot.overridePythonAttrs (old: {
        patches = (old.patches or [ ]) ++ flakeLib.nixbotPatches;
      });
      python = nixbot.pythonModule.withPackages (ps: [
        nixbot
        ps.pytest
      ]);

      nixbot-eval-record =
        pkgs.runCommand "nixbot-eval-record"
          {
            nativeBuildInputs = [
              python
              pkgs.coreutils
            ];
            meta.description = "behavioural check: nixbot logs one evaluation record per evaluation";
          }
          ''
            cp ${./nixbot-eval-record/test_eval_record.py} test_eval_record.py
            export HOME=$TMPDIR
            python -m pytest -p no:cacheprovider -q test_eval_record.py 2>&1 | tee result.txt
            test "''${PIPESTATUS[0]}" -eq 0
            mkdir -p $out
            cp result.txt $out/
          '';
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        nixbot-eval-record = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit nixbot-eval-record;
      };
    };
}
