# Brainstorm: resolve a restarted kept-alive job's failure

This records the exploration behind Linear CAM-92; the evidence is the operator's diagnosis in `logs/cam92-evidence/diagnosis.md` and the issue's two comments of 2026-11-08.

## Problem

`LaunchdJobFailed stibnite` fired at 2026-11-08T03:21Z for `org.nixos.nix-daemon` and stays firing while the daemon runs normally.
An activation changed only `plugin-files` in `/etc/nix/nix.conf`, so nix-darwin sent `launchctl kill HUP` to the daemon; nix 2.35.3 exits on `SIGHUP`, and during static destruction a worker's `SIGCHLD` made `sigChldHandler` write to the destroyed `sigChldPipe` and call `abort()`.
launchd relaunched the daemon (stored `launchd_job_runs_total` 3 to 4 at 03:15:06Z) and kept `last terminating signal = Abort trap: 6` with no exit code, which the probe writes as -1.
The rule reads launchd's last exit, and a kept-alive job that runs again has no next exit, so the instance resolves only at the job's next clean exit.
Acceptance 8.4 resolved only because the operator's `launchctl kickstart -k` produced a second, clean exit.

## Options

- O1: carry NixOS/nix#16517 on the daemon's nix, or move to a nix that has it.
- O2: count a kept-alive job's abnormal last exit only while its run count rose within the last 30 minutes, leaving a job that stays down to `LaunchdJobNotRunning` and a crash loop to `LaunchdJobRestartLoop`.
- O3: a stateful probe that writes 0 once a relaunched job has run for a while.

## Decisions (operator, 2026-11-08)

- O2 is adopted: `LaunchdJobFailed` counts a kept-alive job's abnormal last exit only while `increase(launchd_job_runs_total[30m]) > 0`, so a genuine crash still fires and an instance resolves about 35 minutes after the job runs again; jobs that are not kept alive keep today's semantics.
- O3 is rejected: the stored series stays launchd's last exit as found, and the probe does not change.
- O1 is not implemented: no released nix carries #16517 (it merged to master only, `18057950ca43`, 2026-09-25), nixpkgs offers no newer nix than 2.35.3, and the operator ruled out building nix ourselves.
  When a release carrying #16517 reaches nixpkgs, `modules/system/nix-package.nix` switches from `nixVersions.nix_2_35` to `nixVersions.latest`, which is recorded as a follow-up.
- Asking upstream to backport #16517 to `2.35-maintenance` needs the operator's go-ahead.
