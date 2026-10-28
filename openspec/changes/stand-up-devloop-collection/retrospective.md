# Retrospective: stand-up-devloop-collection

> Written: 2026-10-28 (after 7.2 and 7.7 passed, while `verify.md` was being written; the precheck of `openspec instructions retrospective` needs `verify.md`'s Overall Decision)
> Commit range: `02e57cd69..03a95cf36`, filtered to the S2 paths (`git log 02e57cd69..03a95cf36 -- <S2 paths>`)
> Worktree: merged to main; the archive is pull request 7 (plan Task 8)

---

## 0. Evidence

- **Commit range**: `02e57cd69..03a95cf36`, 12 commits on the S2 paths in 10 pull requests: #3556 plan, #3557 (Task 1 and `d1500350b`, plan review F14 to F22), #3558 (Task 2 and `c6e9abe0e`, plan fixes for journal reads), #3559, #3560, #3561, #3562, #3563, #3564 and #3591.
- **Diff size**: +18866 / -366 lines across 66 files (`git diff --shortstat 02e57cd69 03a95cf36` over the change directory, `modules/system/deploy-record.nix`, `modules/nixos/devloop-collection.nix`, `modules/nixos/greptimedb.nix`, the `fleet-alert` module and check, `devloop-queries`, `otel-collector-config`, `devloop-ingest`, the `otel-collector` service, `modules/machines`, the runbook, `modules/README.md`, `modules/home/ai` and `docs/notes/development/observability`).
- **Plan size**: `plan.md` reached 698 KiB, over jj's 300 KiB `snapshot.max-new-file-size`, and was split without changing its wording into a 30 KB index and `plan/task-1.md` to `plan/task-8.md` (51 KB to 132 KB each).
- **Tasks done**: 65/71 (`grep -cE '^- \[x\]' tasks.md` → 65; `- [ ]` → 6: 8.1 to 8.5 and 9.1, which are this close-out).
- **Active hours**: not recorded; #3556 merged 2026-10-21T23:23Z and #3563 at 2026-10-22T04:05Z, so Tasks 1 to 6, five planned deploys and the unplanned D3B took about 4 h 45 min; #3564 merged at 05:10Z; 7.7 ran on 2026-10-28 (`gh pr view`; `logs/s2-evidence/window.env`).
- **Subagent dispatches**: not counted; at least 21 named `S2*` agents, among them `S2PlanReview` (tasks.md 1.1), `S2Task1` to `S2Task6`, `S2Review` (`review.md`), `S2ReviewFixes` (#3564), `S2Check77` (7.2, 7.7) and `S2Verify`.
- **New external dependencies**: none; the `sqlquery`, `journald` and `file_log` receivers are in the pinned otelcol-contrib 0.155.0, `devloop-queries` applies the existing nixbot input's migrations, and `postgresql_16` comes from the root nixpkgs pin.
- **Bugs encountered post-merge**: 1 shipped defect found by deployment verification: `journald/gitea-mq` read only the current boot, so `batch_event` held 282 of 772 retained lines at 7.4 (#3560, D3B); review F3, a false `FAILED devloop-reconcile` on a restarted build, was fixed in #3564 before it fired; reconcile's missing `cmp` was caught by `devloop-ingest` before #3561 merged.
- **OpenSpec validate state at archive**: `openspec validate stand-up-devloop-collection --strict` passed after #3564 (`review-c-validate-20261022T043418Z.log`); the archive-time state is plan Task 8 Step 16's.
- **Test coverage signal**: `checks.x86_64-linux.devloop-queries` against nixbot's migrations with the `selectError` and `errorUnderAlias` mutants; `otel-collector-config` with `logsToMetricsExporter` and `reconcileNotNotified`; `fleet-alert` with the burn-rule timeline leg, the two-database leg and `devloopFailureLeg` rejecting `everyQueryToFleet` and `allDatabasesFreeze`; `vmTests.x86_64-linux.devloop-ingest` with each of C1 to C7 failing on its named mutant (tasks.md 4.6, 10.7); six scheduled reconcile runs with seven `ok` lines each (tasks.md 7.7).

Commit chain (chronological):

```
02e57cd69 (base)
24572bd11 #3556 docs(observability): S2 dev-loop collection planning (brainstorm through plan, charter v22)
d1500350b #3557 docs(observability): apply the S2 plan review's remaining findings (F14-F22)
ea7cbf60c #3557 feat(deploy-record): record every activation on the ten machines, held by the x86_64-linux NixOS machine checks
c6e9abe0e #3558 docs(observability): S2 plan journal reads need sudo; pre-D2 check reads the collector log file
e94a1631e #3558 feat(devloop): the devloop allow-list, tables, pipelines and devloop-queries
4174473d5 #3559 feat(devloop): collect nixbot, gitea-mq and deploy records into devloop
3d2baf0ed #3560 fix(devloop): journald/gitea-mq reads every retained boot
70848c4f9 #3561 feat(devloop): daily devloop-reconcile against nixbot, the journal and the deploy record
a1b2aac08 #3562 feat(fleet-alert): per-rule database and language, SQL rules and the dev-loop burn rule
beea76ff4 #3563 docs(observability): S2 devloop runbook, collector logs path, check index and skill line
a106c086f #3564 fix(devloop): apply the S2 post-deployment review (F2-F10)
03a95cf36 #3591 docs(observability): S2 F1 disposition: updater bursts explain burn-rule firings; ticks 6.4, 6.5, 7.5
<close-out: verify, review, retrospective; archive: pull request 7, plan Task 8 Steps 16-22>
```

---

## 1. Wins

- [evidence: tasks.md 1.1; `logs/s2-evidence/1.1-plan-review-20261021T232002Z.md`] S2 is the first slice to run the holistic review over its plan before Task 1, as S1 and S3 promoted; it found 22 problems, one high, nine medium and twelve low, all accepted and applied before the code they concerned was written.
- Among them: F1, nixbot's restart resets `started_at` and keeps `created_at`, so reruns would have counted as slow builds; F3, a logs pipeline could bypass the allow-list through the metrics exporter; F7, one failing `devloop` query would have frozen every fleet alert, which became the per-database freeze of tasks.md 5.4.
- [evidence: tasks.md 7.4; `review.md` "Measured and checked"] The data path is exact on the real store: `ci_attribute` held 203,061 rows, equal to its distinct keys and to nixbot's joined finished attributes, and `batch_event` and `deploy_record` held no duplicate.
- [evidence: tasks.md 7.7; `7.7-reconcile-20261028T210531Z.log`] `devloop-reconcile` passed all of C1 to C7 on each of the six scheduled runs since D4, with no `FAILED` posted outside 7.5's forced failure.
- [evidence: tasks.md 7.5; `7.5-forced-fail-20261022T023227Z.log`, `7.5-forced-resolve-20261022T023301Z.log`] The regulator's failure path was shown live: `FAILED devloop-reconcile.service on magnetite` reached `fleet-alerts` at 02:32:30Z and its `RESOLVED` at 02:33:04Z.
- [evidence: tasks.md 7.7; `7.7-join-20261028T210618Z.log`] A deploy is attributable to its commit: D5's one deploy-record line joins through `ci_attribute.outputs_out` of `checks.x86_64-linux.nixos-magnetite` to `a1b2aac08`, the `D5_COMMIT`.
- [evidence: tasks.md 7.7; `7.7-questions-20261028T210554Z.log`] The three questions answer from the store: 22 batches with formation-to-land, queue wait p50 223 s, p90 3,939 s and p99 4,859 s over 82 builds, and 103 build outcomes.
- [evidence: `4.6-devloop-ingest-20261022T014655Z.log:3773`] The container test ran the real reconcile unit and caught `cmp: command not found`, which made every C3 comparison fail on equal counts, before #3561 merged.
- [evidence: tasks.md 2.7; `2.7-precheck-20261022T003015Z.log`] The pre-D2 compile check on a throwaway store (plan review F5) passed the four tables, four pipelines and one OTLP write per table before D2 touched the production store.
- [evidence: `8.1-eval-cost-20261028T211215Z.log`] Every changed check stays under 0.5 GiB at `697a6f1ea`: `devloop-queries` 135,629,648 B, `fleet-alert` 339,763,552 B and `otel-collector-config` 488,431,056 B.
- [evidence: `review.md:3-7`] The post-deployment review found nothing critical; F2 to F10 landed in #3564 with tasks.md 10.1 to 10.9, and F1 has the operator's decision O3 in #3591 (tasks.md 10.10).

## 2. Misses

- [high] [blocking | evidence: #3560; tasks.md 3.3, 7.4] `journald/gitea-mq` read only the current boot: systemd 261 limits `journalctl --follow` to the current boot, and the receiver always follows, so at 7.4, after D3, `batch_event` held 282 of the 772 retained `gitea-mq` batch lines.
- Root cause: neither the plan's upstream reading nor `devloop-ingest` covered more than one boot; the container boots once and its stub prints in that boot, so only the deployed host's retained history could show it.
- #3560 added the `--boot=all` wrapper with an argument check that fails when the wrapper is removed (`3.12-devloop-ingest-red-20261022T014502Z.log`), D3B deployed it and the cursor reset backfilled the history; the argument check guards the wrapper, not the behaviour across a boot, which only the 2026-10-24 scheduled reconcile tested, passing C3 for a day that spans magnetite's reboot of 2026-10-23 (tasks.md 7.2, 7.7).
- [high] [painful | evidence: #3556; plan.md task map] The plan was too large for jj: at 698 KiB `plan.md` exceeded the 300 KiB snapshot limit, about 400 KiB of it complete code that the pull requests then wrote again, and the plan review needed four sub-reviewers to read it.
- It was split per task into `plan/task-1.md` to `plan/task-8.md` with its wording unchanged, so the size and the duplicated code remained, split; S3's 412 KiB plan had already needed the same jj override.
- [med] [painful | evidence: `1.1-plan-review-20261021T232002Z.md:102-127`; `d1500350b` in #3557] Nine of the 22 plan-review findings, F14 to F22, were not in the reviewer's summary to the orchestrator, which decided F1 to F13 from the summary and found the other nine only by reading the file.
- #3556 merged before their edits were ready, so the planning pull request carried a plan with nine accepted findings unapplied and `d1500350b` rode in Task 1's pull request.
- [med] [painful | evidence: `review.md` F4 to F6, F8] Clauses that restate the line they judge appeared a third time, after S1 F7 and F9 and S3 F3 and F5 to F7: `devloop-queries`' result-header clauses compared the allow-list with itself, the marker clause's two controls tested `lib.hasInfix`, the property-level `allDatabasesFreeze` rehearsal never reached the property it named, and two mutant legs judged only the clause name.
- The plan review had listed each clause's two value sources (tasks.md 1.1) and did not flag these, because the two sources were named but not traced to their definitions; #3564 deleted or tightened each one (tasks.md 10.3 to 10.5, 10.7).
- [med] [painful | evidence: `review.md` F1; tasks.md 10.10; `7.7-posts-20261028T210818Z.log`] Every firing of `PullRequestQueueWaitBurn` so far is the flake updater's own burst: the review's replay found five in 15 days, each from a burst of `app/vanixiets-flake-updater` pull requests, and the first live firings, 2026-10-24T00:32Z (#3583 to #3588) and 2026-10-28T00:35Z (#3622 to #3627), were the same.
- Root cause: design D1 calibrated the threshold on nixbot's history ("4 of 14 days breached", `logs/s2/grounding.md` §1.6) without asking who opened the slow builds, and `ci_build` holds no author or head ref, so the rule cannot tell them apart.
- The operator kept the rule and the per-input pull requests (O3, 2026-10-24), because `mic92/update-flake-inputs` cannot group inputs and a combined pull request would let one failing input hold back every update; the runbook names an updater run as the expected cause, and a real regression will arrive as one more instance of a routine warning.
- [med] [painful | evidence: orchestrator transcript, 2026-10-21] The orchestrator broke the development join twice: `jj rebase -r` on one of the join's parents moved only that commit, so the join was re-parented onto the stale copy it then abandoned, and a loop abandoning `divergent() & mutable()` copies also abandoned `96e4d741`, another agent's live copy of `nokqkqqp`, dropping that agent's chain from the join until it was restored.
- It also normalised the join only when its own watchers saw a merge, so another agent's merge left the join on a stale parent.
- In response it ran a join normaliser as a service (`logs/join-normaliser.sh`, git-ignored): it fetches every 60 s, abandons a divergent copy only when its change is in `main`, never rewrites immutable commits, rebases each open chain's root onto `main`, rebuilds the join from the open tips and stops with `STOP` on any conflict or divergence; it then kept the join on `main` through the rest of S2.
- [med] [painful | evidence: `S2Task4`'s report; #3561] `S2Task3`, fixing `--boot=all`, and `S2Task4` edited one working copy at the same time, so Task 4's files held Task 3's hunks, its squash had to select hunks interactively, and its green `devloop-ingest` run was on the combined tree.
- [med] [painful | evidence: plan Task 8 Step 2; `logs/s2-evidence/window.env`] Step 2's arrival watch, which had to start when Task 5's pull request opened, was never started: `window.env` has no `PR5` and there is no `9.1-arrival-watch` log, so 9.1's 10-minute arrival is measured on a substitute build (`verify.md` §10.1).
- Root cause: a step that belongs to Task 5's time lived in Task 8's plan file and in no tasks.md item, and after the split nobody reading Task 5's file saw it.
- [low] [painful | evidence: `c6e9abe0e` in #3558; `7.6-burn-history-20261022T034545Z-superseded-gnu-date.log`; `7.7-reconcile-20261028T210424Z-superseded-gnu-date.log`; `7.2-boot-record-20261028T210726Z-superseded-uptime-s.log`; `7.7-join-20261028T210618Z.log`] The plan's verification scripts failed on the hosts again and again, and every case was a shell or tool difference the plan had not run:
  - 2.7's unprivileged `journalctl` read nothing ("No journal files were opened due to insufficient permissions"), which S3 had also recorded, and its cleanup `status=$?` aborted in magnetite's zsh, where `status` is read-only;
  - 7.6 and 7.7 called BSD `date -j`, but GNU `date` came first on the operator's `PATH` on stibnite (S3 §2 recorded the same);
  - 7.2 used `uptime -s`, which magnetite's `uptime` lacks, and the boot time came from `/proc/stat` `btime` instead;
  - 7.7 Step 30's `jq` stopped on the notifier's untitled `RESOLVED fleet-alert.service` post, and `7.7-posts-20261028T210818Z.log` recounted with a filter that accepts a null title.
- None changed a verdict; each cost a rerun, and the superseded logs are kept.
- [low] [painful | evidence: tasks.md 1.5; plan review F9] The deploy-record snippet is on all ten machines, but CI holds the obligation only on the five x86_64-linux NixOS machine checks (cinnabar, electrum, galena, magnetite, pyrite); the four darwin machines and the deferred scheelite were shown once by evaluation in Task 1 (`1.4-activation-20261021T232805Z.log`) and are not held by CI.
- [low] [painful | evidence: `7.7-posts-20261028T210818Z.log:6,14-20`; `logs/magnetite-20261025-103632.log:1468-1519`] On 2026-10-25 a `FAILED fleet-alert.service` notice was lost: at 14:38:00Z a magnetite deploy stopped `zerotierone`, so the evaluator's run failed and `observability-notify@fleet-alert.service.service` could not post and failed too.
- About 75 s later the deploy's retried `switch-to-configuration` ran `reset-failed`, which cleared the notifier's failure inside `SystemdUnitFailed`'s 5-minute `for`, so nothing reported it and the notice was never retried.
- That is the specified behaviour, but the collector README and the runbook said a failed notice is always retried; this close-out corrects them (collector README `:164-165`, runbook `:125`, `:154-155`, `:323-324`).
- The second failure, at 16:09:07Z, came from a cinnabar deploy stopping `ntfy-sh`, `caddy` and `zerotierone` from 16:08:47Z to 16:09:04Z; the notifier's journal shows its `FAILED` post arrived, followed by the `RESOLVED` at 16:10:02Z.
- [low] [nit | evidence: tasks.md 7.7; operator decision 2026-10-28] The acceptance window was six scheduled reconcile runs, not the planned week, by the operator's decision.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| plan | `plan.md` split into an index and `plan/task-1.md` to `plan/task-8.md`, wording unchanged | 698 KiB exceeded jj's 300 KiB snapshot limit (§0) |
| 1.1 | F14 to F22 applied in `d1500350b`, landed with #3557 instead of #3556 | the orchestrator decided them only after #3556 merged (§2) |
| 2.7, 7.x | journal reads under `sudo`; the pre-D2 check reads the collector's log file | unprivileged `journalctl` on magnetite reads nothing (`c6e9abe0e`, #3558) |
| 3.3 (new #3560, D3B) | `journalctl_path` wrapper adding `--boot=all`, a sixth deploy and a journald cursor reset | systemd 261's `--follow` reads only the current boot; 7.4 Step 13 failed (§2) |
| 4.2 | `diffutils` added to the reconcile's runtime inputs | `cmp` is not on a NixOS unit's `PATH` (`4.6-devloop-ingest-20261022T014655Z.log:3773`) |
| 6.4, 6.5, 7.5 | ticked in #3591 | 6.4 needed stibnite's activation after #3563; 7.5's first scheduled run was 2026-10-23 |
| 7.2 | observed at the natural reboot of 2026-10-23, boot time from `/proc/stat` `btime` | magnetite's `uptime` has no `-s` |
| 7.6, 7.7 | rerun with `/bin/date` | GNU `date` came first on stibnite's `PATH` |
| 7.7 | six scheduled reconcile runs instead of a week; post counts from `7.7-posts-20261028T210818Z.log` | operator decision 2026-10-28; Step 30's `jq` stopped on an untitled post |
| 8.4 | the requirement count compared with `openspec list --specs --json` | `openspec validate --specs --json` counts specs, not requirements (plan Task 8 Step 17) |
| 8.5 | `openspec validate --specs --strict` judged as every S2 capability but `world-assumptions` passing and no spec newly failing | main failed it on 17 of 22 specs before S2 (plan Task 8 Step 16) |
| 9.1 | arrival within 10 minutes measured on a substitute build | Step 2's watch was never started for pull request 5 (§2; `verify.md` §10.1) |
| 10 (new) | section 10, 10.1 to 10.10 | review F1 to F10 (`review.md`; #3564, #3591) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, `logs/s2/brainstorm-prep.md`) |
| superpowers:writing-plans                        | yes (`plan.md` and `plan/`) |
| superpowers:using-git-worktrees                  | yes (deployments from fresh worktrees of `origin/main` through `s2-deploy.sh`, tasks.md 1.7, 2.9, 3.11, 4.8, 5.8) |
| superpowers:subagent-driven-development          | yes (`S2Task1` to `S2Task6`; two of them shared one working copy, §2) |
| (transitive) superpowers:test-driven-development | yes (red and green logs throughout tasks.md 1 to 5 and 10) |
| (transitive) superpowers:requesting-code-review  | partial: the codex sub-step was replaced, as in S1 and S3 |
| superpowers:finishing-a-development-branch       | pending (plan Task 8 Steps 16 to 22) |

### S1 and S3 rules applied in S2

The `:<line>` cells cite the rule's line in S1's (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/retrospective.md`) and S3's (`openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/retrospective.md`) retrospective as read on 2026-10-21.

| Rule | Source | Applied in S2 | What it caught |
|---|---|---|---|
| Read the upstream source behind a vendor option before depending on it | S1 §6 `:132` | yes: pins and citations for otelcol-contrib `sqlquery`, `journald` and `file_log`, nixbot's migrations, gitea-mq's messages and GreptimeDB's pipelines (1.1 review header) | F1 (nixbot's restart keeps `created_at`), F4 (a pipeline error is a 400 for the whole request), F6 (`nixbot.service` is not a notify unit), F16 (both receivers advance their cursor before delivery); later `rerun_exec.py`'s deletions (10.2) and `update-flake-inputs`' grouping (10.10); missed systemd 261's current-boot `--follow` (#3560) |
| Each new producer has a start-order relation and a check for it | S1 §6 `:136` | yes: R3.1's ordering clause and `schemaOrderDropped` (3.6); `devloop-ingest`'s `noAutoCreate` (3.9) | nothing at deploy; F6 found at plan time that the grant unit's ordering after `nixbot.service` did not imply the migrations had run |
| Runtime tests start dependent units together and assert no dropped data | S1 §6 `:140` | yes: every ingest case asserts `otelcol_exporter_send_failed_log_records` is zero after the first send (3.9) | the reconcile's missing `cmp` (#3561); missed the current-boot read, since the container has one boot |
| A clause relates independently defined values; a property of one module is an assertion | S1 §6 `:144`, S3 §6 `:158` | yes: value sources named per clause in 1.1 for 1.5, 2.6, 3.6, 4.5; the journal-read (3.7), R8.2 and kill-order (4.4) assertions shown failing by `extendModules` overrides | the review still found F4 to F6 and F8 (§2) |
| Measure each new check's evaluation cost against a budget, with `.#.checks…` and the method | S1 §6 `:148`, S3 §6 `:154` | yes: each task's figure and Step 7's re-measurement (`verify.md` §9.1) | nothing over budget; `otel-collector-config` is at 91.0 % (488,431,056 B), about 48 MB below 0.5 GiB |
| Every runtime regulator clause has a negative control on a real store | S1 §6 `:152` | yes: C1 to C7 each failed by a `devloop-ingest` mutant (4.6); 7.5's forced `devloop_absent` failure | each control failed as named; F8 found two mutant legs judging only the clause name |
| `nix fmt` with its log before every commit | S1 §6 `:156` | yes: 1.6, 2.8, 3.10, 4.7, 5.7, 6.5 and `review-c-fmt-20261022T043211Z.log` | nothing |
| Operator documentation is a task in the documenter gate's scope | S1 §6 `:160` | yes: group 6 (#3563) and plan Task 8 Step 14 | the review's F9 found seven places where the docs had drifted from the deployed behaviour (10.8) |
| Holistic review of the planned regulators before Task 1 | S1 §6 `:164`, S3 §6 `:162` | yes: tasks.md 1.1 | 22 findings, all applied; nine reached the orchestrator late (§2); the post-merge review still found ten, one significant |
| Check each slice's rules against the later slices that touch the same objects | S1 §6 `:168` | yes: design.md "Later slices" (S4, S6, S7, S8) | F16: the `sqlquery` cursor is keyed by the query text, so an S4 or S7 allow-list column re-backfills about 200,000 rows; S4's O2 reuses S2's logs path for agents' deploy records |
| Notifier and regulator semantics tested across restart and cache-fill states | S1 §6 `:172` | yes: `devloop-ingest`'s overlap and switch cases; 7.4's collector restart (`7.4-restart-20261022T013238Z.log`) | the restart re-sent nothing; missed the reboot case (#3560) and a restarted build's deleted attributes (F3, 10.2) |
| Resolve the designation-lint nouns at sync | S1 §6 `:176`, S3 §6 `:182` | yes: the 35 rows S2's `world-assumptions` delta adds | `verify.md` §8a |
| Record the operator's reason whenever a planned gate is replaced | S1 §6 `:180` | yes: `review.md:3` | — |
| A reference model is written from the specification's scenarios | S3 §6 `:142` | yes: the burn-rule timeline leg from the `fleet-alerting-interface` scenario `The timeline is replayed`, before any evaluator change (5.1) | F14 added the re-post window and the 1 h boundary at plan time; the review found the leg uses the spec's literals, not `rules.nix` |
| A shared clan var gains a reader with `clan vars fix`, never `clan vars generate` | S3 §6 `:146` | not applied: S2 adds no var, and `devloop-reconcile` loads the existing `regulator-password` | — |
| A human step a later observation depends on is its own gated step | S3 §6 `:150` | not applied: no later observation depended on a human step, since 7.2 became opportunistic (plan review F18) | 6.4's delivered skill line waited two days for the operator's activation of stibnite |
| Each slice names the regulator its own silence modes need | S3 §6 `:166` | yes: `devloop-reconcile`'s C4 batch liveness for a silent gitea-mq; `RuleSignalMissing` does not cover `devloop` | nothing: no silence in the six scheduled runs |
| Schedule CAM-76's watch before S5 | S3 §6 `:170` | not S2's; the charter's S4 entry (`charter.md:380`) keeps CAM-76 before S5 and lets S4 proceed first; Linear was not read for this file | — |
| S2 adds a per-rule `database` to the rule table, the fixture server and `promtool` | S3 §6 `:174` | yes: tasks.md 5.1 to 5.5 and 10.5 | F7 at plan time: one failing database froze every alert, so 5.4 freezes per database; on 2026-10-25 both databases were frozen separately |
| A long-running evidence capture runs on an always-on host | S3 §6 `:178` | not applied: Step 2's arrival watch on magnetite was never started (§2) | — |
| A requirement ending on a person's device names one delivered message with its time | S3 §6 `:186` | yes: 7.5's `FAILED devloop-reconcile.service on magnetite` at 02:32:30Z and its `RESOLVED` at 02:33:04Z, with `T_FORCED_FAIL` and `T_FORCED_RESOLVE` | — |

### Deliberately Skipped Skills

- **`superpowers:requesting-code-review`**
  - **What was skipped**: the roborev sub-gate, a paid `codex exec` review (tasks.md 8.2).
  - **Why this cycle**: the operator declined the paid codex review for the whole program and asked for one holistic Opus subagent review instead, as in S1 and S3 (`review.md:3`).
  - The substitute found nothing critical and ten findings, each with a disposition (`review.md:9-23`).
  - **How to prevent recurrence**: no recurrence to prevent; the plan-time review (tasks.md 1.1) now precedes it.

## 5. Surprises

- systemd 261 limits `journalctl --follow` to the current boot, and otelcol-contrib's `journald` receiver always follows, so a receiver without `--boot=all` reads only one boot's history (#3560).
- A `writeShellApplication` used as a NixOS unit gets its `runtimeInputs` plus systemd's default service `PATH`, which has no `diffutils`, so `cmp` was missing only when the unit ran (`4.6-devloop-ingest-20261022T014655Z.log:3773`).
- nixbot deletes a restarted build's finished attributes for systems it no longer builds (`Mic92/nixbot@d020013fa:nixbot/nixbot/rerun_exec.py:83-92`), so a copy that compares with nixbot's current rows sees keys vanish (review F3, 10.2).
- `switch-to-configuration` leaves a `RemainAfterExit` oneshot alone when its unit text is unchanged, so "once per activation" was false and a spec SHALL said so (review F2, 10.1).
- `ci_build.branch` is the base branch for a pull-request build, so neither the store nor the burn rule can tell the flake updater's pull requests from a person's (review F1).
- A reviewer's summary can omit findings its file holds: F14 to F22 were in `1.1-plan-review-20261021T232002Z.md` and not in the summary (§2).
- `jj rebase -r` on a parent of a merge commit moves only that parent's commit and re-parents the merge onto its old parent.
- magnetite's login shell is zsh, where `status` is read-only, and its `uptime` has no `-s`; stibnite's `PATH` puts GNU `date` before `/bin/date`.
- The notifier's `FAILED` and `RESOLVED` posts carry no title, which a `jq` filter on `.title` does not expect (`7.7-posts-20261028T210818Z.log:1`).
- A deploy's retried `switch-to-configuration` runs `reset-failed`, which can clear a failed notifier instance before `SystemdUnitFailed` reports it, so a notice refused during a deploy window is lost (§2).

## 6. Promote candidates → long-term learning

- [ ] [high] **Any reader of the journal or of a rotated file is tested across at least two boots or rotations, and its first deploy compares its count with the host's whole retained history.** → **Promote to** skill (`nix-flake-pr-cycle`, container-test guidance)
  > **Why**: `devloop-ingest` boots once, so the current-boot read passed it and failed only at 7.4 after D3 (#3560).
  > **How to apply**: in S4, `file_log/deploy-record` moving into the agent role gets, per agent host, a first-deploy comparison of `/var/log/deploy-record.jsonl`'s line count with that host's `deploy_record` rows, and any S7 journald reader a fixture journal spanning two boots.

- [ ] [high] **A unit script's tools are all in its `runtimeInputs`, and the unit is run, not only built, in a container test before merge.** → **Promote to** skill (`preferences-nix-development`)
  > **Why**: `cmp` was absent from the reconcile unit's `PATH` and only running the unit in `devloop-ingest` showed it (#3561).
  > **How to apply**: S4's `otel-envelope` unit and timer list every binary they call in `runtimeInputs` and run once in a container or VM test whose log the pull request names.

- [ ] [high] **A plan's verification commands name their interpreter and their tools: `bash -c` on hosts whose login shell is zsh, `/bin/date` or `gdate` explicitly on stibnite, `/proc/stat` `btime` for a boot time, `sudo` for journal reads, and `jq` filters that tolerate a missing field.** → **Promote to** skill (`writing-plans`, deployment verification steps)
  > **Why**: 2.7, 7.2, 7.6 and 7.7 each needed a rerun for one of these, and S3 §2 had recorded the `date` and `journalctl` cases already (§2).
  > **How to apply**: S4's plan runs each verification command block once against cinnabar, magnetite and pyrite as a rehearsal before its first deploy, and records the rehearsal log beside the plan review.

- [ ] [high] **A plan file stays under jj's 300 KiB snapshot limit by holding steps, interfaces and expected output, not complete code, and is written per task from the start.** → **Promote to** skill (`writing-plans`)
  > **Why**: S2's 698 KiB plan, mostly code the pull requests wrote again, was split rather than trimmed, and S3's 412 KiB plan needed the same override (§2).
  > **How to apply**: S4's plan is an index plus `plan/task-<n>.md` files, each under 300 KiB, with full code only for the fragments that are hard to get right (the mTLS receiver, the certificate generators, the R3.1 endpoint clause).

- [ ] [high] **The orchestrator decides plan-review findings from the findings table, and the planning pull request is not enqueued until the dispositions table has one row per finding id.** → **Promote to** skill (`agentic-planning-development-workflow`, plan-review gate)
  > **Why**: F14 to F22 were missing from the reviewer's summary and were applied a pull request late (§2).
  > **How to apply**: before S4's planning pull request, `rg -c '^\| F[0-9]+ ' <review>` under Findings equals the row count under Dispositions.

- [ ] [high] **A clause's two value sources are traced to their definitions; if both are rendered from one Nix attribute, the clause is a restatement and is not written.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: S2's plan review named every clause's sources and still passed `devloop-queries`' header clauses, both rendered from `tables.<t>.columns`; this is the third slice with the pattern (review F4 to F6, F8).
  > **How to apply**: S4's R3.1 clause that the ingress endpoint equals "the registry address and the certificate's IP SAN" (S4 proposal) compares the evaluated receiver endpoint with the certificate generator's SAN as read from its output, not two renderings of `flake.lib.hosts.magnetite.zt`.

- [ ] [high] **Never `jj rebase -r` a parent of the join, and abandon a divergent copy only when its change is in `main`; a normaliser keeps the join on `main` when anyone's pull request lands.** → **Promote to** skill (`jj-version-control`, `hazards.md`)
  > **Why**: both mistakes broke the join on 2026-10-21, one dropping another agent's chain (§2).
  > **How to apply**: move parents with `-s` or `-b`; run the join normaliser's rules as committed tooling rather than the git-ignored `logs/join-normaliser.sh`, and in S4 start it before the first implementation task.

- [ ] [med] **A new alert rule is replayed against the stored history before it ships, and each would-be firing is attributed to its cause; a rule whose firings are all one known cause needs a decision before deploy, not after.** → **Promote to** skill (`preferences-observability-engineering`)
  > **Why**: every firing of `PullRequestQueueWaitBurn`, replayed and live, was a flake-updater burst, found only by the post-deployment review (review F1; O3).
  > **How to apply**: S4's `FilesystemFillingWarn`, `FilesystemFull` and cinnabar's absence rule are replayed over `fleet`'s retained history for cinnabar, magnetite and pyrite, and the plan records each would-be firing with its cause.

- [ ] [med] **Concurrent implementation subagents each get their own jj workspace or run in sequence; two never edit one working copy.** → **Promote to** skill (`subagent-driven-development`)
  > **Why**: `S2Task3` and `S2Task4` shared one working copy, so #3561's green run was on a combined tree and its squash selected hunks by hand (§2).
  > **How to apply**: S4's tasks that may overlap (certificate generators and the agent role) run in sequence or in separate `jj workspace add` copies.

- [ ] [med] **A step that must start during an earlier task is a tasks.md item in that task's group.** → **Promote to** schema (OpenSpec tasks template)
  > **Why**: plan Task 8 Step 2 had to start when Task 5's pull request opened and never ran, so 9.1's arrival was measured on a substitute (§2).
  > **How to apply**: S4's per-host first-deploy captures are tasks.md items in the deploy group that starts them.

- [ ] [med] **`otel-collector-config` is at 91.0 % of its 0.5 GiB budget; S4's per-host relations are fragment or host assertions, and the check is measured before and after each S4 task.** → **Promote to** one-off (S4 design D7)
  > **Why**: 488,431,056 B at `697a6f1ea` leaves about 48 MB (`8.1-eval-cost-20261028T211215Z.log`), and S4 adds agent hosts to the evaluated configurations.
  > **How to apply**: S4's tasks.md records `otel-collector-config`'s figure with the `.#.checks…` method at each task, and a figure over 0.5 GiB stops the task.

- [ ] [med] **S4's allow-list or query edits re-key the `sqlquery` cursor, which re-backfills about 200,000 rows.** → **Promote to** one-off (S4 design, Risks)
  > **Why**: the cursor key embeds the query text (plan review F16), and S4 changes `devloop-collection.nix` (S4 proposal, O2).
  > **How to apply**: S4 leaves the two `sqlquery` queries' text unchanged, or schedules the re-backfill on a deploy day and records the day's row-budget exceedance as S2's D3 did.

- [ ] [med] **Hold the deploy-record obligation on the darwin machines and scheelite, not only on the five x86_64-linux NixOS machine checks.** → **Promote to** one-off (S5, which adds the darwin hosts)
  > **Why**: CI holds the obligation on five of ten machines, and the other five were shown once by evaluation in Task 1 (§2; plan review F9).
  > **How to apply**: S5 adds an evaluation of each darwin configuration's `deployRecordObligations` to a check nixbot runs, or records why best-effort darwin checks suffice.

- [ ] [med] **The sync-order decision of tasks.md 8.3 binds both sibling changes: each rebuilds its `Grounded vocabulary for behavioral requirements` block on S2's synced main before its own sync.** → **Promote to** one-off (`stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite`)
  > **Why**: both still MODIFY the block from a copy that predates S1's, S3's and CAM-77's syncs, and `stand-up-gitea-mq-on-magnetite` adds `batch`, `merge queue` and `pull request` under S2's term and sense with different text (plan Task 8 Step 4).
  > **How to apply**: the decision and the operator's answer are in `verify.md` §10.6; each sibling's archive runs Step 4's row check against main first.

- [ ] [low] **Should the notifier retry its own post, for example with `Restart=on-failure` and a delay, so that a refusal during a deploy window is not lost?** → **Promote to** design question (a later slice or CAM-76)
  > **Why**: on 2026-10-25 a magnetite deploy stopped `zerotierone`, the notifier's post failed, and the deploy's `reset-failed` cleared the failure inside `SystemdUnitFailed`'s 5-minute `for`, so the `FAILED fleet-alert.service` notice never arrived (§2).
  > **How to apply**: it needs a spec change to the failure-notice requirement; until then the corrected collector README and runbook state that a notice refused during a deploy can be lost.

- [ ] [low] **Three review suggestions were not taken: removing the fixture server's wrong-database and SQL-shape controls (F6), a runbook note to replay `sqlquery` only while the store is up, and reindexing nixbot's pre-existing collation mismatch.** → **Promote to** one-off
  > **Why**: the first two are optional and the third lies outside S2 (`review.md:23`).
  > **How to apply**: run `REINDEX` and `ALTER DATABASE nixbot REFRESH COLLATION VERSION` on magnetite as its own change, and add the replay note when the runbook's `devloop` section is next edited.

- [ ] [low] **The burn rule's routine updater firings are the first thing to revisit if a person or the updater changes.** → **Promote to** memory (type: project)
  > **Why**: O3 keeps a warning about twice a week whose only cause so far is the updater (tasks.md 10.10).
  > **How to apply**: if `mic92/update-flake-inputs` gains input grouping or `ci_build` gains an author column (S7, S8), reopen review F1's options.
