## Context

`LaunchdJobFailed` is `launchd_job_last_exit_code{launchd_label!~"<labels in notifiedUnits>"} != 0` for 5 min (`modules/nixos/fleet-alert/rules.nix`).
The darwin probe (`modules/lib/otel-host-probe.nix`) keeps no state and writes launchd's last exit as it finds it: the code, 0 for `(never exited)` or an idle reclaim, and -1 when launchd shows only a terminating signal.
launchd keeps a job's last exit until its next exit, so a kept-alive job relaunched after an abnormal exit keeps that exit for as long as it runs.
On 2026-11-08 at 03:13:49Z an activation's `SIGHUP` made nix 2.35.3's daemon abort during static destruction (NixOS/nix#16517); launchd relaunched it, the store's `launchd_job_runs_total` for `org.nixos.nix-daemon` went from 3 to 4 at 03:15:06Z with the last exit -1, and the instance has fired since 03:21Z (`logs/cam92-evidence/diagnosis.md`).
Acceptance 8.4's instance for `org.nixos.otelcol-process` resolved only because the operator's `kickstart -k` produced a second, clean exit.

The evaluator sends each PromQL rule as an instant query to GreptimeDB 1.2.1 on magnetite, as the `regulator` account, once a minute; `transition.jq` fires an instance once its condition has held for its `for` and resolves it once the condition has been absent for 300 s.
The flake's `checks.x86_64-linux.fleet-alert` runs the evaluator against a fixture server that replays canned answers to each rule's rendered expression, so a leg states the store's answer and the check models how the rendered expression selects, as `LaunchdJobNotRunning`'s legs already do.
Each new check clause names its two value sources, each mutant runs only the leg it must fail, and the regulator is seen failing before the rule changes.
Evaluation cost is measured with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath` against 536,870,912 B.

## Goals / Non-Goals

**Goals:**

- A kept-alive job that launchd relaunched after an abnormal exit, and that runs, stops being reported about 35 minutes after its relaunch, with no operator action.
- A kept-alive job's crash still fires `LaunchdJobFailed` once, after 5 minutes.
- A job that is not kept alive keeps today's semantics: a non-zero last exit fires and holds until the job's next clean exit.
- `fleet-alert` gains a leg for a restarted kept-alive job, seen failing on the current expression, and a mutant restoring that expression that the leg rejects.

**Non-Goals:**

- Changing the probe or what `launchd_job_last_exit_code` stores (O3 rejected).
- Changing the nix the daemon runs; D4 records the follow-up.
- Changing `LaunchdJobNotRunning`, `LaunchdJobRestartLoop` or any other rule.

## Decisions

### D1: A second arm for kept-alive jobs, gated on a recent launch

- **Choice**: `LaunchdJobFailed` becomes

  ```promql
  launchd_job_last_exit_code{launchd_label!~"<notified>|<kept-alive>"} != 0
  or (
    launchd_job_last_exit_code{launchd_label=~"<kept-alive>", launchd_label!~"<notified>"} != 0
    and on (host_name, launchd_label) increase(launchd_job_runs_total[30m]) > 0
  )
  ```

  on one line, `for` 5 min, where `<kept-alive>` is the regex `LaunchdJobNotRunning` already renders from `launchdKeptAlive` and `<notified>` the existing `org.nixos.<unit>` exclusion.
- **Rationale**: launchd relaunches a kept-alive job after each exit, so the launch that follows a crash is the event, and the job's abnormal last exit is news only near it; a job that stays down is `LaunchdJobNotRunning`'s and a crash loop `LaunchdJobRestartLoop`'s, so nothing is lost when the old exit stops counting.
  `on (host_name, launchd_label)` matches the two operands on the labels that name a job, so the match does not depend on how the store treats `__name__`, which GreptimeDB 1.2.1 keeps on `increase`'s result where Prometheus drops it (measured, `logs/cam92-evidence/2-increase-nixdaemon-*.log`).
  The answer's label set is the first operand's, `host_name`, `instance`, `job`, `launchd_label`, `service_instance_id` and `service_name`, with no `__name__`, the same as today's, so the instance key does not change (measured, `logs/cam92-evidence/2-new-expr-store-*.log`).
- **Alternatives considered**: a stateful probe (O3), rejected because it moves alert policy into the probe and the stored value would stop meaning launchd's last exit; `changes(launchd_job_runs_total[30m]) > 0`, rejected because it also counts a reload's reset to 0, after which launchd has no last exit to report; a separate rule for kept-alive jobs, rejected because it would change the alert's name for the same failure class.
- **Boundary**: first-party source (`rules.nix`); the delivered rule takes effect only when magnetite deploys.

### D2: The 30-minute window as GreptimeDB evaluates it

- **Choice**: `increase(...[30m]) > 0`, as the operator decided (O2).
- **Rationale**: measured on magnetite's store over stibnite's history, `increase(launchd_job_runs_total{launchd_label="org.nixos.nix-daemon"}[30m])` is positive at the steps 03:16Z to 03:44Z after the sample that rose at 03:15:06Z, and 0 from 03:45Z, since GreptimeDB needs two samples inside the range; with `for` 5 min and the 300 s resolve, an instance fires about 5 minutes after the relaunch and resolves about 35 minutes after it.
  GreptimeDB 1.2.1 counts resets as Prometheus does: `extrapolated_rate` adds the value before each drop to `last - first` (`GreptimeTeam/greptimedb@v1.2.1 src/promql/src/functions/extrapolate_rate.rs:245-258, :317-322`).
  A reload of a kept-alive job's plist resets launchd's run count to 1, so a drop from 4 to 1 yields 1 and counts; the stored drop of `org.nixos.harmonia-gc` from 10 to 0 at 03:15:06Z yields 0 (measured, `logs/cam92-evidence/2-increase-harmonia-reset-*.log`), and a reloaded job has no last exit to report until it next exits `[INFERENCE: launchd reports (never exited) for a freshly loaded job, as the probe's fixture records for a job that has not run]`.
  A range with fewer than two samples answers nothing, so the second arm never holds on a window that cannot show a launch.
- **Alternatives considered**: a longer window, which keeps a recovered crash firing for longer; a shorter one, which a host's sampling gaps could make miss the launch altogether.
- **Boundary**: vendored behaviour (GreptimeDB 1.2.1), cited at its tag and measured on the deployed store.

### D3: The regulator models the rendered arms

- **Choice**: `modules/checks/fleet-alert.nix` parses `LaunchdJobFailed`'s rendered expression into its arms (`failedArms`): the first arm's exclusion and, when present, the second arm's kept-alive regex, notified exclusion and window in minutes.
  `failedAnswer` gives the store's answer at minute n over jobs `{ label; exit; launchedAt; }`: a job is answered when its exit is not 0 and either its label is not excluded by the first arm, or it matches the second arm's labels and `launchedAt` is less than the window before n.
  Any other shape fails the check's evaluation.
  The legs, each against the rendered table on stibnite with one-minute runs:
  - `keptAliveRestarted`: `org.nixos.nix-daemon`, last exit -1, launched at minute 0, minutes 0 to 40; expected `5 [FIRING]` and `34 [RESOLVED]`.
  - `keptAliveCrashed`: `org.nixos.otelcol-process`, last exit -1, launched at minute 0, minutes 0 to 10; expected `5 [FIRING]`.
  - `notKeptAliveHeld`: `org.nixos.harmonia-gc`, last exit 1, launched at minute 0, minutes 0 to 40; expected `5 [FIRING]` and nothing more.
  - The mutant `failedIgnoresLaunch` restores the single-arm expression with the rendered notified exclusion and runs only `keptAliveRestarted`, which it must fail.
  The existing legs `envelopeFailedNotReported`, `harmoniaFailedReported` and `stibniteSilent` answer through the same model.
- **Rationale**: the expected posts come from the decision (fire after `for`, resolve 30 minutes after the launch plus 300 s), and the answers from the rendered expression, so the two value sources are independent: a change to the window, to an arm's labels or to the kept-alive split moves the answers and fails a leg.
  `keptAliveCrashed` fails a rule that drops kept-alive jobs, and `notKeptAliveHeld` a rule that gates every job on a launch.
- **Alternatives considered**: replaying the second arm's answer as a literal list per step, which would pass whatever the rule renders.
- **Boundary**: first-party check source.

### D4: The nix follow-up

- **Choice**: not implemented here; when a nix release carrying NixOS/nix#16517 reaches nixpkgs, `modules/system/nix-package.nix` switches `nix.package` from `pkgs.nixVersions.nix_2_35` to `pkgs.nixVersions.latest`.
- **Rationale**: no released nix carries the fix (master only, `18057950ca43`, 2026-09-25; `2.35-maintenance`, 2.35.3 and 2.35.5 still declare `static unix::SelfPipe sigChldPipe;`), nixpkgs' `latest` is 2.35.3, and the operator ruled out building nix ourselves; until then any activation that changes `nix.conf` can make the daemon abort and raise one `LaunchdJobFailed` that resolves about 35 minutes later.
- **Boundary**: vendored (nix and nixpkgs).

## Risks / Trade-offs

- [Trade-off] A kept-alive job that crashes once and then runs stably is reported as a crash event that resolves after about 35 minutes, not as a continuing failure → accepted by the operator (O2); `LaunchdJobNotRunning` and `LaunchdJobRestartLoop` report a job that stays down or loops.
- [Risk] stibnite's samples have gaps, as from 03:31Z to 03:37Z on 2026-11-08; if the host stops reporting for most of the 30 minutes after a crash, the second arm may hold for less than the 5-minute `for` on reporting passes and the crash goes unreported → accepted; the evaluator already freezes an instance while its host is silent, and the gap that would hide a crash is one in which the host sleeps through most of the window.
- [Risk] Until D4, every `nix.conf`-changing activation on stibnite may raise one 35-minute `LaunchdJobFailed` for `org.nixos.nix-daemon` → accepted as a true report of an abort.
- [Risk] The fixture server cannot evaluate PromQL, so the legs rest on the arms model; a store whose `and on` or `increase` behaved differently would pass the check → mitigated by the measurements of D1 and D2 on the deployed store and by the replay over stibnite's stored history before deploy.

## Migration Plan

Magnetite alone runs the evaluator, so only its deploy changes behaviour; stibnite and the other hosts are unaffected.
After the pull request merges through the queue, magnetite is deployed from the deploy worktree detached at `origin/main` with `clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log`, after `nixbot-logs queue` prints `Queue is empty`.
The `nix-daemon` instance firing since 2026-11-08T03:21Z then has no answer, its relaunch being more than 30 minutes old, and resolves 5 minutes after the first run: one `[RESOLVED] LaunchdJobFailed stibnite` is expected.
The deploy is verified by reading every post since it started from `sudo journalctl -u fleet-alert -u 'observability-notify@*' --since <start>` on magnetite and from `fleet-alerts`, recording each with its cause.
Rollback: revert the rule's commit and deploy magnetite again; the instance would fire again 5 minutes later.

## Open Questions

- Whether to ask upstream to backport NixOS/nix#16517 to `2.35-maintenance` waits for the operator's go-ahead.
