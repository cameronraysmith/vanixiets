# Retrospective: stand-up-darwin-collection

> Written: 2026-11-08, for tasks.md 9.3, after `review.md` (the holistic review of 2026-11-07) was applied as tasks.md §11 in #3778, while the close-out (9.1, 9.2, 9.4 to 9.6 and 10.1) is in progress
> Commit range: `741e0ecdc^..1ebfa1307`, filtered to the S5 paths (`git log 741e0ecdc^..8947f3f42 -- <S5 paths>`, merge commits and other changes' commits excluded)
> Worktree: merged to main through #3778 (`8947f3f42`); the archive is tasks.md 9.6

---

## 0. Evidence

- **Commit range**: `741e0ecdc^..1ebfa1307`, 13 commits on the S5 paths in 13 pull requests: #3731 plan, #3733 the plan review's corrections, #3736, #3738, #3739, #3740, #3741, #3743, #3744, #3745, #3771, #3772 and #3778 (`gh pr view`).
- **Diff size**: +10,179 / -743 lines over 93 distinct files, summed from `gh pr view --json additions,deletions,files` over the 13 pull requests; none touches `flake.nix` or `flake.lock`.
- **Plan size**: `plan.md` is a 17,971 B index and `plan/task-1.md` to `plan/task-9.md` hold 8.6 KB to 71 KB each (`plan/task-2.md` the largest), all under jj's 300 KiB snapshot limit.
- **Tasks done**: 63 of 72 in the working copy's tasks.md when read (`grep -cE '^- \[x\]'` → 63; `- [ ]` → 9: 6.1a, 8.1, 9.1 to 9.6 and 10.1).
- **Acceptance status, 6.1a**: closed under operator decision O2 of 2026-11-07 (not design.md's O2 of 2026-11-05): `org.nixos.nix-cleanup-gcroots` was kickstarted at 2026-11-08T00:12:53Z instead of waiting for its calendar run, so launchd's calendar trigger is not exercised (`6.1a-kickstart-20261108T001253Z.log`).
- **Acceptance status, 8.1**: closed under operator decision O2 of 2026-11-07: judged over 2026-11-07T08:24Z to 2026-11-08T00:30Z, about 16 h, instead of 24 h (`8.1-day.sh`, its O2 window `1794039840 1794097800`).
- **Close-out**: 9.1 to 9.6 and 10.1 are in progress; `verify.md` holds the open slots for 6.1a and 8.1 (`verify.md` §9.3).
- **Active hours**: not recorded; #3731 merged 2026-11-05T23:16Z, #3736 at 2026-11-06T02:55Z, #3745 at 22:52Z, #3771 at 2026-11-07T19:22Z and #3778 at 22:53Z (`gh pr view`).
- **Subagent dispatches**: not counted in the change folder; the plan review (tasks.md 1.1) and the holistic review (tasks.md 9.3) are each recorded as one read-only Opus subagent.
- **New external dependencies**: none in the flake; on stibnite the root pin's `otelcol-contrib` and nix-darwin's node_exporter now run as launchd daemons, and the probe reads `disk0` with smartmontools 7.5 (design.md:340; `5.3-stibnite-20261106T052005Z.log`).
- **Bugs encountered post-merge**: 3 shipped defects found by deployment verification: #3740 (C5 bounded resident size, not physical footprint), #3744 (the 64 MiB process floor let 63 names an hour through on stibnite) and #3771 (`LaunchdJobNotRunning` posted twice for one booted-out kept-alive job); `review.md` found 19 more, four significant (F1, F2, F3, F18), all applied or deferred by tasks.md §11.
- **OpenSpec validate state at archive**: `openspec validate stand-up-darwin-collection --strict` passed on 2026-11-07 after tasks.md §11 (`11-discharge-20261107T221833Z.log`; `verify.md` §1); the archive-time state is tasks.md 9.6's.
- **Test coverage signal**: `checks.x86_64-linux.otel-collector-darwin` (new) with the mutants `nodeListenEmpty`, `seventhIdentityAttribute`, `processEndpoint`, `diskIncludeAll`, `exporterAddressOther`, `labelDotUnescaped`, `aliasDropped`, `pidWritten`, `missingExitCodeAsZero`, `idleExitAsFailure`, `postEveryFailure`, `keepListIgnored`, `agentLimiterRaised`, `processSpikeRaised`, `c5LimitsSwapped`, `c5AgentLimitChanged` and `otlpFeedsLogs`; `otel-envelope` with six darwin cases and `c5WrongPid`, `c5ReadsRss` and `c5UnreadablePasses`; `fleet-alert` with the legs `pendingAcrossFreeze`, `pendingAfterWake`, `linuxSelectorDarwinOnly`, `stibniteNotCollecting`, `darwinSignalMissing`, `keptAliveStopped`, `envelopeUnloaded`, `envelopeFailedNotReported`, `harmoniaFailedReported`, `restartLoop`, `probeStale`, `nvmeExpectsStibnite`, `stibniteSilent` and `keptAliveUnloaded`, and the mutant `notRunningBothArms`; the darwin fragment's assertions shown failing by the overrides `queue64`, `queues600`, `probeCalendar`, `omnigentNobody`, `nodeWildcard` and `envelopeCalendar` (`2.6-assertions-20261106T010311Z.log`, `3.4-envelope-daemon-20261106T023426Z.log`, `6.3-rules-20261106T151156Z.log`, `8.3a-green-20261107T185455Z.log`, `11-checks-20261107T221356Z.log`).

Commit chain (chronological):

```
741e0ecdc #3731 openspec: plan stibnite's collection on darwin
7ec87f75e #3733 openspec: correct the darwin collection plan after its review
c731814f0 #3736 observability: add stibnite to collection with collection off, its certificate and darwin agent
cffd37d88 #3738 openspec: record deploying stibnite's collection agent with collection off
e3f30fd41 #3739 observability: start collecting stibnite's host metrics
585128280 #3740 otel-envelope: bound darwin collectors by physical footprint, not resident size
2ea47ee5b #3741 openspec: record stibnite's watched activation
9b08ae697 #3743 fleet-alert: alert on darwin launchd jobs and stale probes
8f1764ccf #3744 otel-collector: bound darwin process names with their own floor
f70d1a0ac #3745 observability: document stibnite's darwin collection
e38ac7bcc #3771 fleet-alert: report a stopped kept-alive launchd job once
1bdc59782 #3772 openspec: record stibnite's stopped-job acceptance passing after its fix
1ebfa1307 #3778 stand-up-darwin-collection: apply the close-out review
<close-out: 6.1a and 8.1 closed under O2 of 2026-11-07; verify.md, 9.2, 10.1, the satisfaction projection and the archive: tasks.md 9.1, 9.2, 9.4 to 9.6 and 10.1>
```

---

## 1. Wins

- [evidence: `cam72-evidence/1.1-plan-review-20261106T000448Z.md`] The plan review found 27 problems, applied the plan's code in a throwaway workspace to show each, and the operator decided all 27 from a dispositions table before implementation started; #3733 carried the corrections.
- Among them, three would have stopped the plan as written: its F1, the probe's log in a directory its account could not write; its F2, shellcheck SC2043 failing the probe for stibnite's single SMART device; its F3, the notifier refactor shadowing `config`.
- Its F5 kept every NixOS envelope byte-identical by writing C5's interpolation inline, its F6 halved `otel-collector-darwin`'s evaluation cost by replacing `pkgs.extend` with `pkgs // { … }` (344,895,440 B to 162,481,008 B), and its F11 added cinnabar's deploy, because `fleet-deadman` shares `transition.jq`.
- [evidence: `cam72-evidence/1.3-rehearsal-20261105T233403Z.log`] The rehearsal ran each plan block with its interpreter and the consumers' argument lists, and its survey of 441 system jobs found the jetsam idle exit, which became the parser's `last exit reason` rule and the mutant `idleExitAsFailure` (plan review F27).
- [evidence: `2.3-vars-20261106T022341Z.log`] The vars step left `otel-ca`'s and the `ntfy-alerter` token's hashes unchanged at all four reads, and stibnite became the token's seventh reader through `clan vars fix`.
- [evidence: `3.2-notifier-20261106T011955Z.log`; `3.3-envelope-20261106T012248Z.log`; `6.4-toplevels-20261106T151922Z.log`] Moving the posting logic into `observabilityNotifyRun` left the NixOS notifier and envelope units hashing as at `main@origin`, and #3743 changed no host but magnetite and stibnite.
- [evidence: `5.3-stibnite-20261106T052005Z.log`] At the watched activation the store-built collector reached the ingress over ZeroTier (sends 725 to 971 points in 60 s, none failed), every applicable series was stored under `host_name="stibnite"`, and the deploy record held 14 lines and 14 rows.
- [evidence: `6.1-replay-20261106T144527Z.log`; `6.1-names.tsv`] The stored names and tags of the launchd, textfile and SMART series equalled design D9's expressions before #3743 merged, and no darwin rule would have fired over stibnite's 571 replayed steps.
- [evidence: `8.2-envelope-20261107T045006Z.log`] Stopping `org.nixos.otelcol` for 12 min posted one `FAILED otel-envelope on stibnite` and one `RESOLVED`, and nothing else.
- [evidence: `8.4-signal-20261107T054220Z.log`] A `SIGKILL` of `otelcol-process` was reported as exit code -1, fired one `LaunchdJobFailed stibnite` and resolved after `kickstart -k`, and the recorded reply replaced the edited fixture of 2.5.
- [evidence: `8.5-reload-20261107T055826Z.log`] A plist change reloaded `otelcol` with no `LaunchdJobFailed` or `LaunchdJobNotRunning` over 15 min, and the revert posted nothing.
- [evidence: `8.6-suspend-20261107T062837Z.log`; `8.7-overnight-20261107T083100Z.log`] Across an induced sleep with 13 dark wakes and a natural overnight sleep with 26, no post named stibnite, both exporters' queues drained to 0, and the probe ran within 60 s of wake.
- [evidence: `8.3a-ac2-20261107T192736Z.log`] After #3771, a 15 min bootout of `nix-grpc-daemon` posted exactly one `[FIRING] LaunchdJobNotRunning stibnite` and one `[RESOLVED]`, received on the operator's phone.
- [evidence: `8.8-ntfy-20261107T083142Z.log`] An anonymous post to a fleet topic from stibnite was refused with 403, while the wrapper's posts with the token were accepted.
- [evidence: `verify.md` §9.1; `9.3-config-cost-20261107T215039Z.log`] Every gated check stayed under 536,870,912 B, and the whole change added 103,376 B to `otel-collector-config` (477,578,128 B to 477,681,504 B from `git archive` trees).

## 2. Misses

- [high] [painful | evidence: #3740; tasks.md 5.3a; `c5-top-red-20261106T052719Z.log`] C5 shipped reading `ps -o rss=`, and at the watched activation it failed `otelcol-process 178 MiB above its limit` while the kernel's physical footprint was 101 MB, posting a false `FAILED otel-envelope on stibnite` at 2026-11-06T05:22:16Z.
- Root cause: the 1.3 rehearsal ran `ps -o rss= -p <pid>` as `nobody` and recorded only that it exited 0 (`cam72-evidence/1.3-rehearsal-20261105T233403Z.log:1184`), so nothing compared its value with `/usr/bin/footprint`; on macOS resident size counts the mapped 357 MiB binary's file-backed pages.
- [high] [painful | evidence: #3744; tasks.md 6.5, 6.6a; `cam72-stibnite-names-20261106T211506Z.log`] magnetite's hourly B3 failed on stibnite's 63 process names from 2026-11-06T15:00Z, and stibnite stored 85 distinct names before the fix against 8.1's bound of 30 (tasks.md 8.1).
- Root cause: design D3 carried the Linux 64 MiB process floor to darwin, where resident size counts each process's share of the shared cache (A77), and no step before the watched activation counted stibnite's names above the floor.
- [high] [painful | evidence: #3771; tasks.md 8.3; `8.3-ac2-20261107T051210Z.log`] AC2's bootout of `nix-grpc-daemon` posted two `[FIRING] LaunchdJobNotRunning stibnite` and two `[RESOLVED]`.
- Root cause: the probe writes all four state lines for an unloaded label, so a booted-out kept-alive job answered both arms of the rule's `or`; 6.2's legs were written as the steps on which the fixture answers the expression, one arm each, not from the probe's full output, and 6.1's replay window held no unloaded kept-alive job.
- [high] [painful | evidence: `review.md` F1; `verify.md` §8a.3] The `world-assumptions` delta's MODIFIED vocabulary block predated main's archive of `deliver-omp-browser-relay` (`cda06e467`), so a sync would have dropped 14 main rows and main's two senses of `browser`.
- Root cause: the row check that detects it is placed at the archive (tasks.md 9.4) only, and nothing compared the delta with main between #3733 and the close-out.
- [med] [painful | evidence: `review.md` F18; `logs/cam88-evidence/diagnosis.md`] The collector README, ADR-003, ADR-004, ADR-009, `schema.nix` and design D3 stated that process memory is summed per executable, while `aggregate_labels` keys points by the nanosecond timestamp and each stored point is one process; the review's own first placeholder for F18 repeated a false variant.
- Root cause: the statements were written from the processor's configuration and name, not from its source or from a comparison of stored values with `ps`.
- [med] [painful | evidence: `review.md` F2, F3] The specs stated a 64 MiB darwin process floor after #3744 set 384 MiB, and TSI's scenarios named `otel-collector-darwin` clauses for the limiters, C5's limits and the `otlp` routing that did not exist.
- Root cause: the scenarios were written before the check and before 5.3a and 6.6a changed behaviour, and nothing matched a scenario's named clause against the check until the review.
- [med] [painful | evidence: tasks.md 8.1; `8.1-day-20261107T082952Z.log`; `review.md` F4] 8.1's first 24 h window could not pass: no memory sampler ran and `rss.tsv` did not exist, so neither collector's maximum was recorded, and 8.6 recorded resident sizes where the criterion names the footprint.
- Root cause: the sampler was a measurement the item named, not a step started at the window's opening and checked before the window counted, and 5.3a changed the measured quantity without changing the plan's sampler.
- [med] [painful | evidence: tasks.md 6.1, 6.1a; `6.1a-kickstart-20261108T001253Z.log`] 6.1's replay window, shortened by the operator to 05:17:19Z to 14:49:02Z on 2026-11-06, held no natural overnight sleep and no `nix-cleanup-gcroots` run, and 6.1a's run was in the end a kickstart under O2, so the calendar trigger and A61's coalescing at wake are unobserved.
- Root cause: the plan set the replay at "at least 24 h" without naming the calendar events the window must hold, and `nix-cleanup-gcroots` runs on Sundays only.
- [low] [painful | evidence: `review.md` F19; `0-base-main-20261106T005345Z.log`] `base.sh` measured costs with `#checks.…` without the `.`, about 117.5 MB high, the miss S4 recorded in its §2, and 2.4's note attributed the offset to `git+file?rev=` until the review measured it.
- [low] [painful | evidence: `review.md` F8; `9.1-a64-counts-20261107T213934Z.log`] A64 stated 90 to 140 sleeps a day, and `pmset -g log` held 22 to 132, below the range on five of seven days.
- [low] [painful | evidence: `review.md` F9] 9.2's criterion `rg -n 'collect = false'` could not pass while the host table's header comment stated the joining procedure with that literal.
- [low] [painful | evidence: `review.md` F6; tasks.md 3.2, 3.8] #3736's description says the `fleet-ingress` container test passed without its cases and date, and that run was made from the working copy's snapshot `e048d66b8cc5`, not the pull request's head.
- [low] [painful | evidence: `review.md` F10] The runbook, ADR-009 and `components/fleet-alert.md` still called outcomes unobserved after 8.4 and 8.5 had observed them.
- [low] [nit | evidence: `review.md` F14; `8.3a-ac2-20261107T192736Z.log`] `[FIRING] AlertBudgetExceeded` posted during 8.3a's rerun, counting the day's deliberate acceptance posts, against the criterion's "nothing else".
- [low] [nit | evidence: `8.2-envelope-20261107T044636Z.log`] 8.2's first launch, terminated to relaunch detached, booted `otelcol` out for 40 s with no post.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 1.1 to 1.3 | evidence written to `logs/cam72-evidence/` instead of `logs/s5-evidence/`; the plan corrected in #3733 | the orchestrator's choice; the 27 accepted findings |
| 2.1, 2.6 | scratch edits made in place in the working copy and reverted; `collect` true evaluated by `extendModules` instead of a scratch tree | no worktree was allowed (tasks.md 2.1, 2.6) |
| 3.2, 3.8 | the `fleet-ingress` run from snapshot `e048d66b8cc5`; #3736's description without its cases and date | the run preceded the pull request (`review.md` F6) |
| 4.2, 5.2, 6.6, 6.6a | stibnite activated from the primary checkout, not the deploy worktree | operator choice O1 of 2026-11-06, with `jj diff` listing nothing outside `openspec/` and `logs/` |
| 5.3a (new, #3740) | C5 reads physical footprint from `top` instead of `ps -o rss=` | the false C5 failure at the watched activation (§2) |
| 6.1 | replayed over 05:17:19Z to 14:49:02Z instead of 24 h; C5's limits kept from one `top` reading and 105 passing runs, not `rss.tsv` | operator decisions of 2026-11-06 (O5) |
| 6.1a (new) | closed under O2 of 2026-11-07 with `nix-cleanup-gcroots` kickstarted at 2026-11-08T00:12:53Z | its calendar run falls after the close-out; the calendar trigger is not exercised |
| 6.6a (new, #3744) | darwin process floor 384 MiB with a fleet-executable keep-list | B3 failing on stibnite's names (§2) |
| 8.1 | first window not passed; judged again, then under O2 of 2026-11-07 over 2026-11-07T08:24Z to 2026-11-08T00:30Z, about 16 h | no sampler in the first window; the operator's close-out decision |
| 8.2 to 8.6 | run unattended under the operator's approvals; the `fleet-alerts` topic read back for the phone in 8.2, 8.4 and 8.6 | operator approvals of 2026-11-07 (`verify.md` §7) |
| 8.3a (new, #3771) | `LaunchdJobNotRunning`'s arms made disjoint, and AC2 run again | the doubled posts of 8.3 (§2) |
| 8.5 | the comment placed in `otelcol`'s launchd script; the revert by `nix-env --set` and `activate` | a scratch activation instead of the next routine change |
| 8.6 | `pmset sleepnow` with a scheduled wake for the lid; resident sizes recorded instead of footprint | unattended run; the footprint taken from 8.1's sampler (`review.md` F4) |
| 8.7 | the natural sleep preceded 8.6 instead of following it | the night of 2026-11-06 |
| 11 (new, #3778) | 17 items applying `review.md` F1 to F15, F18 and F19 | the holistic review's dispositions, approved on 2026-11-07 |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md` and `plan/task-1.md` to `plan/task-9.md`) |
| superpowers:using-git-worktrees                  | partial: magnetite and cinnabar deployed from the deploy worktree; stibnite activated from the primary checkout under O1; no scratch worktree (tasks.md 2.1, 2.6) |
| superpowers:subagent-driven-development          | partial: the plan review (1.1) and the holistic review (9.3) are recorded; implementation dispatches are not |
| (transitive) superpowers:test-driven-development | yes (red logs for 2.1, 2.4, 2.5, 3.1, 3.3, 3.5, 3.7, 5.3a, 6.2, 6.3, 6.6a and 8.3a) |
| (transitive) superpowers:requesting-code-review  | partial: the codex sub-step was replaced, as in S1 to S4 |
| superpowers:finishing-a-development-branch       | pending (tasks.md 9.5, 9.6) |

### S4 §6 rules, and the earlier rules S4 carried to S5, applied in S5

The `:<line>` cells cite the rule's line in S4's retrospective (`openspec/changes/archive/2026-11-02-stand-up-linux-fleet-collection/retrospective.md`) as read on 2026-11-08: its §6 entries, or the §4 table rows carrying S1 to S3 rules.

| Rule | S4 retrospective | Applied in S5 | What it caught |
|---|---|---|---|
| Holistic review of the planned regulators before Task 1, decided one disposition row per finding (the plan-review gate) | `:126`, `:135` | yes: tasks.md 1.1, 27 findings each rehearsed in a throwaway workspace and 27 disposition rows, applied in #3733 before implementation (`cam72-evidence/1.1-plan-review-…`) | F1 to F3, each of which would have stopped the plan; F5's change to every NixOS envelope; F6's doubled cost; F11's cinnabar closure; F27's jetsam exit; the post-merge review still found 19, four significant (`review.md`) |
| A pre-deploy probe of a vendored consumer runs that consumer's exact argument list (the rehearsal) | `:180`, `:133` | yes: 1.3 ran every block of Tasks 4, 5, 6 and 8 with its interpreter, `smartctl -j -H -A disk0` and `launchctl print` as `nobody`, one unloaded label (exit 113), `otelcol-contrib validate` and `ps -o rss= -p` (`cam72-evidence/1.3-rehearsal-…`) | the plan's block fixes (plan review F20) and the jetsam job among 441 (F27); missed that `ps -o rss=` measured resident size, not the footprint C5's limits mean (#3740), and launchctl's text for a signal kill, assumed until 8.4 |
| An alert rule's names are read from the store before the rule merges, and an empty replay blocks it (the replay before the rules) | `:176`, `:138` | yes: 3.7 kept stibnite out of every rule until 6.3; 6.1 read the stored names (`6.1-names.tsv`) and replayed eight rules over 571 steps before #3743; 8.3a replayed the fixed expression (`8.3a-replay-20261107T185753Z.log`) | the store answers the launchd series without `__name__`, which 6.2's fixtures follow; no would-be firing; missed the doubled `LaunchdJobNotRunning` (#3771), because no kept-alive job was unloaded in the window |
| A table row that another host's closure reads is followed by that host's deploy (the magnetite deploy after each row change) | `:188` | yes: magnetite at 4.1, 5.4, 6.5 and after #3771; cinnabar at 4.3 for `transition.jq` (plan review F11) | stibnite became expected only at 5.4's deploy, as designed; 5.4's switch stopped an evaluator run in flight and posted `FAILED fleet-alert.service on magnetite` (CAM-85) |
| Every post during a deploy window is read from the journals and recorded with its cause (the per-step post read) | `:204` | yes: every deploy and activation item (`verify.md` §9.3) | 4.3's `[RESOLVED] SystemdUnitFailed cinnabar`, a notifier failed since CAM-76's ntfy stop; 5.4's false C5 failure and CAM-85; 6.5's B3 failure, which became 6.6a; the causes live in the done-notes, not in the logs (`review.md` F17, rejected) |
| Measure each new check's evaluation cost against the budget with `.#.checks…`, stopping over it (the eval-cost stops) | `:122` | yes: before and after each task against 536,870,912 B (`verify.md` §9.1) | `pkgs.extend` (plan review F6); no figure over budget, the highest 0.445 GiB; missed `base.sh`'s `#checks…` without the `.` and its misattribution (`review.md` F19), and `darwin-stibnite` with `collect` true was never measured |
| A clause's two value sources are traced to their definitions, and a mutant runs only the case it must fail (the two-source rule with its mutants) | `:136`, `:121`, `:228` | yes: 1.1's "Clauses and assertions" lists each clause's sources; the tasks.md preamble; each mutant run against its own case (2.4, 3.3, 6.3, 11.3) | plan review F7 (`postEveryFailure` rejected for the wrong reason); `review.md` F12 (`processFloorDarwin` restated its line, deleted in 11.12); `review.md` F3 (scenarios naming clauses that did not exist, added in 11.3 with five mutants) |
| A reader's first deploy compares counts (the deploy-record line counts) | `:131` | yes: 5.3 compared stibnite's file with its rows; 10.1 compares them again | nothing: 14 lines and 14 rows (`5.3-stibnite-20261106T052005Z.log`) |
| Hold the deploy-record obligation on the darwin machines | `:143` | in substance: `deployRecordObligations` has held on the darwin machine checks since `ea7cbf60c` (`modules/README.md:60`), and a darwin evaluation or assertion error fails `darwin-stibnite` before its best-effort modifier is read (design.md:35); nixbot built `darwin-stibnite` for #3739 and #3743 | nothing |
| A migration flag's one-shot branches are removed in the close-out (the migration-flag close-out) | `:224` | yes: 9.2 lists every `collect` line with its disposition (`verify.md` §10; `9.2-flags-20261108T001524Z.log`) | no one-shot branch left; 9.2's own criterion could not pass while the header comment held the literal, reworded in 11.9, with two stale pyrite comments (`review.md` F9) |
| An assumption's status names what was observed (the observed-status wording) | `:208` | yes: `verify.md` §8b and §8c use `configured`, `not violated` or `observed` with a window | A64's range below the recorded counts on five of seven days (`review.md` F8, applied in 11.8); A61's calendar half unobserved; 8.6's resident sizes do not answer the footprint criterion (`review.md` F4) |
| A repeating calendar names its zone; S5's launchd calendar jobs state their behaviour across a clock change | `:184` | yes: design D8; the fragment asserts that no collection daemon sets `StartCalendarInterval`, failing for `probeCalendar` and `envelopeCalendar`; `harmonia-gc` and `nix-cleanup-gcroots` stated across a daylight-saving change | nothing at runtime; the calendar trigger stays unexercised, since 6.1a's run was a kickstart under O2 |
| A world assumption naming a vendor version has a trigger; the close-out compares running versions | `:192` | partly: A61 to A77 carry re-read triggers on macOS's major version and smartmontools' version (design.md:340); no comparison of running versions is recorded in `verify.md` | — |
| A unit with clauses at two cadences keeps each cadence's verdict | `:196` | not applicable: every clause of the darwin envelope, C5 among them, runs at its 300 s `StartInterval` (tasks.md 3.4) | — |
| A regulator clause iterates over the configured set it judges | `:200` | yes: the darwin envelope's targets and exporters come from `flake.lib.otelCollectorDarwin` (tasks.md 3.4) | 8.2's bootout failed C1 and C2 and posted once each way (`8.2-envelope-20261107T045006Z.log`) |
| A laptop's acceptance includes one suspend and resume while it collects | `:212` | yes: 8.6's induced sleep and 8.7's natural one | no false post across 13 and 26 dark wakes; the queues drained and the probe ran within 60 s; the post-sleep footprint was not recorded (`review.md` F4) |
| Each evidence log is read whole for anomalies before the next step | `:216` | yes for 1.2: its log recorded another session's activation of stibnite at 2026-11-05T23:26:45Z, which became the preamble's deploy-record check before every activation | the previous recorded activation was more than an hour old before each of 4.2, 5.2, 6.6 and 8.5 (their done-notes) |
| Check each slice's rules against the later slices that touch the same objects | `:127` | yes: design "Later slices" names S8's export (design.md:360); the SMART counters take smartctl_exporter's names so the NVMe rules read one name on pyrite and stibnite (design.md:217) | the NVMe rules expect `["pyrite","stibnite"]` after 6.3; missed a sibling change's archive moving main's vocabulary (`review.md` F1) |
| Schedule CAM-76's watch before S5 | `:150` | yes: CAM-76 watched the alert path from outside before S5 (proposal.md:19) | its ntfy stop of 2026-11-04 left cinnabar's notifier failed until 4.3's deploy reset it |
| A long-running evidence capture runs on an always-on host | `:151` | partly: 8.1's read runs on magnetite's store (`8.1-day.sh`), while the footprint sampler can run only on stibnite | 8.1's first window had no sampler, so its maxima were not recorded (tasks.md 8.1) |

### Deliberately skipped skills

- **`superpowers:requesting-code-review`**
  - **What was skipped**: the paid `codex exec` review.
  - **Why this cycle**: the operator's program-wide decision recorded in S4's retrospective (`:158`) stands; one read-only Opus subagent reviewed the plan (tasks.md 1.1) and the merged change (tasks.md 9.3).
  - The substitute found nothing critical, four significant findings and fifteen minor ones (`review.md`).
  - **How to prevent recurrence**: no recurrence to prevent; the plan-time review precedes it.

## 5. Surprises

- macOS `ps -o rss=` counts a process's resident file-backed pages of its mapped binary, 178 MiB for `otelcol-process` against a 101 MB physical footprint, and `top`, which is setuid, prints any process's footprint to an unprivileged account (tasks.md 5.3a; A70).
- macOS resident size counts each process's share of the shared cache, so 82 executables read above 64 MiB on stibnite (`cam72-stibnite-names-20261106T211506Z.log`; A77).
- The probe writes all four state lines for an unloaded label, so `running` 0 and `unloaded` 1 both hold for a booted-out job (tasks.md 8.3).
- After `SIGKILL`, `launchctl print` prints no `last exit code` or `last exit reason` line, only `last terminating signal = Killed: 9` (`8.4-signal-20261107T054220Z.log`; A62).
- A jetsam idle exit leaves no exit-code line either, and only `last exit reason` tells it from a failure (plan review F27).
- The store answers the launchd series without `__name__`, and answers D9's `!~` and `or` shapes (tasks.md 6.1).
- `metricstransform`'s `aggregate_labels` keys points by the full nanosecond timestamp, so same-named processes are never summed (`review.md` F18).
- `awk -v` expands backslash escapes, which stripped a mutant's quotes and turned a `\t` into a tab (tasks.md 2.5, 3.3).
- Agent sessions' power assertions kept stibnite awake: a dark wake lasted from 07:14Z to 14:31Z on 2026-11-06, and `pmset -g` printed `sleep 0` (tasks.md 6.1; `review.md` F8).
- A deploy's switch can stop `fleet-alert` mid-run and post `FAILED fleet-alert.service on magnetite`, once in 25 magnetite deploys over 14 days (tasks.md 5.4; CAM-85).
- B3 counts the past hour, so the first run after 6.6a's fix still failed, and the first passing run was at 23:00Z (tasks.md 6.6a).
- `AlertBudgetExceeded` counts deliberate acceptance posts like any others (tasks.md 8.3a).
- Store curl verified `ntfy.zt` as `_otelcol`, so `ntfy-send`'s endpoint-security reason for `/usr/bin/curl` no longer holds (`7.3-ntfy-curl-proof-20261106T220636Z.log`).

## 6. Promote candidates → long-term learning

- [ ] [high] **A regulator that bounds a measured quantity is rehearsed by comparing its reading with the platform's own accounting of that quantity, not only by the command exiting 0.** → **Promote to** skill (`writing-plans`, research step for vendor configuration)
  > **Why**: 1.3 recorded `ps -o rss= -p` exiting 0 as `nobody`, and C5 failed at the first activation on a value the kernel's footprint did not support (§2; #3740).
  > **How to apply**: each new memory or CPU clause records, in the plan's rehearsal, its reading beside `footprint`, `top` or the cgroup's own counter for the same process.

- [ ] [high] **A bound carried to a new platform is measured on that platform's stored data before the regulator that judges it can see the platform.** → **Promote to** skill (`preferences-observability-engineering`)
  > **Why**: the Linux 64 MiB process floor let 63 names an hour through on stibnite, and B3 failed from 2026-11-06T15:00Z in each hour stibnite was active until the 23:00Z run after #3744's activation (§2; tasks.md 6.6a).
  > **How to apply**: a host on a new platform has its distinct names per hour counted at candidate floors from a read-only run before its row's `collect` becomes true, as `cam72-hourly-floors-20261106T211514Z.log` did after the fact.

- [ ] [high] **An alert rule's fixture legs feed the producer's full output for each state, not the expression's answer.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: 6.2's legs answered one arm of `LaunchdJobNotRunning` each, and the probe's four state lines made a booted-out kept-alive job answer both (§2; #3771).
  > **How to apply**: each new rule's legs, like `keptAliveUnloaded`, feed the recorded textfile or series of every state the producer writes, with a mutant restoring the broken form.

- [ ] [high] **A delta that modifies a main requirement is compared with main's text at every rebase, not only at archive.** → **Promote to** schema (OpenSpec tasks template, close-out and rebase)
  > **Why**: the vocabulary block would have dropped 14 rows another change archived after #3733 (`review.md` F1).
  > **How to apply**: the row check of tasks.md 9.4 runs at each pull request that rebases the change folder and at the verify step, and its output goes in `verify.md`.

- [ ] [med] **A statement of what a vendor processor does is checked against its source or against stored values before it enters a design, an ADR or a spec.** → **Promote to** skill (`preferences-observability-engineering`)
  > **Why**: six documents stated a per-executable sum that `aggregate_labels` never performs (`review.md` F18).
  > **How to apply**: CAM-88's fix and every later collector statement cites the vendored source line or a stored-value comparison with `ps`.

- [ ] [med] **A spec scenario that names a check clause is matched against the check by name at verify.** → **Promote to** schema (verify template, discharge coherence)
  > **Why**: TSI's scenarios named limiter and C5 clauses that did not exist, and its floor was stale after #3744 (`review.md` F2, F3).
  > **How to apply**: the verifier lists each clause, case or mutant a scenario names and greps the check for it; an absent name is a finding.

- [ ] [med] **An acceptance measurement starts at its window's opening as its own step, and the window counts only once its first sample exists.** → **Promote to** schema (OpenSpec tasks template, acceptance)
  > **Why**: 8.1's first window ran without a sampler, and 8.6 recorded resident sizes where the criterion names the footprint (§2; `review.md` F4).
  > **How to apply**: an acceptance item that names a maximum over a window has a preceding item that starts the sampler and records its first line.

- [ ] [med] **An acceptance window names the scheduled and natural events it must contain, with their dates.** → **Promote to** schema (OpenSpec tasks template, acceptance)
  > **Why**: 6.1's window held no overnight sleep and no `nix-cleanup-gcroots` run, and 6.1a closed by a kickstart, so the calendar trigger is unexercised (§2; §3).
  > **How to apply**: the plan lists each calendar job and natural event a replay or watch must cover, with its next date, so the operator decides any substitute before acceptance starts.

- [ ] [med] **The evaluation-cost command is one committed script that writes `.#.checks`, and a constant offset from the baseline is diagnosed before it is explained.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: S4 recorded the `#checks` offset, `base.sh` repeated it, and 2.4's note blamed `git+file?rev=` (`review.md` F19).
  > **How to apply**: every slice measures through `cost.sh`, and `rg -n '#checks\.' logs/<slice>-evidence/*.sh` prints nothing before the first figure is recorded.

- [ ] [low] **A world assumption's numeric range is stated from recorded counts at design time.** → **Promote to** skill (`preferences-requirements-engineering`)
  > **Why**: A64's 90 to 140 sleeps a day was below the recorded counts on five of seven days (`review.md` F8).
  > **How to apply**: an assumption with a range cites the read that produced it, with its days.

- [ ] [low] **A verification command that greps for a literal is run once against the files before the plan is reviewed.** → **Promote to** skill (`writing-plans`)
  > **Why**: 9.2's `rg -n 'collect = false'` matched the header comment, so its criterion could not pass (`review.md` F9).
  > **How to apply**: the plan review's rehearsal runs each close-out grep against the current tree and records its output.

- [ ] [low] **An acceptance criterion of "nothing else" names the budget and meta-alerts its deliberate posts can trigger.** → **Promote to** one-off (the next slice with alert acceptance)
  > **Why**: `AlertBudgetExceeded` posted during 8.3a's rerun, counting the day's deliberate posts (`review.md` F14).
  > **How to apply**: the acceptance plan counts each deliberate post against the per-host budget and states the expected budget post, if any.
