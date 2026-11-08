---
linear_story_id: CAM-92
linear_story_identifier: CAM-92
linear_story_title: "Resolve LaunchdJobFailed once a restarted kept-alive job is running again"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-92/resolve-launchdjobfailed-once-a-restarted-kept-alive-job-is-running
linear_story_state: In Progress
linear_team: CAM
linear_project: fleet-observability
last_synced_state: null
last_synced_at: null
review_round: 0
max_review_rounds: 3
attempt_log: []
---

## Why

`LaunchdJobFailed` reads launchd's last exit, and a kept-alive job that launchd relaunched after an abnormal exit has no next exit while it runs, so the alert stays firing until someone restarts the job by hand.
On 2026-11-08 an activation's `SIGHUP` made nix 2.35.3's daemon abort on its way out (NixOS/nix#16517, in no released nix), and `LaunchdJobFailed stibnite` has fired since 03:21Z for a daemon that runs normally.
Counting a kept-alive job's abnormal exit only shortly after its relaunch keeps a genuine crash reported and lets the alert resolve on its own.

## What Changes

Decisions tagged `O<n>` were made by the operator on 2026-11-08 and are recorded in `brainstorm.md`; `D<n>` are developed in `design.md`.

**`LaunchdJobFailed` for a kept-alive job**
- From: `launchd_job_last_exit_code{launchd_label!~"<labels in notifiedUnits>"} != 0` for 5 min, for every allow-listed job.
- To: a job that is not kept alive keeps that condition; a kept-alive job's non-zero last exit counts only while `increase(launchd_job_runs_total[30m]) > 0` for the same host and label, still for 5 min (O2; D1, D2).
- Reason: a relaunched kept-alive job keeps its abnormal exit as long as it runs, so the instance never resolves (CAM-92).
- Impact: non-breaking; a kept-alive job's crash fires as before and resolves about 35 min after its relaunch; a job that stays down remains `LaunchdJobNotRunning`'s and a crash loop `LaunchdJobRestartLoop`'s; the probe and the stored series are unchanged (O3 rejected).

**Regulator**
- `checks.x86_64-linux.fleet-alert` gains the legs `keptAliveRestarted`, `keptAliveCrashed` and `notKeptAliveHeld`, replayed from the rendered expression's arms, and the mutant `failedIgnoresLaunch`, the current expression restored, which must fail `keptAliveRestarted` (D3).

**Follow-up, not implemented**
- When a nix release carrying NixOS/nix#16517 reaches nixpkgs, `modules/system/nix-package.nix` switches from `nixVersions.nix_2_35` to `nixVersions.latest`, so a `SIGHUP` restart of the daemon stops aborting at its source (D4).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `fleet-alerting` (stratum: `behavioral`): `Each known failure class on a host reaches a person as an alert` counts a kept-alive job's non-zero last exit only within 30 minutes after launchd last started it, and gains the scenarios `A kept-alive job runs again after an abnormal exit` and `A kept-alive job crashes`.
- `fleet-alerting-interface` (stratum: `interface`): `Alert rules are rendered from one Nix source to the evaluator and to promtool` renders `LaunchdJobFailed`'s two arms and gains the scenario `A kept-alive job's abnormal exit is counted only after its relaunch`.
  Trust boundary: the evaluator judges the store's answer to the rendered expression; that a kept-alive job's crash raises its launch count, and that the store's `increase` counts a reset of that count to a positive value, rest on launchd and GreptimeDB 1.2.1, which this machine does not control.

## Impact

- Changed: `modules/nixos/fleet-alert/rules.nix` (`LaunchdJobFailed`'s expression and the header's description of it) and `modules/checks/fleet-alert.nix` (the arms model, three legs and one mutant).
- Documentation, under charter v31: the charter's v31 entry; ADR-009's status line, its `LaunchdJobFailed` row and Q10, amended in place; `docs/notes/development/observability/components/fleet-alert.md`; and the operator runbook `packages/docs/src/content/docs/development/operations/fleet-observability.md`, whose "Clearing a crashed kept-alive job" no longer needs a restart for the alert to resolve.
- Deployment: magnetite only, the host that runs the evaluator; deploying it resolves the `nix-daemon` instance firing since 2026-11-08T03:21Z, whose relaunch is more than 30 min old.
- Unchanged: the probe, `launchd_job_last_exit_code` and `launchd_job_runs_total`, every other rule, and the nix the daemon runs.
- Out of scope: the nix follow-up of D4 and any upstream backport request.
