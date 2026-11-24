# The weekly runtime-test run on pyrite (declare-test-size-classes design
# D11). enormous-tests.timer starts enormous-tests.service on Sundays at
# 03:00 pyrite time, and at boot after a missed Sunday; the service fetches
# main once, evaluates every vmTests.x86_64-linux test of that revision under
# the host evaluation lock, builds them one at a time with `--builders ''`,
# the enormous ones first, and appends one result record per test to
# /var/log/runtime-test-result.jsonl (modules/nixos/enormous-tests/run.sh).
# The collector ships the file into devloop.runtime_test_result through
# vanixiets.otelCollector.devloopRecordFiles, where fleet-alert's
# RuntimeTestCostDrift and EnormousTestStale read it. The unit is one of
# pyrite's notifiedUnits, so a failed, timed-out or unevaluated test posts
# one failure notice. checks.x86_64-linux.enormous-tests runs the script
# against a stub nix and a stub nix-eval-jobs.
#
# The builds go through nix-daemon (NIX_REMOTE=daemon), in its OOM order and
# max-jobs, as an operator's on-demand run does; the unit evaluates only
# through the host's lock-wrapped nix-eval-jobs. TimeoutStartSec bounds a run
# above every declared limit reached at once plus builds. Each test keeps one
# GC root, in rootsDir, on the output the run last saw pass.
#
# On demand, after the run notice: `systemctl start enormous-tests.service`;
# another revision or tree through a runtime drop-in setting
# Environment=ENORMOUS_TESTS_FLAKE=<flake reference>.
{ config, lib, ... }:
let
  recordFile = config.flake.lib.devloopCollection.runtimeTestResultFile;
  rootsDir = "/nix/var/nix/gcroots/enormous-tests";
  defaultFlake = "github:cameronraysmith/vanixiets/main";

  # The script, for a host name fixed at evaluation; `nix` and `nix-eval-jobs`
  # come from the caller's PATH. `body` is run.sh; the check passes its
  # mutants.
  runner =
    pkgs:
    {
      hostName,
      body ? builtins.readFile ./enormous-tests/run.sh,
    }:
    pkgs.writeShellApplication {
      name = "enormous-tests";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
      ];
      text = ''
        host=${lib.escapeShellArg hostName}
      ''
      + body;
    };
in
{
  flake.lib.enormousTestsRun = {
    inherit
      recordFile
      rootsDir
      defaultFlake
      runner
      ;
  };

  flake.modules.nixos.enormous-tests =
    { config, pkgs, ... }:
    {
      vanixiets.otelCollector.devloopRecordFiles.runtime-test-result = {
        file = recordFile;
        table = "runtime_test_result";
      };

      systemd.services.enormous-tests = {
        description = "Weekly build of every runtime test of main, one result record per test";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [
          config.nix.package
          config.services.nixEvalLock.package
        ];
        environment = {
          ENORMOUS_TESTS_FLAKE = defaultFlake;
          ENORMOUS_TESTS_RECORD = recordFile;
          ENORMOUS_TESTS_ROOTS = rootsDir;
          NIX_REMOTE = "daemon";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (runner pkgs { hostName = config.networking.hostName; });
          RuntimeDirectory = "enormous-tests";
          TimeoutStartSec = "6h";
        };
      };

      systemd.timers.enormous-tests = {
        description = "Weekly runtime-test run";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Pyrite's local time, named: observability-notify requires a
          # notified unit's calendar to carry its zone.
          OnCalendar = "Sun 03:00 America/New_York";
          Persistent = true;
        };
      };
    };
}
