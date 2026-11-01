# Retrospective: stand-up-linux-fleet-collection

> Written: 2026-11-01, with `review.md` (tasks.md 10.2), while 5.8, 11.1 and 10.3 to 10.5 wait for pyrite's first full day after 2026-11-02T05:59Z
> Commit range: `9ce870cf5^..fcaf4e2d0`, filtered to the S4 paths (`git log 9ce870cf5^..fcaf4e2d0 -- <S4 paths>`)
> Worktree: merged to main; `verify.md` is in #3676, open; the archive is tasks.md 10.5

---

## 0. Evidence

- **Commit range**: `9ce870cf5^..fcaf4e2d0`, 18 commits on the S4 paths in 15 pull requests: #3631 plan, #3632, #3633, #3634, #3635, #3636, #3664, #3665, #3666, #3667, #3668, #3669, #3670, #3671 and #3672; #3676 (`verify.md`) is open.
- **Diff size**: +7591 / -352 lines across 104 files (`git diff --shortstat 9ce870cf5^ fcaf4e2d0` over the change directory, `modules/lib/observability-hosts.nix`, `modules/lib/otel-envelope.nix`, `modules/clan/services/otel-collector`, the clan inventory's `otel-collector.nix`, the `otel-envelope`, `otel-collector-config`, `fleet-alert` and `greptimedb-envelope` checks, `fleet-ingress`, the `fleet-alert` module, `devloop-collection.nix`, `greptimedb.nix`, `modules/machines/nixos`, the runbook, `modules/README.md`, `docs/notes/development/observability`, the `otel-ca`, `otel-cert` and `ntfy-alerter` vars and `modules/checks/pyrite-desktop.nix`).
- **Plan size**: `plan.md` is an 18.6 KB index and `plan/task-1.md` to `plan/task-10.md` hold 6 KB to 43 KB each, all under jj's 300 KiB snapshot limit.
- **Tasks done**: 54/60 in #3676's tasks.md (`grep -cE '^- \[x\]'` → 54; `- [ ]` → 6: 5.8, 10.2 to 10.5 and 11.1).
- **Active hours**: not recorded; #3631 merged 2026-10-29T04:52Z and #3636 at 12:12Z, so groups 2 to 8 and the cinnabar and magnetite deploys took about 7 h 20 min; pyrite's sitting ran from #3664 at 2026-11-01T05:41Z to #3672 at 17:39Z (`gh pr view`).
- **Subagent dispatches**: not counted in the change folder; the plan review (tasks.md 1.1), the verifier (10.1) and this review (10.2) are each recorded.
- **New external dependencies**: none in the flake; `prometheus-smartctl-exporter` 0.15.0 from the root nixpkgs pin now runs on pyrite, and ntfy moved from 2.28.0 to 2.31.0 on cinnabar through a nixpkgs bump outside this change.
- **Bugs encountered post-merge**: 4 shipped defects found by deployment verification: #3634 (no ZFS file-system series), #3667 (a local-time timer on pyrite), #3668 (smartctl's error-log read) and #3669 (the NVMe rules' metric names); `review.md` F1 and F2 found two more in `otel-envelope` that have not fired; #3670 fixed a pyrite network defect older than this change.
- **OpenSpec validate state at archive**: `openspec validate stand-up-linux-fleet-collection --strict` passed on 2026-11-01 (`verify.md` §1); the archive-time state is tasks.md 10.5's.
- **Test coverage signal**: `checks.x86_64-linux.otel-envelope` with 15 cases and the mutants `meshRefusalIsLoss`, `missingCounterFails`, `resetNegative`, `targetDownOneRun` and `noCarryForward`; `otel-collector-config` with `meshWildcard`, `secondMeshReceiver`, `ztAddressOther`, `otlpInLogsPipeline` and `envelopeNotNotified`; `greptimedb-envelope` with `workerOwnsOtelKey`; `fleet-alert` with `cinnabarSilentLeg`, `laptopSilentLeg`, `nvmeExpectsPyriteLeg`, `notCollectingLeg`, `filesystemLeg`, `nvmeLeg` and `alwaysOnMagnetiteOnly`; `vmTests.x86_64-linux.fleet-ingress` with refusal, delivery, back-pressure, C1 to C4, crash-loop, long-run, budget and absent-CA cases (`3.4-fleet-ingress-20261029T072517Z.log`, `7.4-fleet-ingress-20261029T113746Z.log`).

Commit chain (chronological):

```
9ce870cf5 #3631 docs(observability): plan metrics collection from every NixOS host over mutual TLS
b5414d03a #3632 docs(observability): fix fleet-collection plan steps found by rehearsing them on the hosts
cdd4e49e5 #3632 feat(observability): collect host metrics from every NixOS host over a certificate-authenticated ingress
105e18098 #3633 feat(observability): collect host metrics from cinnabar
20a396b55 #3633 docs(observability): correct two fleet-collection deploy steps
ad7980a74 #3634 fix(observability): include ZFS mounts in the collector's filesystem scraper
a76ffc452 #3635 feat(observability): alert on full file systems and failing laptop disks, and on cinnabar's silence
b748c94e0 #3636 feat(observability): check the store's series and row budget every hour on magnetite
a82ac9a4f #3636 docs(observability): document the collector on every NixOS host, its certificates and its delivery checks
999e9c210 #3664 docs(observability): record the fleet-collection acceptance checks and warn against pinning ntfy's certificate
7027a5c02 #3665 feat(observability): collect host metrics and disk health from pyrite
9b0438fda #3666 feat(ntfy): keep fleet alerts on disk for a week
ca6bc8860 #3668 Read pyrite's NVMe health without the error-information log
493bd3981 #3667 Run the observability timers on UTC calendars
54a9613e7 #3669 fix(fleet-alert): read the NVMe series under their stored names
8380e15e2 #3670 pyrite: leave the wifi to NetworkManager
2bb540f8b #3671 openspec: record pyrite's presence and offline test for fleet collection
fcaf4e2d0 #3672 openspec: record pyrite's replay over its observed first hours
<close-out: #3676 verify; review, retrospective; 5.8 and 11.1 after 2026-11-02T05:59Z; archive: tasks.md 10.3 to 10.5>
```

---

## 1. Wins

- [evidence: `logs/s4-evidence/1.1-plan-review-20261029T045059Z.md`] The plan review found 13 problems, one high, three medium and nine low, and the planning pull request waited until its dispositions table had 13 rows, as S2-R6 required.
- Among them: its F1, B1 and B2 would have sent thousands of SQL queries to the store each hour, now one physical-table query each; its F2, one missed telemetry read would have reported a false loss, now carried forward; its F3, a routine deploy from `main` would have applied the agent role to cinnabar or pyrite unwatched, now prevented by the `collect` flag.
- [evidence: `b5414d03a`; `1.3-rehearsal-20261029T050000Z.log`] The rehearsal of every verification block against cinnabar, magnetite and pyrite before the first deploy corrected the plan's steps before they ran for real.
- [evidence: `6.1-replay-20261029T094134Z.log:28`; #3634] The replay of the new rules over stored history, which S2-R6 promoted, found that no host stored file-system series, before `FilesystemFillingWarn` and `FilesystemFull` shipped.
- [evidence: magnetite's `fleet-alert` journal, 2026-11-01] `RuleSignalMissing` caught the NVMe rules' wrong names in production: it posted `[FIRING]` for both rules at 06:59:02Z, 31 min after the evaluator first expected pyrite, and `[RESOLVED]` at 07:11:02Z after #3669's deploy (`review.md` F3).
- [evidence: `9.2-cinnabar-20261029T133229Z.log`; `9.3-exporter-20261101T051622Z.log`] AC4 and R3.2's target control held on cinnabar: `FAILED otel-envelope.service on cinnabar` and `[FIRING] RuleSignalMissing cinnabar` arrived for a stopped collector, `LocalExporterDown cinnabar` for a stopped exporter, and each `RESOLVED` after the restart.
- [evidence: `4.5-magnetite-20261029T083643Z.log`] A client without a certificate was refused at the handshake from stibnite (curl exit 56, "certificate required"), and cinnabar's queue held its 24 min before magnetite's receiver and drained to 0.
- [evidence: `4.6-deploy-records-20261101T045542Z.log`; `5.4-pyrite-20261101T060249Z.log`] Deploy records are exact on every collecting host: 24 and 24 on magnetite, 6 and 6 on cinnabar, 31 and 31 on pyrite.
- [evidence: `2.3-vars-20261029T050844Z.log`; `4.3-cinnabar-20261029T081444Z.log`] The vars steps left the `ntfy-alerter` token's hash unchanged, and cinnabar's zerotierone restart left the controller's files and network list unchanged.
- [evidence: notifier journals on magnetite, cinnabar and pyrite, read 2026-11-01] Since S4's deploy, every `FAILED` notice came from a deliberate control (7.6, 9.2, 9.3), and the hourly budget ran each of the 67 hours from 2026-10-30T00:00Z in about 2 s.
- [evidence: `verify.md` §9.1] `otel-collector-config` fell from 0.455 to 0.443 GiB, because the unit-cap and alias clauses moved into per-host assertions.

## 2. Misses

- [high] [painful | evidence: #3669; `review.md` F3] The NVMe rules shipped on 2026-10-29 with the exporter's exposition names, and the store gives those series `_total`.
- Root cause: design D7 read "the counters carry no `_total` suffix" at the collector's own `:8888` endpoint, a different place from the store, although ADR-004 item 7 already said the store appends `_total`; the `fleet-alert` fixtures used the rules' own hand-chosen names; and 6.1's NVMe replay was empty because pyrite did not yet collect, and the rules shipped anyway.
- The live alerts that exposed it are recorded in no tasks.md item and not in `verify.md`.
- [high] [painful | evidence: #3668; `5.3-smart-20261101T060029Z.log`] smartctl_exporter 0.15.0 calls smartctl with `--log=error`, pyrite's `APPLE SSD AP0512J` rejects that log page, and the exporter dropped the device.
- Root cause: M10 confirmed the read with `smartctl -j -H -A` as root, not with the exporter's argument list, and grounding did not read the exporter's source; the 1.3 rehearsal could not reach an exporter that was not yet deployed.
- [med] [painful | evidence: #3667] `otel-envelope.timer`'s `*:0/5` was local time on pyrite (`America/New_York`), and pyrite's deploy one minute before the autumn change put the next run an hour later.
- Root cause: grounding recorded pyrite's zone and S3's `WeeklyPipelineTest` already handled it, but D7 named no zone, and magnetite, cinnabar and the container test run in UTC.
- [med] [painful | evidence: #3634] The `filesystem` scraper drops `nodev` file systems such as ZFS unless `include_virtual_filesystems` is set, so the strict mount list matched nothing.
- Root cause: D4 chose no evaluation-time regulation for the mountpoints, and `fleet-ingress` replaces the list with `/` on a non-ZFS root and never reads stored file-system series; the replay caught it before the rules shipped.
- [med] [painful | evidence: `review.md` F1, F2] Two `otel-envelope` defects survived the plan review, the check and the container test: a budget failure at minute 00 is resolved by the 05 run while the breach stands, and C3 passes when the queue-size metric is missing, against design Risks' claim.
- Root cause: the crash-loop and long-running cases (S1-R6) tested restarts of the collector, not a notified unit whose clauses run at two cadences; and C3's input set came from the telemetry it judges, not from the configured exporters.
- [med] [painful | evidence: `review.md` F4] ntfy moved from 2.28.0 to 2.31.0 on cinnabar through a nixpkgs bump, and main's A37 to A40 still state 2.28.0's behaviour; A39 names an upgrade as the event at which it is read again, and nothing watched for one.
- [med] [painful | evidence: magnetite's deploy record; `review.md` F5] pyrite's `collect` flag reaches the evaluator only through magnetite's closure, and group 5 deployed only pyrite; pyrite became an expected host at magnetite's 06:28:35Z deploy, made for #3667 and #3668.
- [low] [painful | evidence: `review.md` F7] `verify.md` states several assumptions as holding on evidence that shows less: A42's 168 h is configured and observed to 12 h, A13 was exercised by network loss and not by a suspend, and the dead-man's live test ran on 2026-10-18 code.
- [low] [painful | evidence: `5.1-presence-20261101T054500Z.log:3`; #3670] The 5.1 presence log already showed two addresses on pyrite's `wlp2s0`, from systemd-networkd and NetworkManager both running DHCP, and nobody read it until pyrite took 6 min to return in 5.6.
- [low] [painful | evidence: tasks.md 9.3; `fleet-observability.md:91-92`] The ntfy app had pinned caddy's leaf certificate, which `tls internal` replaces every 12 h, so the phone stopped receiving until the operator installed caddy's root as a user CA.
- [low] [painful | evidence: `verify.md` §9.1] The pre-6.3 cost of `fleet-alert` was first recorded as 458,012,080 B, because the command named `#checks…` without the leading `.`, so nix searched `packages` first; the verifier re-measured 340,809,424 B.
- [low] [nit | evidence: `verify.md` §1; `plan/task-10.md`] Plan Task 10's third `comm` list compared unsorted input and failed as first written.
- [low] [nit | evidence: tasks.md 5.1, 5.7] pyrite's deploy waited from 2026-10-29 to 2026-11-01 for the operator's presence, and 5.7's replay covered 05:59:08Z to 17:33:08Z by the operator's decision, with 5.8 completing the day.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 1.3 | plan steps corrected before pull request 1 (`b5414d03a`) and two deploy steps after it (`20a396b55`) | the rehearsal and the first deploy |
| 6.1 (new #3634) | `include_virtual_filesystems` in the `filesystem` scraper, and the file-system replays rerun after the 09:50Z deploy | no ZFS file-system series were stored (§2) |
| 7, 8 | pull requests 3 and 4 landed as one, #3636 | the budget and the documentation were ready together |
| 5.2 to 5.7 | pyrite deployed on 2026-11-01 instead of after magnetite on 2026-10-29 | the operator's presence at pyrite (tasks.md 5.1) |
| 5.3 (new #3668, #3669) | the exporter's smartctl wrapper drops `--log=error`; the NVMe rules read `_total` | the SSD rejects the error log page; the store's names (§2) |
| 5.4 (new #3667) | the four observability timers on UTC calendars | a local calendar skipped an hour on pyrite at the autumn change |
| 5.6 | pyrite's wifi switched off rather than pyrite powered off; #3670 fixed its second DHCP client | the operator's choice; pyrite took 6 min to answer after its wifi returned |
| 5.7, 5.8 (new) | 5.7 over 05:59:08Z to 17:33:08Z; 5.8 repeats it over the full day with 11.1 and 9.1's pyrite capture | operator decision 2026-11-01 |
| 9.1 | ticked for magnetite and cinnabar; pyrite's capture moved to 5.8 | pyrite's 24 h ends after 2026-11-02T05:55:54Z |
| 9.5 (new) | the dead-man, its probe and A42 discharged | #3666 brought three requirements into the deltas (charter v24) |
| 10.1 | Plan Task 10's third `comm` list sorted | it compared unsorted input |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, `logs/s4/brainstorm-prep.md`) |
| superpowers:writing-plans                        | yes (`plan.md` and `plan/task-1.md` to `plan/task-10.md`) |
| superpowers:using-git-worktrees                  | yes (deploys from a detached worktree of `origin/main`; cinnabar's and pyrite's `collect = true` evaluated in a scratch tree) |
| superpowers:subagent-driven-development          | partial: the plan review, the verifier and this review are recorded; implementation dispatches are not |
| (transitive) superpowers:test-driven-development | yes (red logs for 2.1, 2.4, 2.8, 2.9, 3.1, 3.3, 6.2, 7.1 and #3669) |
| (transitive) superpowers:requesting-code-review  | partial: the codex sub-step was replaced, as in S1 to S3 |
| superpowers:finishing-a-development-branch       | pending (tasks.md 10.3 to 10.5) |

### S1, S2 and S3 rules applied in S4

The `:<line>` cells cite the rule's line in S1's (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/retrospective.md`), S2's (`openspec/changes/archive/2026-10-28-stand-up-devloop-collection/retrospective.md`) and S3's (`openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/retrospective.md`) retrospective as read on 2026-11-01.

| Rule | Source | Applied in S4 | What it caught |
|---|---|---|---|
| Read the upstream source behind a vendor option before depending on it | S1 §6 `:132` | partly: GR §1 to §5 read the collector's TLS validation, back-pressure and the exporter module's udev rule | GR §1 (validation opens no TLS file), GR §5 (the ACL only on `add`); missed the scraper's virtual file-system filter (#3634) and the exporter's `--log=error` (#3668) |
| Each new producer has a start-order relation and a check for it | S1 §6 `:136` | in substance: the agents queue and retry against a 503 (A52), and `fleet-ingress` starts the store, the schema job and both collectors together | nothing at deploy |
| Runtime tests start dependent units together and assert no dropped data | S1 §6 `:140` | yes: every `fleet-ingress` case asserts each exporter's `send_failed` is zero after first start (3.4) | nothing |
| A clause relates independently defined values; a property of one module is an assertion | S1 §6 `:144`, S3 §6 `:158` | yes: D6's assertions, D10's ZeroTier vars file | plan review F4 (a file-system assertion compared a value with its own source) and F5 (the SAN comparison); `review.md` F11 found one duplicate clause |
| Measure each new check's evaluation cost against a budget, with `.#.checks…` and the method | S1 §6 `:148`, S3 §6 `:154` | yes: before and after each task (`verify.md` §9.1) | the 458 MB figure taken with `#checks…` (§2); nothing over budget |
| Every runtime regulator clause has a negative control on a real store | S1 §6 `:152` | yes: `fleet-ingress`'s C1 to C4 and budget fixtures; the 7.6 drop-in | each control failed as named; missed C3's missing input (`review.md` F2) |
| `nix fmt` with its log before every commit | S1 §6 `:156` | yes: 3.5, 6.4, 7.4, 8.4 | nothing |
| Operator documentation is a task in the documenter gate's scope | S1 §6 `:160` | yes: group 8 (#3636) | `review.md` F10: the deployment fixes left the README, the runbook, HP and ADR-009 stale |
| Holistic review of the planned regulators before Task 1 | S1 §6 `:164`, S3 §6 `:162` | yes: tasks.md 1.1 | 13 findings, all decided before the planning pull request; the post-deployment review still found 13 |
| Check each slice's rules against the later slices that touch the same objects | S1 §6 `:168` | yes: design "Later slices" (S5 to S8, CAM-76) | `review.md` F5 adds magnetite's deploy to S5's host step; stibnite's probe must give the NVMe series the stored `_total` names `[INFERENCE]` |
| Notifier and regulator semantics tested across restart and cache-fill states | S1 §6 `:172` | yes: `otel-envelope`'s crash-loop and long-run cases | missed a notified unit whose two cadences resolve each other (`review.md` F1) |
| Resolve the designation-lint nouns at sync | S1 §6 `:176`, S3 §6 `:182` | yes: 10.1's lint and the ten rows the delta adds | seven nouns left (`review.md` F8) |
| Record the operator's reason whenever a planned gate is replaced | S1 §6 `:180` | yes: 5.7's truncated window | — |
| A journal or rotated-file reader is tested across boots, and its first deploy compares counts | S2 §6 `:171` | yes: each host's first deploy compared deploy-record lines and rows (4.6, 5.4) | nothing: every count equal |
| A unit script's tools are in its `runtimeInputs`, and the unit runs in a container test | S2 §6 `:175` | yes: 3.2 and 3.4 | nothing missing at deploy |
| A plan's verification commands name their interpreter and tools, rehearsed on the hosts | S2 §6 `:179` | yes: 1.3 | plan steps fixed in `b5414d03a`; pyrite's exporter read could not be rehearsed before its deploy |
| A plan file stays under 300 KiB, written per task | S2 §6 `:183` | yes: the largest file is `plan/task-2.md` at 43 KB | — |
| Plan-review findings are decided from the table, one disposition row per finding | S2 §6 `:187` | yes: 13 findings, 13 rows | — |
| A clause's two value sources are traced to their definitions | S2 §6 `:191` | yes: 1.1 lists each clause with its sources | plan review F4 and F5 |
| Never `jj rebase -r` a parent of the join; a normaliser keeps the join on `main` | S2 §6 `:195` | not recorded in the change folder | — |
| A new alert rule is replayed against stored history before it ships | S2 §6 `:199` | yes for magnetite and cinnabar (6.1); after shipping for pyrite (5.7) | #3634; missed the NVMe names, because the replay was empty and the rules shipped anyway (§2) |
| Concurrent implementation subagents each get their own workspace | S2 §6 `:203` | not recorded in the change folder | — |
| A step that must start during an earlier task is a tasks.md item there | S2 §6 `:207` | yes: 4.3's queue reads, 4.5's and 5.4's first-hour posts, 5.7 | 5.7's would-be firings; 5.8 added when the window was cut |
| `otel-collector-config` near its budget; per-host relations are assertions | S2 §6 `:211` | yes: D6, D10 | the check fell to 0.443 GiB |
| Leave the two `sqlquery` queries' text unchanged | S2 §6 `:215` | yes: 2.7's hashes equal | no re-backfill |
| Hold the deploy-record obligation on the darwin machines | S2 §6 `:219` | not S4's: S5 | — |
| The sync-order decision binds the sibling changes | S2 §6 `:223` | not S4's | — |
| Should the notifier retry its own post | S2 §6 `:227` | not applied: design Risks accepts a laptop's lost notices | — |
| A reference model is written from the specification's scenarios | S3 §6 `:142` | not applied: S4 changed no state rule in `transition.jq` (D9); the new `fleet-alert` legs follow the spec scenarios | — |
| A shared clan var gains a reader with `clan vars fix` | S3 §6 `:146` | yes: 2.3, with the token's hash before and after each step | nothing: every hash equal |
| A human step a later observation depends on is its own gated step | S3 §6 `:150` | yes: 5.1 and 5.5 | pyrite's sitting waited three days for presence, and nothing ran on pyrite without it |
| Each slice names the regulator its own silence modes need | S3 §6 `:166` | yes: `otel-envelope`'s C1 on every agent, `RuleSignalMissing` for the always-on hosts | missed a skipped hourly budget run, which no clause reports (`review.md` F1) |
| Schedule CAM-76's watch before S5 | S3 §6 `:170` | not S4's: charter v23 O8 lets S4 proceed first | — |
| A long-running evidence capture runs on an always-on host | S3 §6 `:178` | yes: 9.1 from magnetite, 5.6 from the evaluator's journal | — |
| A requirement ending on a person's device names one delivered message with its time | S3 §6 `:186` | yes: 9.2 and 9.3 confirmed on the phone | the ntfy app's pinned leaf certificate (§2) |

### Deliberately Skipped Skills

- **`superpowers:requesting-code-review`**
  - **What was skipped**: the paid `codex exec` review.
  - **Why this cycle**: the operator declined the paid review for the whole program and named one read-only Opus subagent instead, as in S1 to S3 (tasks.md 10.2).
  - The substitute found nothing critical and thirteen findings, four significant (`review.md`).
  - **How to prevent recurrence**: no recurrence to prevent; the plan-time review (tasks.md 1.1) precedes it.

## 5. Surprises

- The store gives an OTLP sum `_total`, while the collector's own endpoint and the exporter's exposition do not, so one series has two names, and a rule must use the store's (#3669).
- smartctl_exporter 0.15.0 hard-codes `--log=error`, and an Apple NVMe controller rejects that log page, so the exporter drops a device that `smartctl -H -A` reads (#3668).
- The collector's `filesystem` scraper drops `nodev` file systems, ZFS among them, unless `include_virtual_filesystems` is set (#3634).
- systemd computes a local calendar's next elapse across the autumn change an hour later, so a 5-minute timer in a daylight-saving zone skips an hour (#3667).
- The ntfy Android app can pin a leaf certificate, and caddy's `tls internal` replaces its leaf every 12 h.
- facter's detected DHCP turns on systemd-networkd beside NetworkManager on pyrite's wifi (#3670).
- The evaluator's expected and always-on hosts come from magnetite's closure, so a host's flag changes alerting only after magnetite deploys (`review.md` F5).
- ntfy on cinnabar moved three minor releases through a nixpkgs bump with no review of the assumptions that name its version (`review.md` F4).
- An always-on host's silence posts about 15 min after its last sample, not 10, because the presence query sees a series until it leaves the store's 300 s lookback window, GreptimeDB 1.2.1's default, which magnetite does not override (`review.md` F9; `12.9-lookback-20261101T184133Z.log`).

## 6. Promote candidates → long-term learning

- [ ] [high] **An alert rule's metric names are read from a store that holds the series before the rule merges; a replay that returns nothing blocks the merge.** → **Promote to** skill (`preferences-observability-engineering`)
  > **Why**: the NVMe rules shipped with exposition names, the store's are `_total`, and the empty replay did not stop them (§2; #3669).
  > **How to apply**: S5's `HostProbeStale`, launchd rules and stibnite's NVMe series are named from a query of the store after stibnite's probe has written once, and the rules pull request waits for it.

- [ ] [high] **A pre-deploy probe of a vendored consumer runs that consumer's exact argument list, read from its source.** → **Promote to** skill (`writing-plans`, research step for vendor configuration)
  > **Why**: M10 read pyrite's SSD with `smartctl -j -H -A`, and the exporter's `--log=error` failed on the same controller (#3668).
  > **How to apply**: S5's stibnite probe reads `smartctl` and `launchctl` with the arguments its script will pass, recorded in the plan's grounding.

- [ ] [high] **Every repeating systemd calendar names its zone, held by an evaluation assertion.** → **Promote to** skill (`preferences-nix-development`)
  > **Why**: `*:0/5` skipped an hour on pyrite at the autumn change, and three of the four timers #3667 fixed are held by no check (`review.md` F6).
  > **How to apply**: the §12 assertion over the notified units' timers; S5's launchd `StartCalendarInterval` jobs state how they behave across a clock change.

- [ ] [high] **A table row that another host's closure reads changes that host too: the plan deploys both, and the runbook says so.** → **Promote to** schema (OpenSpec design template, Migration Plan)
  > **Why**: pyrite became an expected host only at a magnetite deploy made for other fixes (`review.md` F5).
  > **How to apply**: S5's stibnite row in `flake.lib.observabilityHosts` is followed by magnetite's deploy, as a tasks.md item.

- [ ] [high] **A world assumption that names a vendor version has a trigger that fires when the deployed version moves.** → **Promote to** skill (`preferences-requirements-engineering`)
  > **Why**: ntfy moved from 2.28.0 to 2.31.0 in a nixpkgs bump, and A39's own re-read trigger passed unnoticed (`review.md` F4).
  > **How to apply**: the operator decides whether cinnabar asserts ntfy's version; until then each slice's close-out compares the running version of every vendor its assumptions name.

- [ ] [med] **A notified unit that runs clauses at two cadences keeps each cadence's last verdict, so a passing run of one never resolves the other's failure.** → **Promote to** skill (`preferences-observability-engineering`)
  > **Why**: the 05 run resolves a budget failure posted at minute 00 while the breach stands (`review.md` F1).
  > **How to apply**: the §12 fix to `otel-envelope`; any S5 to S7 regulator that adds an hourly or daily clause to a 5-minute unit.

- [ ] [med] **A regulator clause iterates over the configured set it judges, not over the series it happens to find.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: C3 passes when no queue-size series exists (`review.md` F2).
  > **How to apply**: S5's darwin `otel-envelope` renders its exporters and targets from the evaluated configuration and fails on any without telemetry.

- [ ] [med] **Every alert or notice posted during a deploy window is read from the evaluator's and the notifier's journals and recorded with its cause.** → **Promote to** schema (OpenSpec tasks template, deployment verification)
  > **Why**: the four NVMe `RuleSignalMissing` posts of 2026-11-01 appear in no record (`review.md` F3).
  > **How to apply**: each S5 deploy item ends with `sudo journalctl -u fleet-alert -u 'observability-notify@*' --since <deploy start>` and a cause per post.

- [ ] [med] **An assumption's status in `verify.md` names what was observed; "holding" needs an observation of the assumption's own claim.** → **Promote to** schema (verify template, discharge coherence)
  > **Why**: A42's 168 h and A13's resume were stated as holding on evidence of 12 h and of network loss (`review.md` F7).
  > **How to apply**: S5's verifier writes "configured", "not violated" or "observed" with the window, for each assumption.

- [ ] [med] **A laptop's acceptance includes one suspend and resume while it collects.** → **Promote to** one-off (S5, stibnite)
  > **Why**: pyrite has not suspended since 2026-10-28, so the agent's behaviour after a resume is unobserved (`review.md` F13).
  > **How to apply**: S5's tasks.md gates a suspend and resume of stibnite with the operator present, and reads the queue, the timer and the probe after it.

- [ ] [med] **Each evidence log is read for anomalies beyond the line the step checks, before the next step runs.** → **Promote to** memory (type: feedback)
  > **Why**: the 5.1 presence log showed pyrite's two DHCP addresses three steps before they slowed 5.6 (#3670).
  > **How to apply**: the orchestrator reads each operator-sitting log whole before moving on.

- [ ] [low] **A timing statement in a requirement counts the store's lookback window.** → **Promote to** one-off (this change's §12, FA `A missing signal is itself reported`)
  > **Why**: the always-on silence posts about 15 min after the last sample, the store's 300 s lookback plus the evaluator's 10 min, and 9.2 met its bound by 25 s (`review.md` F9).
  > **How to apply**: done in this change's §12, where FA `A missing signal is itself reported` states 15 minutes.

- [ ] [low] **A migration flag's one-shot branches are removed in the change's close-out.** → **Promote to** schema (OpenSpec tasks template, close-out)
  > **Why**: cinnabar's `units = lib.mkIf (!collects)` and the text around it outlived the migration (`review.md` F10).
  > **How to apply**: S5's close-out lists each conditional its migration added and removes the ones that can no longer apply.

- [ ] [low] **A mutant runs only the case it must fail.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: each `otel-envelope` mutant reruns all 15 cases to judge one, in every nixbot build (`review.md` F11).
  > **How to apply**: the §12 fix; S5's darwin envelope check follows it.
