# Retrospective: stand-up-fleet-alerting

> Written: 2026-10-20 (after verify passed with warnings, `verify.md` Overall Decision)
> Commit range: `630722b14..59af3f592`, filtered to the S3 paths (`git log 630722b14..59af3f592 -- <S3 paths>`)
> Worktree: merged to main; the archive is a second close-out pull request

---

## 0. Evidence

- **Commit range**: `630722b14..59af3f592` (12 commits on the S3 paths, one per pull request: #3503 plan, #3504, #3505, #3506, #3507, #3508, #3509, #3510, #3511, #3512, #3516, #3519; `verify.md` §5).
- **Diff size**: +13004 / -309 lines across 54 files (`git diff --shortstat 630722b14 59af3f592` over the S3 code paths, the change directory with its 7118-line `plan.md`, `modules/machines/nixos/{cinnabar,magnetite}`, the runbook, `modules/README.md`, `docs/notes/development/observability` and the two vars directories).
- **Tasks done**: 59/61 (`grep -cE '^- \[x\]' tasks.md` → 59; `- [ ]` → 2, 8.4 and 8.5, which are the archive).
- **Active hours**: not recorded; the wall-clock span is #3503 merged 2026-10-18T06:17Z to #3519 merged 2026-10-20T21:29Z, about 63 hours, of which the cutover and its fixes, #3504 to #3511, took 2026-10-18T06:17Z to 11:12Z (`gh pr view`).
- **Subagent dispatches**: not counted; named agents include `S3OpsPreC1` (`verify.md` §8b), `S3CostBisect` (charter v19), `S3FixAbsence` (`verify.md` §9.1), `S3Verify` and `S3CloseOut` (`verify.md` header) and the holistic reviewer (`review.md:3`).
- **New external dependencies**: none; `ntfy-sh` 2.28.0 and `prometheus`'s `promtool` come from the root pin, and Hypothesis 6.156.1 from the root pin's Python set (`tasks.md:40`).
- **Bugs encountered post-merge**: 2 shipped defects found by deployment verification: frozen time counted as absence, so `HostOOMKill` resolved 50 s after a 7-minute store outage (#3510, `verify.md` §9.10), and `greptimedb-schema` not restarting when the store was started by hand (review F9, #3516); review F1 and F2 were live-path gaps caught before they fired (`review.md:11-12`).
- **OpenSpec validate state at archive**: not run yet; at this close-out, `openspec validate stand-up-fleet-alerting --strict` passed.
- **Test coverage signal**: `checks.x86_64-linux.fleet-alert` with promtool, fixture legs, a derandomized Hypothesis property against `model.py` and mutants `forZero`, `noStateWrite`, `noStoreFreeze`, `noAbsenceFreeze`, `noHostsUpdate`, `noRepost` and `malformedExpression` (`review-b-green-20261020-164707.log`); `ntfy-provisioning` with four mutants; `package-ntfy-send-test-token-transport` with its argv mutant; every shipped rule fired and resolved on magnetite's store (`verify.md` §9.7).

Commit chain (chronological):

```
630722b14 (base)
b32825cde #3503 observability: plan S3 fleet alerting (charter v17)
b9b922036 #3504 feat(ntfy-send): send the token from NTFY_TOKEN_FILE on stdin, never on argv
23c82360b #3505 refactor(observability-notify): own module, FAILED log and token option
e19971f37 #3506 feat(ntfy): provision the alerter user and token on cinnabar, one visitor per mesh client
6ccc644bb #3507 feat(fleet-alert): alert evaluator on magnetite with rule, fixture and property checks
dbec98c74 #3508 feat(fleet-alert): dead-man on cinnabar and fleet-* access control
6caa2425c #3509 fix(ntfy): end the S3 cutover debug logging on cinnabar
18e3b8acf #3510 fix(fleet-alert): frozen time is not absence
c926297ef #3511 docs(fleet-alert): correct the evaluation-cost evidence and method (charter v19)
5f935064c #3512 docs(observability): S3 alerting runbook, module index and ntfy-send token lines
e48bf7b2d #3516 fix(fleet-alert): always-on host silence, retried notices, timing budget and schema restart
59af3f592 #3519 refactor(fleet-alert): single-host relations as assertions, drop restating checks
<close-out: verify, review, retrospective, charter v21; archive: pending, plan.md Task 8 Steps 14-18>
```

---

## 1. Wins

- [evidence: `verify.md` §8b] Every ADDED and MODIFIED requirement has a discharge, so §8b has no undischarged row.
- [evidence: `verify.md` §9.5] The three-deploy cutover refused no post: across C1 to C3, 7 refusals in ntfy's journal, all deliberate, and `unexplained: none`.
- [evidence: `verify.md` §9.2; charter v17] Reading ntfy 2.28.0's source before deploying found that an unknown `Authorization` header gets 401 even on an open topic (`server/server_auth.go:45-50`), which turned the planned two deploys into three, and that IPv6 visitors are grouped by /64, which every ZeroTier member shares; the pre-C1 negative control then showed the shared visitor live (`NEGATIVE CONTROL HOLDS`).
- [evidence: `verify.md` §9.4, §9.6] R9.4 and R9.3 were shown able to fail on the hosts: removing `*:fleet-*:ro` failed `fleet-deadman` and posted `FAILED`, and stopping the evaluator raised `AlertEvaluatorSilent` in 14 min 28 s and resolved it 4 min 12 s after the restart.
- [evidence: `verify.md` §9.7] Every shipped rule fired and resolved once on the real store, the safe ones by real conditions and the others by hand runs on scratch state.
- [evidence: `verify.md` §10.2] R9.1's count equalled the captured `FIRING` messages over both 24-hour windows, and the evaluator's journal and pyrite's capture held identical id sets.
- [evidence: `tasks.md` 1.2; `verify.md` §8b] The token stays off every command line: the token-transport test records curl's argv and stdin and rejects a mutant that passes the header as an argument.
- [evidence: `verify.md` §9.10] The Task 5 property that an `expr`-less rule behaves like its `expr` twin failed against Task 4's `transition.jq` and caught the dead-man's rule being skipped before it merged.
- [evidence: `review.md:3-6`] The holistic review found nothing critical, and every finding has a recorded disposition.
- [evidence: `logs/s3-evidence/`, 232 files] Every verify claim points at a captured log.

## 2. Misses

- [high] [blocking | evidence: #3510; `logs/s3-evidence/7.6-oom-store-resolved-20261018T095420Z.log`; `verify.md` §11.1] Frozen time counted as absence: after a 7-minute store stop, `[RESOLVED] HostOOMKill magnetite` came 50 s after the store returned, because absence ran from the last observation before the freeze.
- The property test passed with the bug present because `model.py` measured absence the same way; the model and the function shared the misreading of design D15, so the comparison could not see it.
- Only the deployment's forced timeline, the 7.6 store stop while `HostOOMKill` fired, exposed it.
- [high] [blocking | evidence: `verify.md` §9.10; `5.1-transition-selection-old-control-20261018T080442Z.log`] Task 4's `transition.jq` selected rules with `select(has("expr"))`, so the dead-man's `AlertEvaluatorSilent`, which has no expression, could never fire; Task 5's new property caught it before merge, and #3508 carried the fix.
- [high] [painful | evidence: `4.8-vars-magnetite-20261018T073644Z.log`; charter v18] `clan vars generate magnetite --generator ntfy-alerter`, meant to add magnetite as a reader of the shared token, regenerated the token and re-ran cinnabar's `ntfy-alerter-env`; deployed, magnetite's token would have differed from the one C1 had provisioned on cinnabar, and every post would have got 401.
- The orchestrator caught it before Task 4's commit, restored both vars directories and used `clan vars fix`, which only adds the reader; tasks.md 4.8 and the plan now name the hazard.
- [med] [painful | evidence: charter v18, v19; #3511; `verify.md` §9.1] The evaluation cost was measured as `nix eval .#checks…`, which first probes `packages` and `legacyPackages` and adds about 114 MB; the inflated 0.557 GiB put `checks.fleet-alert` over its 0.5 GiB budget and drove Task 4 to move clauses into assertions for the wrong reason.
- With the leading dot the check was 0.252 GiB at Task 4's merge, and #3511 corrected the evidence and the reason.
- [med] [painful | evidence: `review.md:10-22`] The review found eleven problems that the plan's regulators had passed, as in S1, even though S3 adopted S1's rules: F3, F5, F6 and F7 were again assertions and clauses restating the line they judge, and F3 put the check at 91 % of its budget.
- [med] [painful | evidence: `review.md` F1; `verify.md` §11.2] F1: if magnetite's collector stopped exporting, every rule froze while the heartbeat stayed green; the plan's own fixture leg `silentGapLeg` asserted that silence as expected behaviour.
- [med] [painful | evidence: `verify.md` §9.8] The first Monday `WeeklyPipelineTest` was posted and accepted, but reached no phone: the operator had not installed ntfy on the phone, although Task 7 Step 35 asked for the subscription before Step 32 on 2026-10-18.
- With it went the planned phone observation of the `LocalExporterDown` pair, which 9.1 now discharges by composition (`verify.md` §10.1); and the first test post used plain `curl`, which failed caddy's certificate, while the runbook named only the app and `-k` polling.
- [low] [painful | evidence: `verify.md` §10.2; orchestrator report] pyrite, which held the `fleet-alerts` capture, was asleep when 9.1 fell due 24 hours after the capture started; the comparison ran on 2026-10-20 after the capture reconnected (`open` at 21:16:42Z), when `state.json` had pruned 7.6's `FIRING`s, so window B had to rebuild them from the evaluator's journal.
- [low] [nit | evidence: `verify.md` §9.9] Several plan expectations did not match what ran (RED wording, line numbers, `systemctl show` printing `[unprintable]`, unprivileged `journalctl` reading nothing, GNU `date` without `-j` voiding one poll); none changed a verdict.
- [low] [nit | evidence: `verify.md` §8a] Twelve nouns in `fleet-alerting`'s behavioral requirements have no designation row.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 3 to 5 | three deploys, C1 provisioning without access entries | ntfy 2.28.0 refuses an unknown token with 401 on an open topic (charter v17, D5) |
| 4.2, 5.1 | `transition.jq` reads a rule when it has an `expr` or a results entry | the dead-man's `AlertEvaluatorSilent` has no `expr` (#3508; `verify.md` §9.10) |
| 4.7, 4.9 | token wiring and R7.1 moved to module and host assertions | first measured as a budget breach, then justified by S1 review F5 once the measurement was corrected (charter v18, v19) |
| 4.8 | `clan vars fix` replaced `clan vars generate` for the shared token | `generate` regenerated the token (`4.8-vars-magnetite-20261018T073644Z.log`) |
| 7.6 | the store-stop timeline was re-observed after #3510 | the first observation resolved `HostOOMKill` early (`verify.md` §11.1) |
| 7.6 | `greptimedb-schema` restarted by hand | stopping the store stopped it and starting the store did not (`verify.md` §9.9; review F9) |
| 7.7 | phone receipt shown by a test post on 2026-10-20 | the phone was not subscribed for the first Monday message (`verify.md` §9.8) |
| 9.1 | the phone link composed from pyrite's capture and the test post; window B rebuilt from the evaluator's journal | the pair was posted before the phone subscribed; `.firings` prunes after 24 hours (`verify.md` §10.1, §10.2) |
| 8 Step 11 | the paid codex review was replaced by one holistic subagent review | the operator declined the paid review for the program (plan.md Task 8 Step 11) |
| 10 (new) | section 10, 10.1-10.10, added after verify | #3510's defect and the review findings (`review.md`; `tasks.md` 10.1-10.10) |
| 8 (close-out) | runbook outage bound, charter v21, ADR-009 Q5 and the reference architecture's sequencing | review F4 and the CAM-76 schedule (`review.md:15`) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, `logs/s3/decisions.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | yes (deployment from fresh worktrees of `origin/main`, `tasks.md` 3.7, 4.11, 5.5) |
| superpowers:subagent-driven-development          | yes (`verify.md` header and §8b) |
| (transitive) superpowers:test-driven-development | yes (red and green logs throughout `tasks.md` 1 to 10) |
| (transitive) superpowers:requesting-code-review  | partial: the codex sub-step was replaced, as in S1 |
| superpowers:finishing-a-development-branch       | pending (plan.md Task 8 Steps 14-18) |

### S1-R6 rules applied in S3

`logs/s3/decisions.md:17` lists the S1 promote rules S3 adopted for planning.

| S1 rule | Applied in S3 | What it caught or missed |
|---|---|---|
| Read the vendor source before depending on an option | yes: ntfy v2.28.0 `server_auth.go`, `visitor.go`, `log.go` (tasks.md 3.1; charter v17) | caught the 401-on-unknown-token behaviour, which turned two deploys into three, and the /64 visitor grouping, fixed by `visitor-prefix-bits-ipv6: 128` |
| Plan a start-order relation for each producer | yes: `fleet-alert` after the store and schema job; the dead-man after `ntfy-sh`, `caddy` and `zerotierone` without wanting them (design D12, asserted since #3519) | no ordering failure at deploy; missed that starting the store by hand does not start the schema job (F9) |
| Runtime tests start dependent units together | not applicable: S3 added no `vmTests`; the forced conditions of 7.6 ran on the deployed hosts | — |
| A check clause judges independent values; a module's own settings are assertions | partly: token wiring and R7.1 became assertions (charter v18) | the review still found F3, F5, F6 and F7, clauses and assertions restating the line they judge |
| Measure each check's evaluation cost against a budget | yes: every new check in `verify.md` §9.1, budget 0.5 GiB | the method without the leading dot inflated figures by about 114 MB and misdirected Task 4 (#3511); F3 then found the dead-man parts at 91 %, and #3519 cut the check to 0.306 GiB |
| A negative control for every runtime clause on the real system | yes: the pre-C1 visitor control, the unknown-token 401, the curl-exit-22 control, R9.4's deploy without `*:fleet-*:ro`, `RuleSignalMissing`'s misspelt selector | each control failed as intended; the 7.6 store stop exposed #3510 |
| Format before every commit | yes: `1.4-fmt-…`, `2.6-fmt-…`, `3.5-fmt-…`, `4.10-fmt-…`, `5.4-fmt-…` | each pull request of Tasks 1 to 5 kept its format log before its commit |
| Operator documentation as a planned task | yes: Task 6 (#3512), before 7.7 | the runbook existed, but nothing made the subscription happen before Monday, and it lacked the app install and the plain-`curl` certificate failure until this close-out |
| Check rules against later slices | yes: D10's exclusion becomes the union over hosts in S4; D7, D8 place rules in S2, S4, S5 | missed F10, S2's need for a per-rule database, and F1's dependence on R3.2 arriving in S4 |
| Holistic review of the planned regulators before implementation | no: not among the adopted rules (`logs/s3/decisions.md:17`) | the review ran after merge again and cost #3516 and #3519 |
| Notifier and regulator semantics across restart and outage states | yes: the crash-loop rehearsal with `failed.log` (design, Testing) | missed frozen time as absence, because the reference model shared the misreading (#3510) |
| Resolve the designation-lint nouns at sync | partly: the delta carries 129 designation rows | twelve nouns remain (`verify.md` §8a) |
| Record the operator's reason when a gate is replaced | yes: plan.md Task 8 Step 11 states that the operator declined the paid review | — |

### Deliberately Skipped Skills

- **`superpowers:requesting-code-review`**
  - **What was skipped**: the roborev sub-gate, a paid `codex exec` review (plan.md Task 8 Step 11).
  - **Why this cycle**: the operator declined the paid codex review for the whole program and asked for one holistic Opus subagent review instead, as in S1 (`review.md:3`).
  - The substitute found nothing critical and eleven findings, with F12 added from verify, each with a disposition (`review.md:5-24`).
  - **How to prevent recurrence**: no recurrence to prevent; S1's rule that S2-S8 plans name the holistic review as the gate held.

## 5. Surprises

- ntfy 2.28.0 answers a request with an unknown token 401 even on a topic anonymous clients may write, so tokens must exist on the server before any sender uses them (charter v17).
- ntfy groups IPv6 visitors by /64 by default, and every ZeroTier member shares one /64 (charter v17).
- `clan vars generate <machine> --generator <shared>` regenerates a shared value rather than adding a reader; `clan vars fix` adds the reader (charter v18).
- `nix eval .#checks…` probes `packages` and `legacyPackages` first, adding about 114 MB that is not the check's (charter v19).
- A reference model written from the same design text as the function it checks inherits the same misreading, so the property test agreed with a wrong absence clock (#3510).
- `greptimedb-schema`, `PartOf` the store, stops with it, but starting the store does not start it without `wantedBy` (review F9).
- systemd 261.3 prints `LoadCredential` as `[unprintable]` in `systemctl show`, and unprivileged `journalctl` on magnetite reads nothing without saying so beyond one line (`verify.md` §9.9).
- A posted alert is not a delivered alert: ntfy accepted the first Monday message while no phone was subscribed (`verify.md` §9.8).

## 6. Promote candidates → long-term learning

- [ ] [high] **A reference model for a property test is written from the specification's scenarios, not from the design text the implementation was written from, and each freeze or clock rule gets a scenario with a timeline that crosses it.** → **Promote to** skill (`executable-specification-testing`)
  > **Why**: `model.py` shared `transition.jq`'s absence clock, so the property passed while frozen time counted as absence (#3510).
  > **How to apply**: in S2, S4 and S5, any new state rule in `transition.jq` lands with a fixture timeline taken from a spec scenario before the model is extended.

- [ ] [high] **Adding a reader to an existing shared clan var uses `clan vars fix`, never `clan vars generate`.** → **Promote to** skill (`preferences-secrets`)
  > **Why**: `generate` regenerated the `alerter` token and would have broken every post with 401 (`4.8-vars-magnetite-20261018T073644Z.log`).
  > **How to apply**: S4 and S5 add hosts as `ntfy-alerter` readers with `CLAN_NO_COMMIT=1 clan vars fix <host> --generator ntfy-alerter` and check the token's hash is unchanged.

- [ ] [high] **A human step that a later observation depends on is scheduled as a gate with its own confirmation, not as a note before another step.** → **Promote to** schema (OpenSpec tasks template, deployment verification)
  > **Why**: the phone subscription was a precondition of Step 32 and of 7.7, and neither happened before Monday (`verify.md` §9.8, §10.1).
  > **How to apply**: S5's tasks list the operator's subscription and a received test post as a gated item before any step that needs the phone.

- [ ] [high] **Evaluation cost is measured with `.#.checks…`, the exact output, and the method is recorded with every figure.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: the probing form added about 114 MB and drove a move for the wrong reason (charter v19).
  > **How to apply**: S2-S8 plans copy tasks.md line 4's command verbatim and reject a figure without its method.

- [ ] [med] **Before writing an assertion or clause, name the independently defined value it compares; if the expected value is a literal set a few lines away, do not write it.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: F3, F5, F6 and F7 repeated S1's F7 and F9 despite the adopted rule (`review.md`).
  > **How to apply**: S2 and S4 plan reviews list each new clause with its two value sources before any mutant is written.

- [ ] [med] **Run the holistic review's four questions against the plan before Task 1.** → **Promote to** skill (`writing-plans`, plan review step)
  > **Why**: S1 promoted it and S3 did not adopt it; the post-merge review again cost two pull requests (#3516, #3519).
  > **How to apply**: S2's plan runs the review over design.md and tasks.md and records its findings before the first implementation commit.

- [ ] [med] **Each slice names the regulator that must exist before its own silence modes are safe, and checks it ships.** → **Promote to** schema (OpenSpec design template, Failure path)
  > **Why**: F1's silence was safe only with R3.2, which ships in S4, and `silentGapLeg` asserted the gap as correct.
  > **How to apply**: S4's design removes or replaces the always-on `RuleSignalMissing` only alongside R3.2's per-host freshness clause.

- [ ] [med] **Schedule CAM-76's watch from outside cinnabar before S5.** → **Promote to** one-off (CAM-76 blocks CAM-72)
  > **Why**: an ntfy outage shows only as a missing Monday message, up to 7 days later (`review.md` F4; charter v21).
  > **How to apply**: CAM-72 does not start until CAM-76's watcher alerts over a channel other than ntfy.

- [ ] [med] **S2 adds a per-rule `database` field to the rule table, the fixture server and the `promtool` rendering.** → **Promote to** one-off (S2 design)
  > **Why**: the evaluator sends one database header for every query (`review.md` F10).
  > **How to apply**: S2's dev-loop SLO burn rule reads `devloop` through that field, with a fixture leg that queries both databases.

- [ ] [med] **A long-running evidence capture runs on an always-on host.** → **Promote to** memory (type: feedback)
  > **Why**: pyrite slept through the 24-hour window, and 9.1 had to rebuild `.firings` from the evaluator's journal (`verify.md` §10.2).
  > **How to apply**: S4 and S5 captures run on cinnabar or magnetite, or the plan's comparison step reads the evaluator's journal from the start.

- [ ] [low] **Resolve the designation-lint nouns at sync.** → **Promote to** one-off
  > **Why**: twelve nouns in `fleet-alerting`'s behavioral requirements have no designation row (`verify.md` §8a).
  > **How to apply**: add the rows §8a proposes to the `world-assumptions` table in S2's delta.

- [ ] [low] **The verification of a requirement ending on a person's device names one delivered message on that device, with its time, as its evidence.** → **Promote to** one-off
  > **Why**: the phone link of 9.1 is discharged by composition because no alert was seen on the phone (`verify.md` §10.1).
  > **How to apply**: the next Monday's `WeeklyPipelineTest`, 2026-10-26, is recorded on the phone with its time as the first direct observation.
