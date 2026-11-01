# S4 holistic review

A read-only review of `stand-up-linux-fleet-collection` as merged (#3631 to #3636, #3664 to #3672) and deployed on magnetite, cinnabar and pyrite, made on 2026-11-01 for tasks.md 10.2.
It read the change folder, `verify.md` and tasks.md 9.5 as #3676 carries them (head `f889b8321`), the deployed modules design.md names, the deployment fixes, and charter v23 to v25.
Three read-only sub-reviewers covered the modules, the deployment fixes, and `verify.md` with the documentation; every finding below that rests on their reports was checked against the code or the hosts.
Read-only queries ran on magnetite (`fleet-alert`'s and `otel-envelope`'s journals, the notifier's journal, `/var/log/deploy-record.jsonl`, `systemctl show otel-envelope.timer`), on cinnabar (the notifier's journal) and on pyrite (`journalctl -b all -u systemd-suspend.service` under `sudo`), between 18:10Z and 18:25Z.
Nothing was edited, built or deployed.

It found nothing critical, and thirteen findings: four significant and nine minor.
The significant ones are a budget breach that resolves itself five minutes after each hourly failure (F1), a queue clause that passes when its input is missing (F2), the NVMe rules shipped against names the store never gives and the live alerts that showed it, which no record holds (F3), and main's four ntfy assumptions still read at 2.28.0 after an unwatched upgrade to 2.31.0 (F4).
Every finding has a proposed disposition: apply now as a tasks.md §12 group, defer with a reference, or reject with a reason.

## Severity summary

| Severity | Count | Findings |
|---|---|---|
| critical | 0 | — |
| significant | 4 | F1, F2, F3, F4 |
| minor | 9 | F5 to F13 |

## Findings

| Id | Severity | Location | Finding | Evidence | Proposed disposition |
|---|---|---|---|---|---|
| F1 | significant | `modules/lib/otel-envelope.nix:116`, `:363`; `modules/nixos/observability-notify.nix:6-9`, `:168-169`; `modules/clan/services/otel-collector/flake-module.nix:509-515` | A budget breach posts `FAILED otel-envelope.service on magnetite` at minute 00 and a false `RESOLVED` at minute 05, every hour the breach lasts; nothing notices an hourly budget run that never happened | B1 to B6 run only when the run's minute is `00`; the next run, C1 to C4 only, starts successfully and the start hook posts `RESOLVED`; the 7.6 drop-in control logged that pair at 12:20:23Z and 12:21:25Z; the minute is read after C1 and C2, under the timer's default 1 min accuracy | apply now (§12): keep each B clause's last verdict and the time of the last budget run in the state file, re-fail non-hourly runs while a breach stands, and fail when the last budget run is over 65 min old; an `otel-envelope` case and mutant for each |
| F2 | significant | `modules/lib/otel-envelope.nix:325-339`; `design.md:404` | C3 passes when no `otelcol_exporter_queue_size` series exists, while design Risks says a renamed queue metric fails C3 on the first run | the awk loop iterates only over the size series it finds; no fixture lacks the size metric | apply now (§12): render the host's configured exporter names into the script and fail C3 for any exporter without both series; add a case and mutant; correct `design.md:404` |
| F3 | significant | `modules/nixos/fleet-alert/rules.nix:145-160` before #3669; design D9 (`design.md:292`, `:299`); FA scenario `The new rules meet the stored history`; tasks.md 5.4, 5.7; `verify.md` §8b | The NVMe rules shipped on 2026-10-29 with no stored series to replay and with names the store never gives; on 2026-11-01 the deployed evaluator posted `[FIRING] RuleSignalMissing` for both NVMe rules at 06:59:02Z and `[RESOLVED]` at 07:11:02Z, and neither tasks.md nor `verify.md` records these posts | `fleet-alert`'s journal on magnetite; 6.1's NVMe replay was empty because pyrite did not collect; ADR-004 item 7 already said the store appends `_total`; 5.4's "posted nothing naming pyrite" held because pyrite became an expected host only at magnetite's 06:28:35Z deploy | apply now (§12): record the four posts in `verify.md` §8b as the live run of the FA scenario `pyrite reports memory but no disk health`, and state that the scenario's "before the rules ship" could not hold for pyrite and was replaced by 5.7 and 5.8 |
| F4 | significant | `openspec/specs/world-assumptions/spec.md:366`, `:378`, `:390`, `:393`, `:402`; `modules/machines/nixos/cinnabar/ntfy.nix:21` | A37 to A40 state ntfy 2.28.0's behaviour while cinnabar runs 2.31.0; A39 names an upgrade as the event at which it is read again, and the upgrade arrived through a nixpkgs bump that nothing ties to the assumptions | `a42-ntfy-retention-20261101T174340Z.log` shows the `ntfy-sh-2.31.0` store path; `ntfy.nix:21` takes `pkgs.ntfy-sh` | apply now (§12): read each cited path at `binwiederhier/ntfy` v2.31.0, MODIFY A37 to A40 in this change's delta with the version and the monitors observed under it (1,077 probes refused with 403 for A38), and stop and tell the operator if any cited behaviour changed; defer the version guard to a follow-up issue the orchestrator files, because an assertion pinning the version fails every nixpkgs bump that moves ntfy and needs the operator's decision |
| F5 | minor | design D6 (`design.md:225-226`); `packages/docs/src/content/docs/development/operations/fleet-observability.md:377-378`; tasks.md group 5 | Setting a host's `collect` changes magnetite's evaluator too, because it reads `flake.lib.observabilityHosts` from magnetite's own closure; group 5 deployed only pyrite, and pyrite became expected at a magnetite deploy made for #3667 and #3668 | magnetite's deploy record: 06:28:35Z and 07:06:26Z, none after pyrite's 05:59Z deploy until then | apply now (§12): the runbook's "Adding an agent host" and design D6 add a magnetite deploy after the host's own; S5's stibnite row carries the same step |
| F6 | minor | `flake-module.nix:514`; `modules/nixos/fleet-alert.nix:839`; `modules/nixos/greptimedb.nix:411`; `flake-module.nix:358`, `:629-643` | No check holds #3667's UTC calendars on `otel-envelope`, `fleet-deadman` and `greptimedb-envelope`; #3634's `include_virtual_filesystems` and #3668's smartctl wrapper are held only at runtime | no file under `modules/checks` or `modules/vm-tests` names `OnCalendar`; only `fleet-alert.timer` is held, through R9.5's `periodSec` lookup (`fleet-alert.nix:596-600`) | apply now (§12): an agent-role assertion that every timer of a notified unit names a zone in `OnCalendar`, shown failing on `*:0/5`; reject build-time clauses for #3634 and #3668, because the presence selectors already report either regression within 30 min, as the NVMe rules showed on 2026-11-01, and a clause would restate the setting |
| F7 | minor | `verify.md` §1, §5, §8b, §9.1, header | Several statuses say more than their evidence (detailed below): A42, the dead-man's discharge, A13, A51, the origin/main cost claim, §1's heading, the header time, 5.6's notifier read, the gap requirement's evidence, and #3670's absence | the evidence logs §8b cites; `git log` of `modules/nixos/fleet-alert*` since 2026-10-18 | apply now (§12): reword each status to what was observed, re-run R9.3's evaluator stop at 5.8's sitting, measure `otel-envelope` and `greptimedb-envelope` at origin/main, and add #3670 to §5 |
| F8 | minor | `verify.md` §8a.2; this change's `world-assumptions`, `host-metrics-collection`, `fleet-alerting` and `devloop-collection` deltas | Seven nouns of behavioral requirements resolve to no designation row: owner, collection, job, disk ("on disk"), expected host, silence and silent, day and morning | `verify.md` §8a.2 | apply now (§12): five rows and two rewordings, per noun below |
| F9 | minor | FA `A missing signal is itself reported` (`specs/fleet-alerting/spec.md:53`); `modules/nixos/fleet-alert/transition.jq:35`; `modules/nixos/fleet-alert.nix:215` | The requirement says an always-on host silent for 10 min is reported, but the evaluator counts 600 s from the first pass on which an instant `count by (host_name)` drops the host, which is after the store's PromQL lookback `[INFERENCE: GreptimeDB's default 5 min]`; 9.2 met the scenario's 15 min bound by 25 s | cinnabar's collector stopped at 13:02:27Z and `[FIRING] RuleSignalMissing cinnabar` posted at 13:17:02Z (`fleet-alert`'s journal) | apply now (§12): confirm the lookback on magnetite, then state the requirement's 10 min from the last sample's exit from the lookback window, or bound the scenario at 16 min |
| F10 | minor | `modules/machines/nixos/cinnabar/fleet-alert.nix:3-7`, `:10`, `:29`; `modules/lib/observability-hosts.nix:4-7`, `:46`, `:51`; `modules/clan/services/otel-collector/README.md:236`, `:240`; runbook `:24`; `docs/notes/development/observability/components/host-probes.md:69`; `docs/notes/development/observability/decisions/ADR-009-alerting.md:138`; charter v23 M10 (`charter.md:381`); tasks.md 3.3 | Migration scaffolding and text the deployment made stale remain | cinnabar's `units = lib.mkIf (!collects)` can no longer apply; the README and runbook still describe cinnabar as not collecting; HP names smartctl_exporter 0.14.0, the deployed one logs 0.15.0, and omits #3668's wrapper; ADR-009 calls pyrite's SMART "unverified until acceptance"; no charter entry records #3667 or #3668; 3.3 still says `*:0/5` | apply now (§12): delete the scaffolding, keeping `collect` as the table's documented option; correct the text; the orchestrator records #3667, #3668 and M10's outcome in a charter v26 entry |
| F11 | minor | `modules/checks/otel-collector-config.nix:359-361`; `flake-module.nix:273-274`; `modules/checks/otel-envelope.nix:341` | R3.1's "a notified name is not a unit with an ExecStart" repeats the agent assertion's conjunct over magnetite's same services, and each `otel-envelope` mutant reruns all 15 cases, `longRun` included, to judge one | the two predicates are identical; the mutant loop passes `${allCases}` | apply now (§12): delete the check clause; run only `${m.case}` per mutant; reject removing the queue assertion's `file_storage`, `bytes` and `0s` conjuncts (`flake-module.nix:590-595`), because they hold the merged configuration against a host file's override, an assertion S1-R6 admits |
| F12 | minor | `modules/lib/otel-envelope.nix:209`, `:117`; `flake-module.nix:280` | C2 probes only the first target of each job's first `static_configs` entry; ADR-004's unit cap of 40 is written in two places | `builtins.head` twice; the literal 40 in the script's default and in the assertion | apply now (§12): `concatMap` over every target; one `otelCollectorSchema` attribute for the budget limits, read by both |
| F13 | minor | tasks.md 5.7, 5.8; `verify.md` §8b A13 | Neither 5.7's window nor 5.8's full day contains a suspend, so the laptop's resume path (the timer stopping in sleep, the exporter and the queue after resume) is unobserved | pyrite's journal holds no `systemd-suspend` entry since boot 0 began on 2026-10-28 | apply now (§12): 5.8 also records pyrite's suspend count over its window, and `verify.md` states the resume path unexercised when it is zero; S5's stibnite acceptance includes one suspend and resume |

## Report

### F1: a budget breach resolves itself, and a skipped budget run is invisible

- The budget clauses run inside `otel-envelope.service` only when `OTEL_ENVELOPE_MINUTE`, by default `date -u +%M`, reads `00` (`otel-envelope.nix:116`).
- The notifier posts `RESOLVED` from `ExecStartPost` on the unit's next successful start (`observability-notify.nix:6-9`, `:168`), so the 05 run, which runs C1 to C4 only, resolves a budget failure that still stands.
- A breach that lasts a day therefore posts 24 `FAILED` and 24 `RESOLVED`, and each `RESOLVED` is false.
- The 7.6 drop-in control showed the mechanism: `FAILED` at 12:20:23Z and `RESOLVED` at 12:21:25Z (`7.6-dropin-20261029T122000Z.log`).
- The minute is read after C1 and C2, which may take 10 s each per target, and the timer keeps systemd's default `AccuracySec=1min` (`systemctl show otel-envelope.timer` on magnetite).
- In practice every hour has run: magnetite's journal holds 67 `B1 active-series` lines from 2026-10-30T00:00Z to 2026-11-01T18:00Z, one per hour, each run starting at :00:01 or :00:02 and taking about 2 s.
- The risk is latent, but no clause would report a lost hour.
- A hung store could also push a magnetite run past `TimeoutStartSec = "4min"` (C1 10 s, C2 seven targets at 10 s, eight queries at curl's 30 s); the killed run still posts `FAILED`, and `greptimedb-envelope` reports the store, so that part needs no change.
- The fix keeps the hourly cadence inside one unit, so `fleet-ingress-interface`'s `otel-envelope on the ingress host regulates the fleet budget` stays as written.
  A separate `otel-budget.service` would also fix both, but adds a notified unit, a notifier instance to D8's arithmetic and a spec change.

### F2: C3 cannot fail on a missing queue metric

- C3 collects `otelcol_exporter_queue_size` and `_capacity` per exporter and data type, and reports only the size entries it found (`otel-envelope.nix:334-337`).
- With no size series, as after a collector release that renames it, C3 prints `ok`.
- `design.md:404` claims the opposite, and A52's mitigation leans on it.
- The configured exporters are known at evaluation (`services.opentelemetry-collector.settings.exporters`, less `forward`), which is a value source independent of the telemetry the script reads.

### F3: the NVMe rules met the store only in production

- #3635 merged the NVMe rules with `smartctl_device_critical_warning` and `smartctl_device_percentage_used`, the exporter's exposition names.
- The store keeps the exporter's counter-typed fields as OTLP sums with `_total`, which ADR-004 item 7 already stated; design D7 recorded "the counters carry no `_total` suffix" from the collector's own `:8888` endpoint, which is a different place.
- 6.1's NVMe replay was empty, because pyrite did not collect until 2026-11-01, and the rules shipped anyway; the FA scenario `The new rules meet the stored history` asks for the replay before the rules ship, which for pyrite could not happen.
- On 2026-11-01 magnetite's evaluator first expected pyrite after its 06:28:35Z deploy.
  It posted `[FIRING] RuleSignalMissing` for `rule=NvmeCriticalWarning, selector=smartctl_device_critical_warning` and for `NvmeWearHigh` at 06:59:02Z, and both `[RESOLVED]` at 07:11:02Z, after #3669's deploy at 07:06:26Z.
- These are the system's own detection of the defect, and the live run of the scenario `pyrite reports memory but no disk health`.
- No record holds them: tasks.md 5.4 recorded no post naming pyrite up to 06:32Z, and 5.7's replay used the corrected names, so its "absent for 1,740 s, under the 1,800 s `for`" describes rules that were not yet deployed.

### F4: ntfy's assumptions and the version cinnabar runs

- A37, A38, A39 and A40 in main open with "It is true of ntfy 2.28.0".
- cinnabar runs `ntfy-sh-2.31.0`; the package is `pkgs.ntfy-sh` from the root nixpkgs pin, so the flake updater moves it without any review of the assumptions.
- A39's Evidence names "a ntfy upgrade on cinnabar" as the event at which it is read again (`spec.md:393`); that event passed unread.
- `verify.md` is right not to rewrite the version without a reading.
  The reading is small: the cited paths are `cmd/serve.go`, `user/util.go`, `user/manager.go`, `user/manager_sqlite.go`, `server/server_auth.go`, `server/visitor.go`, `server/util.go` and `docs/config.md`.
- Live monitors already observed under 2.31.0 belong in the Evidence: the dead-man's 1,077 anonymous probes refused with 403 (A38), and ntfy's start at 06:03:17Z with the declared users (A37).

### F5: a host's flag needs magnetite's deploy too

- `RuleSignalMissing`'s `alwaysOn` and every rule's expected hosts come from `flake.lib.observabilityHosts` evaluated in magnetite's configuration (`rules.nix:21-27`).
- Design D6 says setting the flag is the one change, and the runbook's "Adding an agent host" ends at the host's own deploy.
- pyrite deployed at 05:55:54Z to 05:59:05Z; the evaluator expected it only from magnetite's 06:28:35Z deploy, which existed for #3667 and #3668.
- Without that deploy, pyrite's NVMe and file-system presence selectors would not have been watched.

### F6: guards for the deployment fixes

- #3667 moved four timers to UTC; only `fleet-alert.timer` is held, by accident of R9.5's `periodSec` table, which looks up `"minutely UTC"`.
- A local calendar on a host in a daylight-saving zone loses an hour at the autumn change, which the regulators on that host would not report.
- The other two fixes are held at runtime: a host without file-system series raises `RuleSignalMissing` for `FilesystemFillingWarn` and `FilesystemFull`, and a host without SMART series does so for the NVMe rules.

### F7: `verify.md` statuses that overclaim

- A42, "keeps heartbeats for 168 h across a restart": the 168 h expiry is configured and seen in each message's `expires`, and the oldest message ever returned was 12.05 h old; the only messages that crossed a restart carried the old 12 h expiry and expired on schedule.
  Restate it as holding against its violation condition, with 168 h configured and observed to 12 h; a poll after 2026-11-08T06:04Z observes the week.
- `A silent evaluator is reported from another host`: the live silence test is S3's of 2026-10-18, and the code it ran has changed since in e48bf7b2d, a1b2aac08, cdd4e49e5, a76ffc452, 493bd3981 (the dead-man's own timer) and 54a9613e7.
  The build-time leg `an empty window posts one FIRING, resumed heartbeats one RESOLVED` (`modules/checks/fleet-alert.nix:273-283`) passes on current code at every pull request; stopping `fleet-alert.timer` for 15 min at 5.8's sitting gives the live observation on the deployed code.
- A13, "holding": 5.6 switched pyrite's wifi off, which exercises network loss, not a suspend or a resume; pyrite has not suspended since 2026-10-28 (F13).
  Say "not violated; 5.6 exercised network loss only".
- A51, "holding" on one read: 5.7's log shows SMART samples every minute from 06:28:38Z to 17:32:38Z, which is the stronger citation, and A51's Evidence should say the controller rejects the Error Information log page and is read through #3668's wrapper.
- §9.1, "at origin/main `fcaf4e2d0` too": `costs-origin-main-20261101T174417Z.log` has no `otel-envelope` or `greptimedb-envelope` row, and #3667 changed `greptimedb.nix`.
- §1's heading names `openspec validate --all --json`, which did not run, and its box is unticked although the result it shows is valid.
- The header says 17:40 UTC, while §8b cites `a42-ntfy-retention-past12h-20261101T180734Z.log`.
- 5.6's notifier read printed `Failed to add filter for units: No data available` (`5.6-acceptance-20261101T144554Z.log:12-13`), so "no post naming pyrite" is shown for the evaluator only; on 2026-11-01 at 18:15Z `sudo journalctl -u 'observability-notify@*'` on pyrite printed the same message, which means the journal holds no notifier entry since the deploy.
- DC `A gap in the dev-loop history reaches a person within a day` cites only passing reconcile runs; the failing path is `devloop-ingest`'s mutants, which §8b should cite.
- The "SMART absence 1,740 s, under the 1,800 s `for`" line under `A missing signal is itself reported` shows a rule not firing; F3's live posts are the evidence for that requirement.
- §5's table omits #3670, which 5.6 refers to; the later toggle logs (`logs/pyrite-wifi-toggle-20261101T154158Z.log`, 1,076 s unreachable) show its effect was not settled when it merged.
- tasks.md 9.1 is ticked with pyrite's part pending; its note and 5.8 say so, which is honest, and the box stays as the operator left it.

### F8: the seven unresolved nouns

The rows follow the delta's table format, `| term | sense | phenomenon | status |`.

| Noun | Proposed disposition |
|---|---|
| owner | row: `\| owner \| — \| the person an Omnigent worker runs for, whose name the worker's unit name carries \| world-only \|`; a row is cheaper than retitling a requirement that tasks.md and `verify.md` quote |
| collection | row: `\| collection \| — \| a collector's continuing gathering of its host's signals \| shared \|` |
| job | row: `\| job \| — \| a unit that runs to completion each time it is started, by a timer or by another unit's failure, such as a regulator or the notifier \| shared \|`; it also grounds the `unit`, `notifier` and `evaluator` rows, which use the word |
| disk ("on disk") | reword HMC `Collection survives a telemetry store restart without losing the queued interval`, which this delta already modifies, from "on disk" to "in its local state", an existing row |
| expected host | row: `\| expected host \| — \| for one alert rule, a host from which the fleet expects its signal: every collecting host, or for the disk-health rules each collecting host with a disk-health source \| shared \|` |
| silence, silent | row: `\| silent \| — \| of a host or a job, having sent nothing it is expected to send for a stated time: a host no memory signal, the evaluator no heartbeat \| shared \|`; one sense covers "a laptop's silence", "every expected host is silent" and `A silent evaluator is reported from another host` without retitling it |
| day, morning | row: `\| day \| — \| a UTC calendar day, the period the reconcile compares \| shared \|`; reword DC `A gap in the dev-loop history reaches a person within a day`, which this delta modifies, from "by the end of the following morning" to "by 03:00 UTC of the following day", since 02:15 UTC is the previous evening in the operator's time zone |

### F9: the always-on silence bound

- `transition.jq:35` sets `absent_after` to 600 s, counted from the first pass on which `count by (host_name) (system_memory_usage_bytes)` no longer returns the host (`fleet-alert.nix:215`).
- An instant PromQL query returns a series until its last sample leaves the lookback window, so the alert follows the last sample by the lookback plus 600 s plus up to one 60 s pass `[INFERENCE: GreptimeDB's default lookback of 5 min; not read from magnetite's configuration]`.
- 9.2 observed 14 min 35 s from the collector's stop to the post, against the scenario's 15 min.
- The requirement's "has reported no memory signal for 10 minutes" therefore describes about 15 minutes of real silence.

### F10: stale scaffolding and text

- `cinnabar/fleet-alert.nix` lists `fleet-deadman` only while cinnabar does not collect, a branch that cannot apply since #3633; its header and the README (`:236`, `:240`) still describe that state, and the runbook (`:24`) says "on every collecting host and on cinnabar".
- `observability-hosts.nix:4-7` still describes the watched first deploy as current, and `collect = true` at `:46` and `:51` repeats the default at `:13`.
- `host-probes.md:69` names `prometheus-smartctl-exporter` 0.14.0, while the deployed exporter logs `version=0.15.0` (`5.3-smart-20261101T060029Z.log`), and its configuration surface omits #3668's `--smartctl.path` wrapper.
- `ADR-009-alerting.md:138` still calls pyrite's SMART support unverified until acceptance; charter v25 amended only that line's metric name.
- Charter v23's M10 entry (`charter.md:381`) keeps the exporter's own read as an acceptance observation; that read failed with exit status 4 and #3668 changed the exporter's arguments, and no charter entry records it or #3667.
- tasks.md 3.3 still says `OnCalendar = "*:0/5"`; `plan/task-6.md` and `plan/task-7.md:46` keep the pre-fix names and calendar, and stay as the history of what was planned.

### F11 and F12: checks and small defects

- The R3.1 clause at `otel-collector-config.nix:359-361` and the agent assertion's first conjunct at `flake-module.nix:273` test one predicate over magnetite's same evaluated services; the assertion holds it on every host, so the clause adds nothing.
- `checks/otel-envelope.nix:341` runs every case under each of the five mutants, and keeps only `${m.case}`'s result; each nixbot build pays for 75 case runs where 5 judge.
- `otelEnvelopeTargets` (`otel-envelope.nix:209`) takes `builtins.head` of the first `static_configs` entry's targets; every job has one target today, so a second target would be scraped and never probed.
- ADR-004's per-host unit cap appears as `40` in the script's default (`otel-envelope.nix:117`) and in the agent assertion (`flake-module.nix:280`), and the other budget limits only in the script.
- Not taken: C2's `otelcol` probe repeats C1 for a stopped collector, but the unit posts one `FAILED` either way; the ingress is written as magnetite in the certificate SANs and the inventory (`flake-module.nix:174`, `:781`, `:945`; `modules/clan/inventory/services/otel-collector.nix:12`), which ADR-003 item 9 and charter v23 M20 fix on purpose.

### F13: the 5.7 window and the laptop's suspend

5.7's truncation, by the operator's decision, weakens no discharge beyond what `verify.md` already marks pending, provided 5.8 runs before archive:

- FA `Each known failure class on a host reaches a person as an alert` rests on 5.7 for pyrite's would-be firings, and `verify.md` §8b says 5.8 completes the day.
- FA `A missing signal is itself reported` rests on 5.6 and 6.7 for its live parts; F3's posts strengthen it more than the replay does.
- HMC `Series cardinality stays bounded` and FII `otel-envelope regulates each agent from its own collector` wait on 9.1's pyrite capture, which 5.8 now runs, and §8b says so.

Two limits remain that neither window removes.
The "before the rules ship" condition could not hold for pyrite (F3).
pyrite has not suspended since boot 0 began on 2026-10-28, so the full day will not contain a resume either; design D7's "sleep stops the timer" and the exporter's and queue's behaviour after resume stay unobserved.

## Fixes found during deployment

| Fix | What failed and how it was found | Could the design have caught it | Rule that would have |
|---|---|---|---|
| #3634 | magnetite and cinnabar stored no file-system series: the scraper drops `nodev` file systems such as ZFS unless `include_virtual_filesystems` is set; 6.1's replay found it (`6.1-replay-20261029T094134Z.log:28`) | partly: D4 chose "no regulation at evaluation for the mountpoints", and `fleet-ingress` replaces the mount list with `/` on a non-ZFS root and never reads stored file-system series (`modules/vm-tests/fleet-ingress.nix:747-756`) | each new scraper's first deploy reads its series from the store on that host's real file-system type; the 6.1 replay, which S2-R6 promoted, did this |
| #3667 | pyrite deployed one minute before the autumn change, and `otel-envelope.timer`'s local calendar put its next run an hour later; found waiting for 5.4's first run | yes: GR records pyrite on `America/New_York`, and S3's `WeeklyPipelineTest` already handles that zone, but D7 wrote `*:0/5` with no zone; magnetite and cinnabar run in UTC, and so does the container test `[INFERENCE]` | every repeating calendar names its zone, held by an assertion (F6) |
| #3668 | smartctl_exporter 0.15.0 calls smartctl with `--log=error`, which pyrite's `APPLE SSD AP0512J` rejects (`Invalid Log Page (0x109)`), so the exporter dropped the device (`5.3-smart-20261101T060029Z.log`) | yes: M10 ran `smartctl -j -H -A` as root, not the exporter's argument list (`readjson.go:67`), and GR §5 notes the smartmontools documentation was not consulted; the 1.3 rehearsal skipped pyrite's exporter read, which could not run before the deploy | a pre-deploy probe of a vendored consumer uses that consumer's argument list, read from its source |
| #3669 | the NVMe rules read names the store never gives (F3); the live `RuleSignalMissing` fired at 06:59:02Z | yes: ADR-004 item 7 says the store appends `_total`, and S3's rule reads `systemd_service_restarts_total`; D7 took the names from the scrape endpoint, and the `fleet-alert` fixtures used the same hand-chosen names as the rules | a rule's metric names are read from a store that holds the series before the rule merges; an empty replay blocks the merge |
| #3666 | not a defect: the operator decided on 2026-11-01 that `fleet-alerts` should survive a phone's week off ZeroTier, rather than ntfy's 12 h default (charter v24) | S3 knew the 12 h limit and worked around it; it was a requirement gap the operator closed | none needed; F4 is the residue |
| #3670 | facter's detected DHCP made systemd-networkd lease a second address on pyrite's `wlp2s0` beside NetworkManager's, and pyrite took about 6 min to answer after its wifi returned in 5.6 | not S4's design, but the 5.1 presence log already shows `192.168.50.35` and `192.168.50.44/24` on `wlp2s0` (`5.1-presence-20261101T054500Z.log:3`), and nobody read it | read each evidence log for anomalies before the next step; #3670's assertion (`modules/checks/pyrite-desktop.nix:369-386`) now holds it |
| pinned certificate (#3664, 9.3) | the ntfy app had pinned caddy's leaf certificate, which `tls internal` replaces every 12 h, so the phone stopped receiving | no check observes a phone's receipt; S3-R6's rule of naming one delivered message caught it at 9.3 | acceptance confirms each subscriber's receipt after a leaf renewal; the runbook now warns against pinning (`fleet-observability.md:91-92`) |

## Measured and checked, not counted as findings

- Notices since S4's deploy: magnetite's notifier posted one `FAILED otel-envelope.service on magnetite`, at 12:20:23Z on 2026-10-29, the 7.6 control; cinnabar's posted two, at 13:10:00Z on 2026-10-29 and 05:05:00Z on 2026-11-01, the 9.2 and 9.3 controls; pyrite's journal holds no notifier entry.
- The evaluator's posts since 2026-10-29 08:00Z are the 9.2 and 9.3 pairs and F3's four; no file-system or NVMe rule fired.
- The hourly budget ran each hour from 2026-10-30T00:00Z, about 2 s a run; B3 prints `launchd_label table absent` each hour and passes, as designed until S5.
- Deploy-record lines equal rows: 17 and 17, then 24 and 24 on magnetite, 5 and 5, then 6 and 6 on cinnabar, 31 and 31 on pyrite.
- cinnabar's rate before magnetite's receiver was 22,784 bytes a minute, a tenth of the 256,000 the queue relation assumes.
- magnetite's process names reached 30 in 9.1's window, exactly ADR-004's bound; no breach, and no margin.
- The dead-man ran 1,077 times from 2026-10-29T00:00Z to 2026-11-01T17:40Z, each probe refused with 403 before its poll.
- C4's restart, carry-forward and empty-match handling match design D7, each with a mutant shown rejected; `StateDirectory` keeps the state under `DynamicUser`.
- The certificates: SAN and usage in `validation`, `restartUnits` where the host collects, `ca.crt` a store path, `otel-ca`'s key never deployed.
- R3.1's endpoint clause compares the receiver with the ZeroTier vars file, independent of `modules/lib/hosts.nix`.
- `otel-collector-config` fell from 0.455 to 0.443 GiB.

## What is sound

- The delivery path: three hosts' series arrive under their own `host_name` over mTLS, a client without a certificate is refused at the handshake from stibnite, and cinnabar's queue held its 24 min before magnetite's receiver and drained.
- The plan-time controls did their work: the plan review's 13 findings each have a disposition, among them its F1, the hourly budget's thousands of queries reduced to one physical-table query, its F2, a missed read that would have faked a loss, and its F3, the `collect` flag that kept routine deploys from applying the agent unwatched; the rehearsal corrected plan steps before the first deploy (`b5414d03a`).
- The absence regulator caught a real defect in production 31 min after the evaluator first expected pyrite (F3), and the replay caught #3634 before the file-system rules shipped.
- The vars steps left the `ntfy-alerter` token's hash and the ZeroTier controller's files unchanged.

## Verdict

S4 is deployed and does what its specs require on magnetite and cinnabar, and on pyrite for the window observed so far.
Fix F1 and F2 before archive, since each leaves a regulator reporting something false or nothing at all.
Record F3's posts and re-read F4's assumptions before `verify.md`'s Overall Decision.
F5 to F13 are wording, guards and cleanup that fit one §12 group.

### Questions for the operator

1. F1: keep the budget in `otel-envelope` with a carried verdict, as proposed, or split it into its own unit?
2. F4: should cinnabar's configuration hold ntfy's version, so that a nixpkgs bump moving ntfy fails CI until the assumptions are re-read?
3. F7 and F13: at 5.8's sitting, stop `fleet-alert.timer` for 15 min for the dead-man's live test, and suspend and resume pyrite once?
