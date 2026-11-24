# checks.x86_64-linux.harmonia-gc-obligations: the judge of
# flake.lib.harmoniaGcObligations (modules/system/harmonia-gc.nix) accepts a
# NixOS unit bounded by TimeoutStartSec and a darwin job that runs harmonia-gc's
# argv under `timeout` with its output and errors in the one log, and finds
# exactly one problem in each mutant: no TimeoutStartSec, a different
# duration, no timeout wrapper, a wrapper around a different argument list,
# no StandardOutPath, no StandardErrorPath, and a log path elsewhere.
#
# Per-host facts are asserted by modules/checks/machines.nix on every
# nixos-<host> and darwin-<host> check, which already evaluates the
# configuration. No host is evaluated here; the fixtures are literals, so the
# check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.harmoniaGcObligations;
      argv = [
        "/h/bin/harmonia-gc"
        "--delete-older-than"
        "7d"
      ];
      darwinOk = {
        ProgramArguments = [
          "/c/bin/timeout"
          o.bound
        ]
        ++ argv;
        StandardOutPath = o.logPath;
        StandardErrorPath = o.logPath;
      };
      nixosOk = {
        Type = "oneshot";
        TimeoutStartSec = o.bound;
      };
      darwin = service: {
        platform = "darwin";
        inherit service argv;
        problems = 1;
      };
      nixos = service: {
        platform = "nixos";
        inherit service;
        problems = 1;
      };
      cases = {
        nixosAccepted = nixos nixosOk // {
          problems = 0;
        };
        darwinAccepted = darwin darwinOk // {
          problems = 0;
        };
        nixosNoTimeout = nixos (removeAttrs nixosOk [ "TimeoutStartSec" ]);
        nixosOtherDuration = nixos (nixosOk // { TimeoutStartSec = "4h"; });
        darwinNoWrapper = darwin (darwinOk // { ProgramArguments = argv; });
        darwinOtherArgv = darwin (
          darwinOk
          // {
            ProgramArguments = [
              "/c/bin/timeout"
              o.bound
              "/h/bin/harmonia-gc"
              "--delete-older-than"
              "10d"
            ];
          }
        );
        darwinNoStdout = darwin (removeAttrs darwinOk [ "StandardOutPath" ]);
        darwinNoStderr = darwin (removeAttrs darwinOk [ "StandardErrorPath" ]);
        darwinLogElsewhere = darwin (darwinOk // { StandardErrorPath = "/tmp/harmonia-gc.err"; });
      };
      wrong = lib.filterAttrs (
        _: case: lib.length (o.problems { inherit (case) platform service argv; }) != case.problems
      ) (lib.mapAttrs (_: case: { argv = null; } // case) cases);
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        harmonia-gc-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.harmonia-gc-obligations =
        assert lib.assertMsg (
          wrong == { }
        ) "harmonia-gc-obligations: the judge misjudges ${toString (lib.attrNames wrong)}";
        pkgs.runCommand "harmonia-gc-obligations" { } "touch $out";
    };
}
