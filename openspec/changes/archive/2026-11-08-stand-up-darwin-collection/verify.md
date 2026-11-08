# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `stand-up-darwin-collection`
**Verified at**: `2026-11-07 21:40 UTC`, drafted before tasks.md 6.1a and 8.1 closed; completed `2026-11-08 00:40 UTC` with 6.1a and 8.1 under the operator's decision O2 of 2026-11-07 (§9.3), 10.1 (§9.4), 9.2's rerun (§10) and the archive's checks (§1, §8a.3)
**Verifier**: written read-only for tasks.md 9.1 from `tasks.md`, `design.md`, `proposal.md`, `plan/`, `specs/`, `logs/cam72-evidence/` and `logs/s5-evidence/`, with the commands of §1, §8a.3 and §10 run read-only against the working copy and `pmset -g log` read on stibnite (`9.1-a64-counts-20261107T213934Z.log`); nothing was built, deployed or activated; the holistic review of tasks.md 9.3 ran beside it, and its findings that bear on a row are cited as `review.md` F-numbers

Evidence names are files under `logs/s5-evidence/` unless prefixed `cam72-evidence/`, which is `logs/cam72-evidence/`; both are git-ignored.
Times are UTC.

---

## 1. Structural Validation (`openspec validate stand-up-darwin-collection --strict`)

- [x] The change reports valid
- [x] Every requirement of the deltas is discharged by name in `tasks.md`

**Result**:

Plan Task 9 Step 1's discharge-name check and `openspec validate stand-up-darwin-collection --strict` ran on 2026-11-07 against the working copy after tasks.md §11 (`11-discharge-20261107T221833Z.log`):

```text
undischarged:
unknown:
absent from verify.md:
Change 'stand-up-darwin-collection' is valid
```

The deltas hold 42 requirements, one of them RENAMED and MODIFIED (`fleet-ingress-interface`: `pyrite's NVMe health is read by a loopback exporter` to `A laptop's disk health is read on the host and served on loopback`).
Before §11, three requirements were named after no `Discharges:`: TSI `This capability states its own trust boundary`, A70 and A77; tasks.md 11.5 added TSI's trust boundary to 9.1's, A70 to 5.3a's and A77 to 6.6a's (`review.md` F5).

| Item | Check | Finding before §11 |
|---|---|---|
| tasks.md 9.1 | discharge name | omits TSI `This capability states its own trust boundary` |
| tasks.md 5.3a | discharge name | names A70 outside `Discharges:` |
| tasks.md 6.6a | discharge name | names A77 outside `Discharges:` |

At the archive on 2026-11-08, 17 requirement statements in `fleet-alerting`, `fleet-alerting-interface`, `fleet-ingress-interface`, `host-metrics-collection` and `telemetry-store-interface` were over 500 characters after sync, which would have made those five main specs newly fail `openspec validate --specs --strict`.
Each was shortened by moving 20 whole sentences verbatim into new scenarios of the same requirements, with titles and obligations unchanged (`9.6-shortening-20261108T002103Z.md`, each moved sentence found by `grep -F` under its scenario).
After it, the change validates strictly, the discharge-name check prints three empty lists, and a scratch archive's main specs fail strict validation on exactly main's 18 pre-existing specs (`9.6-shortening-checks-20261108T002103Z.log`).

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

The working copy's `tasks.md` has every item ticked, among them 3.8, 7.4 and the seventeen items of §11; 6.1a and 8.1 under the operator's decision O2 of 2026-11-07, and 9.6 with the Linear mirror and CAM-72's move to Done made by the orchestrator.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 3.8 | ticked by tasks.md 11.6: #3736 merged at 2026-11-06T02:55:55Z with every nixbot status passing (`gh pr checks 3736`); `nix fmt` changed nothing (`3.8-fmt-20261106T024816Z.log`); at its commit `c731814f0` the four gating checks and the `fleet-ingress` container test built on magnetite (`3.8-pr-head-20261106T024835Z.log`); each cost after is in `3.8-cost-20261106T020005Z.log` (§9.1); its description names the drvPaths and states the container test passed, without the run's cases and date, recorded as a deviation | no |
| 7.4 | ticked by tasks.md 11.6: #3745 merged at 2026-11-06T22:52:36Z with every nixbot status passing (`gh pr checks 3745`); `nix fmt` changed nothing (`7.4-fmt-20261106T224439Z.log`) | no |
| 6.1a | ticked 2026-11-08 under O2: the job was kickstarted, not run by its calendar (§9.3) | no |
| 8.1 | ticked 2026-11-08 under O2 over 2026-11-07T08:24Z to 2026-11-08T00:30Z (§9.3) | no |
| 9.1 | this file, with both slots filled | no |
| 9.2 | ticked: the list is rerun and the one stale comment reworded (§10) | no |
| 9.3 | ticked: `review.md` is recorded with its dispositions applied as tasks.md §11, and `retrospective.md` is written | no |
| 9.4 | the row check prints only the `collected host` row after tasks.md 11.1 (§8a.3); the item runs again at the archive | no |
| 9.5, 9.6 | the satisfaction projection and the archive | no; they are the archive |
| 10.1 | ticked: the integration read of 2026-11-08T00:32Z (§9.4) | no |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `devloop-collection` | synced at the archive, 2026-11-08 | MODIFIES `Every dev-loop event is recorded once and kept for a year` (stibnite among the collected hosts). |
| `devloop-collection-interface` | synced at the archive, 2026-11-08 | MODIFIES `Each agent host's collector ships its own deploy records` and `This capability states its own trust boundary`. |
| `fleet-alerting` | synced at the archive, 2026-11-08 | MODIFIES `Each known failure class on a host reaches a person as an alert` and `An unreachable telemetry store or a silent host freezes alerts`. |
| `fleet-alerting-interface` | synced at the archive, 2026-11-08 | MODIFIES six requirements, from `The evaluator queries each rule's database as the regulators' store account` to `This capability states its own trust boundary`. |
| `fleet-ingress-interface` | synced at the archive, 2026-11-08 | RENAMES `pyrite's NVMe health is read by a loopback exporter`; MODIFIES six requirements; ADDS `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile` and `No darwin collection job runs on a calendar schedule`. |
| `host-metrics-collection` | synced at the archive, 2026-11-08 | MODIFIES six requirements. |
| `telemetry-store-interface` | synced at the archive, 2026-11-08 | MODIFIES eight requirements. |
| `world-assumptions` | synced at the archive, 2026-11-08 | MODIFIES `Grounded vocabulary for behavioral requirements` and ADDS A61 to A66, A70 and A77; the MODIFIED block predates main's archive of `deliver-omp-browser-relay` (`cda06e467`, 2026-11-06T01:00Z), which would have dropped 14 main rows and main's two senses of `browser`; tasks.md 11.1 retook it from main, and the row check prints only `collected host` (§8a.3). |

Of main's capability specs, only `world-assumptions` changed after the planning pull requests #3731 and #3733 (`git log --since=2026-11-05 origin/main -- openspec/specs/<capability>/spec.md`); `fleet-alerting`, `fleet-alerting-interface` and `telemetry-store-interface` changed on 2026-11-05 before them.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D6, D12 (C5) | C5 reads each job's physical footprint from `top`'s MEM field, 256 MiB and 128 MiB (5.3a) | FII `otel-envelope regulates each agent from its own collector`; TSI `The telemetry store and the collector run inside a declared envelope`; A70 | none in the deltas; 8.1's maxima are 135M and 109M (§9.3) |
| D9 (`LaunchdJobNotRunning`) | two disjoint arms after 8.3a: the running arm over the kept-alive labels, the unloaded arm over the others | FA `Each known failure class on a host reaches a person as an alert` ("a kept-alive job is not running, an allow-listed launchd job is not loaded") | none; one `[FIRING]` and one `[RESOLVED]` at 8.3a's rerun (`8.3a-ac2-20261107T192736Z.log`) |
| D3 (process floor) | darwin floor 384 MiB with the fleet executables kept below it (6.6a) | HMC `Series cardinality stays bounded`; A77 | none; 25 names over the 24 h to 2026-11-08T00:30Z, at most 19 an hour (§9.3) |
| D13 (cost) | each changed check measured before and after | tasks.md preamble line 8 | none over budget (§9.1); `darwin-stibnite` and `nixos-magnetite` were not measured after pull request 1 |

**Drift warnings** (non-blocking):

- The `world-assumptions` delta's designation table and its two-senses scenario were written against main before `cda06e467` (§3, §8a.3).
- 6.1's window, C5's evidence source and the replay script's freeze model, recorded as deviations in tasks.md 6.1 and 6.3, are not described in `design.md` beyond D12's C5 paragraph.

---

## 5. Implementation Signal

- [x] All related commits have been pushed
- [ ] No unstaged files in the worktree

The change's pull requests, all merged to `main`, from `741e0ecdc` (#3731) to `1bdc59782` (#3772):

| Pull request | Merged (UTC) | Merge commit | Content | tasks.md |
|---|---|---|---|---|
| #3731 | 2026-11-05T23:16:34Z | `741e0ecdc` | the planning pull request | — |
| #3733 | 2026-11-06T00:30:09Z | `7ec87f75e` | the plan corrected after its review | 1.1 to 1.4 |
| #3736 | 2026-11-06T02:55:55Z | `c731814f0` | pull request 1: stibnite's row with `collect = false`, its certificate, the darwin agent, the wrapper, the envelope's darwin clauses, the pending-time change | 2.1 to 3.8 |
| #3738 | 2026-11-06T04:59:39Z | `8444c8c98` | records of group 4 | 4.1 to 4.3 |
| #3739 | 2026-11-06T05:12:11Z | `501b3ea27` | pull request 2: stibnite's `collect = false` removed | 5.2 |
| #3740 | 2026-11-06T05:40:12Z | `585128280` | C5 on physical footprint | 5.3a |
| #3741 | 2026-11-06T06:34:00Z | `2ea47ee5b` | records of group 5 | 5.1 to 5.4 |
| #3743 | 2026-11-06T15:42:57Z | `9b08ae697` | pull request 3: the darwin rules | 6.2 to 6.4 |
| #3744 | 2026-11-06T21:34:39Z | `8f1764ccf` | the darwin process floor and fleet-executables keep-list | 6.6a |
| #3745 | 2026-11-06T22:52:36Z | `f70d1a0ac` | pull request 4: the documentation | 7.1 to 7.4 |
| #3771 | 2026-11-07T19:22:33Z | `e38ac7bcc` | `LaunchdJobNotRunning`'s disjoint arms | 8.3a |
| #3772 | 2026-11-07T20:05:43Z | `1bdc59782` | records of group 8 after 8.3a | 8.2 to 8.8 |

The working copy also carries other changes' unmerged edits, which this verification did not inspect.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files, or any existing files are legitimate residue from before schema installation

**Leak list** (if any):

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` and `plan/task-*.md` have no row marked `[~]`.
The operator-gated items were 4.2, 5.1, 5.2, 6.6 and 8.2 to 8.6; 8.2 to 8.6 ran unattended under the operator's approvals recorded in their `done:` notes, with the `fleet-alerts` topic read back standing in for the phone in 8.2, 8.4 and 8.6, and `pmset sleepnow` with a scheduled wake standing in for the lid in 8.6.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.

### 8a. Designation lint

#### 8a.1 Method

The pass read the statements of the six `host-metrics-collection`, two `fleet-alerting` and one `devloop-collection` requirements in this change's deltas, excluding scenarios and `Discharged by` lines.
Each content noun was looked up in the `Term` column of this change's `world-assumptions` delta table (222 rows after tasks.md 11.1 and 11.7), by the whole term or by listed terms the phrase is built from.
Quantities and identifiers (`fleet`, `devloop-collection`, host names, "24 hours", "512 MiB", "365 days", "30") were not counted.

#### 8a.2 Result

The nouns this change introduces resolve to rows the delta adds:

| Noun | Requirement | Delta row |
|---|---|---|
| darwin host | HMC `Each agent host contributes its own signals to the telemetry store`, `Series cardinality stays bounded`, `A failed collection or store job notifies a person`; FA `Each known failure class on a host reaches a person as an alert` | `darwin host` |
| launchd job | HMC `Each agent host contributes its own signals to the telemetry store`, `Series cardinality stays bounded`, `Stored unit names carry no owner's name`, `A failed collection or store job notifies a person`; FA `Each known failure class on a host reaches a person as an alert` | `launchd job`, which also grounds "last exit code" and "starts" |
| kept-alive job | FA `Each known failure class on a host reaches a person as an alert` | `kept-alive job` |
| probe ("the probe's readings") | FA `Each known failure class on a host reaches a person as an alert` | `probe` (sense `darwin host`) |
| sleep (a laptop's) | FA `An unreachable telemetry store or a silent host freezes alerts` | `sleep` |
| collected host | DC `Every dev-loop event is recorded once and kept for a year` | `collected host`, rewritten to name stibnite |

`dark wake` has a delta row and appears in A64, not in a behavioral statement.

Two nouns resolved to no row when this section was first written, and tasks.md 11.7 resolved both (`review.md` F7):

| Noun | Requirement | Resolution |
|---|---|---|
| the fleet's list of watched launchd jobs; allow-listed (launchd job) | HMC `Series cardinality stays bounded`; FA `Each known failure class on a host reaches a person as an alert` | the delta's new row `watched launchd jobs`, whose jobs are the allow-listed launchd jobs |
| supervisor | HMC `A failed collection or store job notifies a person` | reworded to "launchd", which the `launchd job` row grounds |

Every other content noun resolves to a row: `agent host`, `provisioned host`, `collector`, `memory`, `process`, `file system`, `laptop`, `disk health`, `compressed swap`, `unit`, `storage pool`, `out-of-memory`, `signal`, `series`, `telemetry store`, `database`, `source`, `log record`, `trace`, `dev-loop record`, `dev-loop history`, `query language`, `cardinality`, `identifier`, `process number`, `command line`, `queued interval`, `local state`, `ingress`, `collection`, `job`, `regulator` (which covers "periodic regulator"), `envelope`, `Omnigent worker`, `owner`, `alias`, `person`, `failure notice`, `notification service`, `notifier`, `alert`, `alert rule`, `alert instance`, `failure class`, `memory pressure`, `kernel`, `evaluator`, `condition`, `holding time`, `pass`, `silent`, `build service`, `attribute`, `outcome`, `build`, `batch event`, `merge queue` and `deploy`.

#### 8a.3 Archive-time row check (tasks.md 9.4)

Run read-only on 2026-11-07 against the working copy, before any sync:

```bash
row() { awk '/^\| /' "$1" | grep -vE '^\| *(Term|---)' | LC_ALL=C sort -u; }
LC_ALL=C comm -23 <(row openspec/specs/world-assumptions/spec.md) <(row openspec/changes/stand-up-darwin-collection/specs/world-assumptions/spec.md)
```

Main has 215 rows and the delta, after tasks.md 11.1, 222.
Output on 2026-11-07 after 11.1 (`9.4-rows-20261107T221437Z.log`):

```text
| collected host | — | a host whose deploy records a collector ships to the telemetry store: magnetite, cinnabar and pyrite, and not yet stibnite | shared |
```

Only the expected `collected host` row is printed, and the archive-time run on 2026-11-08, with `origin/main`'s specs unchanged since `cda06e467`, printed the same row alone (`9.4-rows-20261108T001543Z.log`).
Before 11.1 it printed 15 rows: the other 14 entered main with `cda06e467` ("openspec: archive deliver-omp-browser-relay", 2026-11-06T01:00Z), after this change's planning pull requests, and split main's `browser` row into the senses `dashboard` and `relay` (`review.md` F1).
11.1 retook the block from main, re-added this change's six rows and the `collected host` rewrite, added the `watched launchd jobs` row of 11.7, and states in the two-senses scenario, which lists main's twenty-four terms, that `probe` carries three senses.

### 8b. Discharge coherence

Each row names the tasks whose `Discharges:` quote the requirement and their evidence.
Each status uses the schema's three words: `configured` when only the delivered configuration or an evaluation shows it, `not violated` when a watch over a stated window saw no counter-example, and `observed` when a step made it happen and saw it, with its window.

| Requirement | Discharged by (tasks, evidence) | Under (W) | Status |
|---|---|---|---|
| devloop-collection: `Every dev-loop event is recorded once and kept for a year` | tasks.md 5.3; stibnite's `deploy_record` rows equal its file's 14 lines (`5.3-stibnite-20261106T052005Z.log`) | A65 | observed at 2026-11-06T05:20Z; 10.1 repeats the count |
| devloop-collection-interface: `Each agent host's collector ships its own deploy records` | tasks.md 2.7, 5.3; the darwin agent's `logs/devloop-deploy_record` pipeline from `file_log/deploy-record` to `otlp_http/ingress-logs`, its receiver and processor equal to electrum's, and `ok: validate agent` (`2.7-deploy-record-20261106T011815Z.log`); 14 rows for 14 lines (`5.3-stibnite-…`) | A65 | configured, and observed at 2026-11-06T05:20Z |
| devloop-collection-interface: `This capability states its own trust boundary` | tasks.md 9.1; the requirement's own statement, §8d | — | discharged by statement |
| fleet-alerting: `Each known failure class on a host reaches a person as an alert` | tasks.md 6.1, 6.1a, 6.3, 8.3, 8.3a; stored names equal D9's expressions and no would-be firing over 2026-11-06T05:17:19Z to 14:49:02Z (`6.1-names.tsv`, `6.1-replay-20261106T144527Z.log`); promtool 15 rules, nine new legs passing and nine runtime mutants rejected (`6.3-rules-20261106T151156Z.log`, `6.3-red-noexclusion-20261106T151151Z.log`); 8.3's doubled posts (`8.3-ac2-20261107T051210Z.log`), then `keptAliveUnloaded` red and green, `notRunningBothArms` rejected, and one `[FIRING] LaunchdJobNotRunning stibnite` at 19:39:03Z and one `[RESOLVED]` at 19:48:03Z (`8.3a-red-rehearsal-20261107T183332Z.log`, `8.3a-green-20261107T185455Z.log`, `8.3a-replay-20261107T185753Z.log`, `8.3a-ac2-20261107T192736Z.log`); `LaunchdJobFailed` fired and resolved for a signal kill (`8.4-signal-20261107T054220Z.log`); 6.1a's replay to 2026-11-08T00:30Z, whose only would-be firings of deployed rules are group 8's controls (`6.1a-replay-20261108T003011Z.log`) | A61, A62, A63, A64 | observed for `LaunchdJobNotRunning` and `LaunchdJobFailed`, and not violated from 2026-11-06T14:49Z to 2026-11-08T00:30Z outside the controls; `nix-cleanup-gcroots`' run was a kickstart under O2, so its calendar start is unobserved (§9.3) |
| fleet-alerting: `An unreachable telemetry store or a silent host freezes alerts` | tasks.md 3.6, 8.6, 8.7; `pendingAcrossFreeze` and `pendingAfterWake` red then green, the property test passing (`3.5-red-20261106T012702Z.log`, `3.6-transition-20261106T013921Z.log`); no post naming stibnite from 07:13:51Z to 08:23:53Z across an induced sleep with 13 dark wakes (`8.6-suspend-20261107T062837Z.log`) and from 01:08:56Z to 04:41:05Z across a natural sleep with 26 dark wakes (`8.7-overnight-20261107T083100Z.log`) | A61, A64 | observed over both sleeps |
| fleet-alerting-interface: `The evaluator queries each rule's database as the regulators' store account` | tasks.md 6.5; 31 queries a run, 16 presence selectors, 14 PromQL and 1 SQL, as `regulator`, no `StoreQueryFailing`, a run of 3.3 s (`6.5-magnetite-20261106T154826Z.log`, `6.5-rules-20261106T212717Z.log`) | — | observed from 2026-11-06T15:48:26Z |
| fleet-alerting-interface: `Alert rules are rendered from one Nix source to the evaluator and to promtool` | tasks.md 6.3, 8.3, 8.3a; `6.3-rules-…`; `8.3a-green-…`, `8.3a-cost-20261107T185819Z.log` | — | configured, and observed at 8.3a's rerun |
| fleet-alerting-interface: `Each rule's presence selector is watched` | tasks.md 3.7, 6.3; `linuxSelectorDarwinOnly` red with seven posts, then green, `stibniteNotCollecting` passing, promtool 11 rules (`3.7-red-20261106T013954Z.log`, `3.7-platform-20261106T015334Z.log`); `darwinSignalMissing` and `nvmeExpectsStibnite` (`6.2-red-20261106T145313Z.log`, `6.3-rules-…`); no `RuleSignalMissing` from 15:48:26Z to 21:27Z (`6.5-rules-…`) | — | configured, and not violated from 2026-11-06T15:48Z to 21:27Z |
| fleet-alerting-interface: `Store errors and silent hosts freeze instance state` | tasks.md 3.5, 3.6, 8.6; `3.5-red-…`, `3.6-transition-…`, `3.6-property-at-main-20261106T015256Z.log`; `8.6-suspend-…` | A61, A64 | observed across 8.6's sleep |
| fleet-alerting-interface: `The alerter token travels only as a file` | tasks.md 2.2, 2.3, 8.8; the token `_otelcol` `0400` (`2.2-role-20261106T005521Z.log`, `4.2-stibnite-20261106T031902Z.log`); hashes equal and seven readers (`2.3-vars-20261106T022341Z.log`, §9.2); anonymous POST refused with 403 and 8.2's posts with `NTFY_TOKEN_FILE` accepted (`8.8-ntfy-20261107T083142Z.log`) | A66 | configured, and observed at 2026-11-07T08:31:42Z |
| fleet-alerting-interface: `This capability states its own trust boundary` | tasks.md 7.2, 9.1; the runbook's darwin section (`7.2-runbook-20261106T221139Z.log`); §8d | — | discharged by statement |
| fleet-ingress-interface: `One host table declares the agent hosts and what each reports` | tasks.md 2.1; the assertion naming six rows with `"platform":null`, then seven rows and the scratch edit's failure (`2.1-platform-red-20261106T005354Z.log`, `2.1-platform-20261106T005406Z.log`) | — | configured |
| fleet-ingress-interface: `The collection CA issues each agent host one certificate` | tasks.md 2.2, 2.3; `CN=stibnite`, client authentication, verified against `otel-ca` (`2.3-vars-…`); key `_otelcol` `0400`, `restartUnits = [ ]`, `OTEL_CERT_SHA256` equal to the certificate's hash (`2.2-role-…`, `2.6-assertions-20261106T010311Z.log`) | — | configured |
| fleet-ingress-interface: `Each agent exports by its role` | tasks.md 2.4, 2.6; `exporterAddressOther` rejected (`2.4-check-20261106T005744Z.log`); `queue64` and `queues600` fail evaluation (`2.6-assertions-…`, `2.6-overrides.nix`); sends grew from 725 to 971 points in 60 s (`5.3-stibnite-…`) | A65 | configured, and observed at 2026-11-06T05:20Z |
| fleet-ingress-interface: `otel-envelope regulates each agent from its own collector` | tasks.md 3.3, 3.4, 5.3a, 8.1; darwin cases and `c5WrongPid` (`3.3-red-20261106T012206Z.log`, `3.3-envelope-20261106T012248Z.log`); the daemon's interval, account and calendar control (`3.4-envelope-daemon-20261106T023426Z.log`); `c5ReadsRss` and `c5UnreadablePasses` rejected and C5 live as `_otelcol` (`c5-top-red-20261106T052719Z.log`, `c5-top-green-20261106T052847Z.log`, `c5-top-live-20261106T053143Z.log`); 8.2's control, one `FAILED` and one `RESOLVED` (`8.2-envelope-20261107T045006Z.log`); 179 runs with every clause `ok` over 8.1's O2 window (`8.1-o2-20261108T003018Z.log`) | A70 | observed for the stopped-collector control, and not violated from 2026-11-07T08:24Z to 2026-11-08T00:30Z, about 16 h by O2 (§9.3) |
| fleet-ingress-interface: `A laptop's disk health is read on the host and served on loopback` (RENAMED from `pyrite's NVMe health is read by a loopback exporter`, and MODIFIED) | tasks.md 2.5, 5.3; the smartctl fixture and its expected `smartctl.prom` (`2.5-probe-20261106T005959Z.log`); eight `smartctl_device_*` series stored for stibnite (`5.3-stibnite-…`); pyrite's NVMe path unchanged since S4 | A51, A63 | configured, and observed at 2026-11-06T05:20Z |
| fleet-ingress-interface: `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile` (ADDED) | tasks.md 2.5, 8.4; eight probe cases and four mutants rejected (`2.5-probe-…`); the signal-killed fixture replaced by the recorded reply, `nonIdleNoExitCode` passing and `missingExitCodeAsZero` rejected (`8.4-signal-20261107T054220Z.log`, `8.4-fixture-build-20261107T083214Z.log`) | A62 | observed at `KILL_EPOCH=1794030140` (2026-11-07T05:42:20Z) |
| fleet-ingress-interface: `No darwin collection job runs on a calendar schedule` (ADDED) | tasks.md 2.6; `probeCalendar` and `envelopeCalendar` fail evaluation (`2.6-assertions-…`, `3.4-envelope-daemon-…`); after 8.6's wake the probe went from 504 to 505 runs within 60 s and the envelope from 210 to 211 within 300 s, with no burst (`8.6-suspend-…`) | A61 | configured, and observed across 8.6's sleep |
| fleet-ingress-interface: `This capability states its own trust boundary` | tasks.md 7.2, 9.1; `7.2-runbook-…`; §8d | — | discharged by statement |
| host-metrics-collection: `Each agent host contributes its own signals to the telemetry store` | tasks.md 5.3; `count by (host_name)` lists stibnite, and the store holds its `system_*`, `process_*`, three `launchd_job_*` and eight `smartctl_device_*` series (`5.3-stibnite-…`) | A63, A65 | observed at 2026-11-06T05:20Z; 10.1 reads the last 24 h |
| host-metrics-collection: `Each stored series names its host` | tasks.md 5.3; PromQL `count by (host_name)` and SQL `WHERE host_name = 'stibnite'` each return stibnite's rows (`5.3-stibnite-…`) | — | observed at 2026-11-06T05:20Z |
| host-metrics-collection: `Series cardinality stays bounded` | tasks.md 6.6a, 8.1; `processFloorDarwin` red on the single floor, deleted by tasks.md 11.12 as a restatement of its line (`review.md` F12), `fleetKeptBelowFloor` with `keepListIgnored` rejected (`cam72-red-20261106T212016Z.log`, `cam72-green-20261106T212230Z.log`, `cam72-assertion-mutant-20261106T212414Z.log`); B3 `ok` at 23:00Z with 17 names over 22:00 to 23:00Z (`6.6a-stibnite-20261106T215354Z.log`); 11 `launchd_label` values and 25 `process_executable_name` values, at most 19 an hour, over the 24 h to 2026-11-08T00:30Z (`8.1-o2-20261108T003018Z.log`) | A77 | observed over the 24 h from 2026-11-07T00:30Z, process collection unchanged since 6.6a's activation (§9.3) |
| host-metrics-collection: `Collection survives a telemetry store restart without losing the queued interval` | tasks.md 2.6; `queue64` and `queues600` fail evaluation, the 24 h relation with `fleetBytesPerMinute` held (`2.6-assertions-…`); both exporters' queues 0 at wake and after (`8.6-suspend-…`) | A52 | configured on stibnite; the restart path is S4's `fleet-ingress` back-pressure case, not run on darwin |
| host-metrics-collection: `Stored unit names carry no owner's name` | tasks.md 2.5, 2.6; `aliasDropped` rejected (`2.5-probe-…`); `omnigentNobody` fails evaluation (`2.6-assertions-…`); the store holds `org.nixos.omnigent-host-owner-1` and no owner's name (`6.1-names.tsv`) | — | configured, and observed at 2026-11-06T14:45Z |
| host-metrics-collection: `A failed collection or store job notifies a person` | tasks.md 3.2, 8.2; five wrapper cases, `postEveryFailure` rejected, NixOS notifier hashes unchanged (`3.2-notifier-20261106T011955Z.log`); `fleet-ingress` notice cases at the pull request's head (`3.2-fleet-ingress-20261106T015400Z.log`, `3.8-pr-head-…`); 8.2's `FAILED` at 04:57:32Z and `RESOLVED` at 05:02:34Z (`8.2-envelope-…`); 8.4's `LaunchdJobFailed` for `otelcol-process` (`8.4-signal-…`) | A65, A66 | observed at 2026-11-07T04:50:06Z to 05:12:06Z |
| telemetry-store-interface: `Scrape targets are reached on loopback` | tasks.md 2.4; the loopback clause with `nodeListenEmpty` and `exporterAddressOther` rejected (`2.4-check-…`); `nodeWildcard` fails evaluation (`2.6-assertions-…`) | — | configured |
| telemetry-store-interface: `The collector's configuration bounds what it gathers` | tasks.md 2.4, 6.6a; six clauses `ok`, `seventhIdentityAttribute`, `processEndpoint` and `diskIncludeAll` rejected, both `otelcol-contrib validate` cases `ok` (`2.4-check-…`); the darwin floor of 384 MiB and the fleet-executables keep-list (`cam72-green-…`) | A77 | configured; tasks.md 11.2 states each platform's floor and the keep-list, and the `fleetKeptBelowFloor` scenario with `keepListIgnored` (`review.md` F2) |
| telemetry-store-interface: `The telemetry store and the collector run inside a declared envelope` | tasks.md 2.6, 3.3, 5.3a, 8.1; the limiters and queue assertions (`2.6-assertions-…`); C5's cases and mutants (`3.3-envelope-…`, `c5-top-green-…`); 105 consecutive passing C5 runs to about 15:40Z on 2026-11-06 (`6.1-replay-…`, `## Decision`); 179 `C5 memory: ok` lines and no other line over 8.1's O2 window, and the sampler's maxima `otelcol` 135M and `otelcol-process` 109M (`8.1-o2-20261108T003018Z.log`) | A70 | configured; tasks.md 11.3 added `limitersAsDeclared` and `c5LimitsAsDeclared` over stibnite's evaluated fragment with four mutants rejected (`11-checks-20261107T221356Z.log`); observed below C5's limits from 2026-11-07T19:59Z to 2026-11-08T00:30Z, and C5 passing on every run from 08:24Z (§9.3) |
| telemetry-store-interface: `Credentials exist only as activation-resolved files owned by non-worker users` | tasks.md 2.2; the key and the token `_otelcol` `0400` in evaluation (`2.2-role-…`) and on stibnite (`4.2-stibnite-…`) | — | configured, and observed at 2026-11-06T03:18Z |
| telemetry-store-interface: `Omnigent unit names are stored under aliases` | tasks.md 2.5, 2.6; `aliasDropped`, `omnigentNobody` (`2.5-probe-…`, `2.6-assertions-…`); `6.1-names.tsv` | — | configured, and observed at 2026-11-06T14:45Z |
| telemetry-store-interface: `Failure notices are posted to one topic` | tasks.md 3.2, 3.4, 8.2; `3.2-notifier-…`, `3.4-envelope-daemon-…`; both 8.2 posts read back from `fleet-alerts` (`8.2-envelope-…`) | A66 | observed at 2026-11-07T04:57:32Z and 05:02:34Z |
| telemetry-store-interface: `A failure episode ends at the unit's next successful start or exit` | tasks.md 3.2, 8.2; the wrapper's pass, fail, fail, pass case (`3.2-notifier-…`); `RESOLVED` from the first run after the bootstrap (`8.2-envelope-…`) | — | observed at 2026-11-07T05:02:34Z |
| telemetry-store-interface: `This capability states its own trust boundary` | none in `tasks.md` (§1); §8d | — | discharged by statement; not named by any `Discharges:` |
| world-assumptions: `Grounded vocabulary for behavioral requirements` (MODIFIED) | tasks.md 9.1, 11.1, 11.7; §8a | — | discharged by the lint: after tasks.md 11.1 and 11.7 both §8a.2 nouns resolve to a row, and the row check prints only `collected host` (§8a.3) |

The rows of A61 to A66, A70 and A77 are in §8c.
Every ADDED or MODIFIED requirement is discharged; the rows that rest on 8.1 or 6.1a are discharged under the operator's decision O2 of 2026-11-07 (§9.3).

### 8c. World assumptions

| Assumption | Discharged by (tasks, evidence) | Status and window |
|---|---|---|
| `A61 — launchd misses a StartInterval firing during sleep and coalesces missed StartCalendarInterval firings into one run at wake` | tasks.md 8.6, 6.1a; the `StartInterval` half: across the sleep from 2026-11-07T07:13:58Z to 07:53:52Z the probe ran once within 60 s of wake and the envelope once within 300 s, then 30 and 6 runs in 30 min, no burst (`8.6-suspend-…`); the calendar half: no darwin collection job uses `StartCalendarInterval`, and `harmonia-gc` ran once at its scheduled 08:16Z on 2026-11-06 and on 2026-11-07 while awake (`6.1-replay-…`, `6.1a-replay-20261108T003011Z.log`) | `StartInterval` half observed over 8.6's sleep; calendar half not violated from 2026-11-06T05:12Z to 2026-11-08T00:30Z; its coalescing at wake is unobserved, because 6.1a's run was a kickstart under O2 (§9.3) |
| `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs` | tasks.md 2.5, 8.4; the 1.3 survey (`cam72-evidence/1.3-rehearsal-20261105T233403Z.log`); after `SIGKILL` at 05:42:20Z on 2026-11-07, no `last exit code` or `last exit reason` line, `last terminating signal = Killed: 9`, and `launchd.prom` -1 (`8.4-signal-…`) | observed at `KILL_EPOCH=1794030140` (2026-11-07T05:42:20Z) |
| `A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools` | tasks.md 5.3; eight `smartctl_device_*` series stored, read by `_prometheus-node-exporter` (`5.3-stibnite-…`); `RuleSignalMissing` on the NVMe selectors not posted for stibnite from 2026-11-06T15:48Z (`6.5-rules-…`) | observed at 2026-11-06T05:20Z, and not violated from 15:48Z to 21:27Z |
| `A64 — stibnite sleeps and wakes in the dark many times a day` | tasks.md 8.6, 8.7; 13 dark wakes in 8.6's 40 min sleep and 26 in 8.7's natural sleep; per local day `pmset -g log` holds 37, 22, 69, 132, 92, 38 and 66 `Sleep` entries and 36, 18, 63, 124, 87, 32 and 64 `DarkWake` entries from 2026-10-31 to 2026-11-06, and `pmset -g` now prints `sleep 0` with sleep prevented by `omp` and `powerd` assertions (`9.1-a64-counts-20261107T213934Z.log`) | observed over 8.6's and 8.7's sleeps; the daily counts fall below the stated 90 to 140 on five of seven days, which the violation scenario names "far outside this range" (`review.md` F8) |
| `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier` | tasks.md 5.3; the store-built collector's sends grew from 725 to 971 points in 60 s (`5.3-stibnite-…`); store curl verified `ntfy.zt` as `_otelcol` (`7.3-ntfy-curl-proof-20261106T220636Z.log`) | observed at 2026-11-06T05:20Z, and not violated since; 10.1 reads the last 24 h |
| `A66 — ntfy refuses an anonymous post to a fleet topic from stibnite` | tasks.md 8.8; 403 at 08:31:42Z (`8.8-ntfy-…`) | observed at 2026-11-07T08:31:42Z |
| `A70 — macOS top prints a process's physical footprint as unversioned text to an unprivileged account` | tasks.md 5.3a, 8.1; `c5-top-recording-20261106T052605Z.log`, `c5-top-live-…`; every C5 run passing from #3740's activation except 8.2's control (`8.1-day-…`); 512 sampler readings from 2026-11-07T19:59:00Z to 2026-11-08T00:30Z, none absent or unread (`8.1-footprint-20261107T195859Z.tsv`) | observed at 2026-11-06T05:26Z, and not violated from 06:28Z to 2026-11-08T00:30Z |
| `A77 — macOS resident size counts each process's mapped share of the shared cache, so ordinary processes read tens to hundreds of MiB` | tasks.md 6.6a; 82 names above 64 MiB and the hourly peaks per floor (`cam72-stibnite-names-20261106T211506Z.log`, `cam72-hourly-floors-20261106T211514Z.log`, `cam72-hostpeaks-20261106T211536Z.log`) | observed from 2026-11-06T05:17Z to 21:14Z |

### 8d. Trust boundaries

Four requirements state the trust boundary of a capability this change modifies, and each is discharged by its own statement; no regulator applies.
Their scenarios state them as follows.

**fleet-ingress-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a host's series reach the store.

- Read as a set, the properties establish that each agent host holds a certificate from `otel-ca`, that the ingress accepts only such holders on magnetite's ZeroTier address at TLS 1.3, that each agent, darwin included, queues and retries toward it, that the darwin probe writes launchd job state and disk health for the loopback node_exporter, and that `otel-envelope` regulates each collector and the fleet budget, each as far as its check, assertion, container test or recorded observation reaches.
- A host cannot be shown to write series only under its own name: any holder of an `otel-ca` certificate is trusted to write, and a certificate's CN is not bound to the `host.name` its agent stamps.
- A lost or stolen agent key is not shown to stop being accepted: certificates have no revocation, a lost key stays valid until `otel-ca` is rotated, and stibnite's key sits on a laptop that leaves the operator's premises.
- ZeroTier does not authenticate the writer: the two Android members and the darwin machines without a certificate reach the handshake and only mTLS refuses them.
- The probe's launchd series are not shown correct after a macOS update: the probe trusts `launchctl print`'s text, which is not API, under A62.
- A darwin host's collection does not run without root: `org.nixos.otelcol-process` runs as root, confined to the `process` scraper with no receiver endpoint, telemetry listener or credential, and any root process on that host can read the `_otelcol` key and inject points on loopback.
- These properties do not guarantee that a given series reaches the store: nothing here observes a series' whole path.

**fleet-alerting-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

- Read as a set, the properties establish that the evaluator queries each rule's database as `regulator`, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats, the dead-man and its ping behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured as stated.
- ntfy's refusal of anonymous `fleet-*` publishes, its per-client rate limits and its delivery to a device are not guaranteed: ntfy enforces them and this machine only configures it.
- The `alerter` token is not readable only by its consumers: any root process on magnetite, cinnabar, pyrite, electrum, galena, scheelite or stibnite can read it, and on stibnite so can any process running as `_otelcol`.
- A compromised stibnite can post to any `fleet-*` topic, alerts and heartbeats included, and its copy of the token travels on a laptop and stays valid until the shared token is replaced.
- An outage of cinnabar or its ntfy is reported only through healthchecks.io's email, whose period, grace and integration this machine does not set, and whose ping URL is a bearer credential.
- These properties do not guarantee that an alert reaches a person: nothing here observes an alert or an email reaching a device.

**devloop-collection-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a dev-loop event reaches the store.

- Read as a set, the properties establish that the queries, the journal parse and the deploy snippet select, parse and write the stated fields, that the tables, pipelines and routes carry them into `devloop` keyed as stated, that the readers authenticate by peer under column grants, and that the reconcile compares each signal with its source daily.
- An event nixbot or gitea-mq never records is not detected.
- Not only the reconcile can read the `regulator` password or the deploy-record file.
- Deploys on hosts other than magnetite are not reconciled: stibnite's records are compared only by the operator at its first activation (5.3) and by 10.1.
- A deploy record stibnite writes while it sleeps or is off the mesh reaches `devloop` only after it wakes and reaches the ingress again.
- A `deploy_record` row's `host` does not prove which host sent it.
- These properties do not guarantee that a given event reaches the store.

**telemetry-store-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a series reaches the telemetry store or that a failure reaches a person.

- Read as a set, the properties establish loopback listeners, gated `/v1/` paths, the ingest and read paths, retention, object-storage configuration, credential files, the declared envelope with darwin's runtime memory clause, the persistent bounded queue, and the hand-off of named units' and darwin's wrapped `otel-envelope`'s failures to the notifier's posting code, each as far as its own check, assertion, test or observation reaches.
- R2's durability and the R2 token's scope are not asserted.
- Loopback binding does not limit access to the named consumers: any root process on magnetite can reach the listener.
- A failure notice reaching a person, and only the notifier and the evaluator publishing to `fleet-alerts`, are not guaranteed: ntfy enforces the token, any root process on a host holding a copy can read it, on stibnite where `_otelcol` owns it, and cinnabar is a single unwatched delivery path.
- These properties do not guarantee that a given series reaches the telemetry store.

---

## 9. Evaluation cost and observations

### 9.1 Evaluation cost of each new or changed check

The budget is 536,870,912 B of `gc.totalBytes` (tasks.md preamble line 8).
The method is `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#.checks.<system>.<check>.drvPath`, reading `.gc.totalBytes` and `.cpuTime`; from 6.2 on it is wrapped by `cost.sh`, over the working copy.
Every "before" is 1.2's figure at `main@origin` `b325407984e6` in a pristine workspace (`cam72-evidence/1.2-baseline-20261105T230914Z.log`).
The about 117 MB that `0-base-main-20261106T005345Z.log` reads higher comes from its command, `base.sh`, writing the attribute path without the `.` after `#`, which makes nix look under `packages` and `legacyPackages` first, as S4's `verify.md` §9.1 found for `fleet-alert`; a `git+file?rev=` reference by itself adds only about 0.25 MB (`9.3-config-cost-*.log`, `review.md` F19); the `before(@-)` line of `8.3a-cost-…` reads 113 MB higher, and its command was not recorded, so the same cause there is an inference.

| Check | Point | `gc.totalBytes` | cpuTime (s) | Log |
|---|---|---|---|---|
| `otel-collector-darwin` (new) | before | none | — | the check did not exist |
| | at 2.4 | 142,351,712 | — | `2.4-check-20261106T005744Z.log` |
| | pull request 1 | 162,702,064 | 0.57 | `3.8-cost-20261106T020005Z.log` |
| | after 5.3a | 162,719,408 | 0.55 | `c5-top-cost-20261106T053106Z.log` |
| | after 6.3 | 162,719,408 | 0.58 | `6.3-cost-after-20261106T152509Z.log` |
| | after 6.6a | 162,806,592 | 0.58 | `cam72-final-cost-20261106T212608Z.log` |
| | after 8.4's fixture | 162,806,592 | — | `8.4-fixture-build-20261107T083214Z.log` |
| | after tasks.md §11 (clauses over stibnite's fragment, `processFloorDarwin` deleted) | 175,478,368 | 0.70 | `9.x-cost-before-20261107T221237Z.log` (162,820,512 before), `9.x-cost-after-*.log` |
| `otel-envelope` (changed) | before | 157,616,512 | 0.68 | `cam72-evidence/1.2-baseline-…` |
| | pull request 1 | 157,918,048 | 0.54 | `3.8-cost-…` |
| | after 5.3a | 158,006,224 | 0.56 | `c5-top-cost-…` |
| | after 6.6a | 158,006,224 | 0.56 | `cam72-final-cost-…` |
| `fleet-alert` (changed) | before | 351,940,224 | 1.19 | `cam72-evidence/1.2-baseline-…` |
| | pull request 1 | 358,952,224 | 1.03 | `3.8-cost-…` |
| | before 6.2 | 358,966,288 | 1.08 | `6.2-cost-before-20261106T145022Z.log` |
| | after 6.3 | 373,999,568 | 1.12 | `6.3-cost-after-…` |
| | after 8.3a | 377,744,832 | 1.17 | `8.3a-cost-20261107T185819Z.log` |
| | after tasks.md §11 (comments and the two summaries) | 377,859,392 | 1.18 | `9.x-cost-before-20261107T221237Z.log` (377,779,088 before), `9.x-cost-after-*.log` |
| `otel-collector-config` (changed) | before | 477,579,776 | 1.81 | `cam72-evidence/1.2-baseline-…` |
| | pull request 1 | 477,678,976 | 1.49 | `3.8-cost-…` |
| | before 6.2 / after 6.3 | 477,685,520 / 477,690,720 | 1.52 / 1.48 | `6.2-cost-before-…`, `6.3-cost-after-…` |
| | after 6.6a | 477,692,544 | 1.49 | `cam72-final-cost-…` |
| | each pull request's parent and merge commit, from `b325407984e6` to `main@origin` `1bdc59782`, from a `git archive` tree | 477,578,128 to 477,687,296; `1bdc59782` 477,681,504 | 1.48 to 1.59 | `9.3-config-cost-*.log` |
| `nixos-magnetite` (machine check) | before / pull request 1 | 2,866,073,776 / 2,866,211,104 | 12.84 / 10.87 | `cam72-evidence/1.2-baseline-…`, `3.8-cost-…` |
| `darwin-stibnite` (machine check) | before / pull request 1, `collect` false | 3,278,070,864 / 3,279,613,456 | 12.77 / 12.01 | same |

Every check under the budget stayed under it; the highest, `otel-collector-config`, is at 0.445 GiB.
The machine checks are outside the budget by design and are recorded only.
Costs this change never measured: `darwin-stibnite` with `collect` true and `nixos-magnetite` after pull request 1, so the separate cost of #3739, #3740, #3743, #3744 and #3771 on the machine checks is unknown.

### 9.2 Vars step (tasks.md 2.3)

The sha256 of `vars/shared/otel-ca/ca.crt/value` was `7c2d055b…f51c4699` and of the decrypted `ntfy-alerter` token `1e023789…b4ddff71` at 1.2, before the step, after `clan vars generate stibnite --generator otel-cert`, after `clan vars fix stibnite --generator otel-ca` and after `clan vars fix stibnite --generator ntfy-alerter`, each with `CLAN_NO_COMMIT=1`; the certificate reads `CN=stibnite` and verifies against `otel-ca`, and the token's readers are cinnabar, electrum, galena, magnetite, pyrite, scheelite and stibnite (`2.3-vars-20261106T022341Z.log`).

### 9.3 Deploy, activation and acceptance records

Times are from `window.env` and the `done:` notes of `tasks.md`.
Each log cited was scanned with `rg -n 'tk_|BEGIN .*PRIVATE'`, which matched none of `logs/s5-evidence/`; the logs of groups 4 to 6 hold no `## Causes` heading, and their posts' causes are those of the `done:` notes repeated here.

| Event | Time (UTC) | Posts since its start, with causes | Evidence |
|---|---|---|---|
| magnetite deployed with pull request 1 (4.1) | 2026-11-06T02:57:11Z | none to 03:06Z | `4.1-magnetite-20261106T025711Z.log` |
| cinnabar deployed with pull request 1 (4.3) | 2026-11-06T02:59:02Z | `[RESOLVED] SystemdUnitFailed cinnabar` at 03:06:03Z, the reset of a notifier failed since the CAM-76 ntfy stop | `4.3-cinnabar-20261106T025902Z.log` |
| stibnite's routine activation, `collect` false (4.2) | about 2026-11-06T03:18Z | none; only the two secrets added | `4.2-stibnite-20261106T031902Z.log` |
| stibnite's watched activation (5.2) | after 05:12:11Z; daemons running at 05:20:05Z | `FAILED otel-envelope on stibnite` at 05:22:16Z, C5's resident-size measure (5.3a) | `5.3-stibnite-20261106T052005Z.log` |
| magnetite deployed after 5.2 (5.4) | 2026-11-06T05:23:38Z | `FAILED fleet-alert.service on magnetite` at 05:25:01Z, an evaluator run stopped by the switch (CAM-85), resolved at 05:25:13Z | `5.4-magnetite-20261106T052338Z.log` |
| magnetite deployed with pull request 3 (6.5) | 2026-11-06T15:48:26Z | `FAILED otel-envelope on magnetite` at 15:50Z, B3 on stibnite's 63 process names (6.6a) | `6.5-magnetite-…`, `6.5-rules-…` |
| stibnite activated with pull request 3 (6.6) | 2026-11-06T15:51:20Z | only 6.5's B3 failure | `6.6-stibnite-20261106T155153Z.log` |
| stibnite activated with #3744 (6.6a) | 2026-11-06T21:50:58Z | B3 `FAILED` at 22:00Z on the pre-fix hour, `RESOLVED otel-envelope.service on magnetite` at 23:00:03Z | `6.6a-stibnite-20261106T215354Z.log` |
| `org.nixos.otelcol` booted out (8.2) | `OTELCOL_STOP_EPOCH=1794027006` to `OTELCOL_START_EPOCH=1794027726` (04:50:06Z to 05:02:06Z) | `FAILED otel-envelope on stibnite` at 04:57:32Z and `RESOLVED` at 05:02:34Z; an aborted first launch at `1794026796` booted it out 40 s with no post | `8.2-envelope-20261107T045006Z.log`, `8.2-envelope-20261107T044636Z.log` |
| `nix-grpc-daemon` booted out (8.3) | `GRPC_STOP_EPOCH=1794028332` to `GRPC_START_EPOCH=1794029232` (05:12:12Z to 05:27:12Z) | two `[FIRING] LaunchdJobNotRunning stibnite` at 05:23:04Z and two `[RESOLVED]` at 05:32:03Z, both arms of the first form (8.3a) | `8.3-ac2-20261107T051210Z.log` |
| `otelcol-process` killed (8.4) | `KILL_EPOCH=1794030140` to `KICKSTART_EPOCH=1794030501` (05:42:20Z to 05:48:21Z) | `[FIRING] LaunchdJobFailed stibnite` at 05:48:03Z and `[RESOLVED]` at 05:53:03Z | `8.4-signal-20261107T054220Z.log` |
| scratch activation and revert (8.5) | `RELOAD_EPOCH=1794031107` (05:58:27Z) and `REVERT_EPOCH=1794032012` (06:13:32Z) | none to 06:28:32Z | `8.5-reload-20261107T055826Z.log` |
| induced sleep (8.6) | `LID_CLOSE_EPOCH=1794035631` to `LID_OPEN_EPOCH=1794038033` (sleep 07:13:58Z, wake 07:53:52Z) | none naming stibnite to 08:23:53Z | `8.6-suspend-20261107T062837Z.log`, `8.6-reread-20261107T083158Z.log` |
| natural overnight sleep (8.7) | 2026-11-07T01:08:56Z to 04:11:05Z | none naming stibnite; magnetite's B3 `FAILED` at 03:00:04Z and `RESOLVED` at 04:00:08Z during CI builds, and `[FIRING] PullRequestQueueWaitBurn` at 04:13:03Z | `8.7-overnight-20261107T083100Z.log` |
| anonymous post (8.8) | 2026-11-07T08:31:42Z | 403 | `8.8-ntfy-20261107T083142Z.log` |
| magnetite deployed with #3771 (8.3a) | 2026-11-07T19:22:53Z | none | `8.3a-magnetite-20261107T192253Z.log` |
| `nix-grpc-daemon` booted out again (8.3a) | `GRPC_STOP_EPOCH=1794079659` to `GRPC_START_EPOCH=1794080559` (19:27:39Z to 19:42:39Z) | one `[FIRING] LaunchdJobNotRunning stibnite` at 19:39:03Z, one `[RESOLVED]` at 19:48:03Z, and `[FIRING] AlertBudgetExceeded` at 19:40:03Z counting the day's deliberate posts, a deviation from 8.3a's "nothing else" (`review.md` F14) | `8.3a-ac2-20261107T192736Z.log`, `8.3a-final-20261107T192734Z.log` |

#### tasks.md 6.1a, under the operator's decision O2 of 2026-11-07

`org.nixos.nix-cleanup-gcroots` was kickstarted at 2026-11-08T00:12:53Z instead of waiting for its first calendar run on or after 08:30Z (Sunday 03:30 `America/New_York`); it ran to 00:12:58Z with exit 0 and `runs = 2` (`6.1a-kickstart-20261108T001253Z.log`).
The concession is that launchd's calendar trigger is not exercised, so A61's coalescing of a missed calendar firing at wake stays unobserved.
Its one earlier run predates collection: the stored `launchd_job_runs_total{launchd_label="org.nixos.nix-cleanup-gcroots"}` is 1 from its first sample at 2026-11-06T04:37:30Z and 2 from the scrape at 2026-11-08T00:14:06Z.

`logs/s5-evidence/6.1-stibnite-replay.sh 1793976542` replayed 2026-11-06T14:49:02Z to 2026-11-08T00:30:02Z, 2022 steps, at 00:30Z (`6.1a-replay-20261108T003011Z.log`, `## Causes`).
Its would-be firings of deployed rules are group 8's three deliberate controls:

- `LaunchdJobNotRunning`, `org.nixos.nix-grpc-daemon`, firing at 2026-11-07T05:23:02Z and resolving at 05:32:02Z: 8.3's bootout from 05:12:12Z to 05:27:12Z.
- `LaunchdJobNotRunning`, `org.nixos.nix-grpc-daemon`, firing at 2026-11-07T19:39:02Z and resolving at 19:48:02Z: 8.3a's rerun from 19:27:39Z to 19:42:39Z.
- `LaunchdJobFailed`, `org.nixos.otelcol-process`, firing at 2026-11-07T05:48:02Z and resolving at 05:53:02Z: 8.4's `SIGKILL` at 05:42:20Z.

Each `LaunchdJobNotRunning` episode replays as two instances because the script holds 6.1's two-arm expression, which 8.3a made disjoint; the deployed rule posted once at 8.3a's rerun.
The cleanup job's run fires no rule, its last exit code staying 0; no other rule and no `RuleSignalMissing` selector has a would-be firing, and `HostProbeStale` held on 154 steps in runs of at most 7, below its 10 min `for`.
No would-be firing lacks a cause, so none was put to the operator.

#### tasks.md 8.1, under the operator's decision O2 of 2026-11-07

O2 judges 8.1 over 2026-11-07T08:24Z, the end of group 8's deliberate runs, to 2026-11-08T00:30Z, about 16 h instead of the 24 h from 19:22:53Z first chosen; the read ran at 00:30Z (`8.1-day-20261108T003011Z.log`, `8.1-o2-20261108T003018Z.log`, `8.1-closures-20261108T001427Z.log`).
Stibnite's collection was constant over the window.
The activations at 2026-11-07T21:58:06Z and 22:59:17Z, deploy-record closures `4l3ha4hd…` and `35zl7gwh…`, updated agent tools only (`nix store diff-closures`: bun, codex, omp and other agent packages, and the flake `source`).
The five collection plists `org.nixos.{otelcol,otelcol-process,otel-envelope,otel-host-probe,prometheus-node-exporter}` resolve to identical store paths in `vnqf98bd…` and `35zl7gwh…`, and the collectors' pids 14796 and 83655 were unchanged.
The window's deliberate run is 8.3a's rerun, `nix-grpc-daemon` booted out from 19:27:39Z to 19:42:39Z, with the three posts of the last row above.

- `notify.log` `FAILED` lines in the window: none; its two lines are 5.3a's at 2026-11-06T05:22:15Z and 8.2's at 2026-11-07T04:57:31Z.
- `FAIL` lines in `/var/log/otelcol/otel-envelope.log` in the window: none. The log has no timestamps; its 17 `FAIL` lines are all at or before line 979, and it held 1154 lines at 2026-11-07T08:29:52Z (`8.1-day-20261107T082952Z.log`), so the window's runs lie in lines 1150 to 2044, which are 179 runs with every clause `ok`, among them 179 `C5 memory: ok` lines, and no other line.
- The probe's runs against each awake minute: of 902 stored textfile scrapes, one found `launchd.prom` older than 120 s, at 17:09:03Z with age 493 s, the first scrape after a wake, its preceding memory sample 523 s earlier.
- Stibnite's distinct stored `launchd_label` values: 11, against a bound of 30.
- Stibnite's distinct stored `process_executable_name` values: 25 over the full 24 h from 2026-11-07T00:30Z to 2026-11-08T00:30Z, at most 19 an hour, and 24 in the window, against a bound of 30. The 24 h read stands because process collection is unchanged since 6.6a's activation at 2026-11-06T21:50:58Z: no deploy-record closure since then changed `org.nixos.otelcol-process`'s plist, and the 2026-11-07T05:59:39Z and 06:13:47Z pair, `vnqf98bd…` to `dmrlfj4k…` and back, was 8.5's scratch reload, which changed only `otelcol`'s start script by one comment line.
- The maxima of physical footprint from the sampler, 256 readings each from 19:59:00Z to 00:30Z, none absent or unread: `otelcol` 135M at 20:32:12Z and `otelcol-process` 109M at 22:53:43Z, against C5's 256 MiB and 128 MiB. After the one sleep in the sampler's span, 23:32:15Z to 23:38:41Z, the next hour's maxima were 134M and 108M; the window's sleeps from 17:00Z to 18:05Z precede the sampler, and 8.6 recorded the footprint after its sleep.

The concessions are the window's length and that the footprint maxima cover its last 4.5 h; the envelope's C5 bound passed on every run across the window.

### 9.4 Integration (tasks.md 10.1)

Plan Task 9 Step 6 ran read-only at 2026-11-08T00:32:23Z over the 24 h from 2026-11-07T00:32:23Z, through `logs/s5-evidence/10.1-integration.sh`, because `promq.sh`, `gsql.sh`, `posts.sh` and `5.3-tables.tsv` do not exist; its queries go through `just obs-promql` and `just obs-sql`, and the posts are read back from the `fleet-alerts` topic with the alerter token (`10.1-integration-20261108T003223Z.log`, `## Causes`).

| Read | Query | Result |
|---|---|---|
| stibnite's series over the last 24 h | `count by (host_name) (count_over_time(<metric>{host_name="stibnite"}[24h]))` | memory 3, process 25, file system 3, `launchd_job_state` 44, `launchd_job_last_exit_code` 11, `launchd_job_runs_total` 11, `node_textfile_mtime_seconds` 2, both `smartctl_device_*` 1, and the disk tables `system_disk_io_bytes_total`, `system_disk_operation_time_seconds_total` and `system_disk_operations_total` 2 each, all under `host_name="stibnite"` |
| gaps over 60 s outside recorded sleeps | stored `system_memory_usage_bytes` sample times against `pmset -g log`'s `Sleep` entries | 41 gaps; 37 hold a `Sleep` entry; 04:49:17Z to 05:02:07Z is 8.2's bootout of `otelcol`; three of 61 s at 19:26:51Z, 23:06:51Z and 23:53:14Z are consecutive samples one interval apart plus 1 s, with no sample missing |
| deploy records | `wc -l < /var/log/deploy-record.jsonl`; `SELECT count(*) FROM deploy_record WHERE host = 'stibnite'` on `devloop` | 21 lines and 21 rows |
| S4's series | `count by (host_name) (count_over_time(<metric>[24h]))` | `system_memory_usage_bytes` and `system_filesystem_usage_bytes` for magnetite, cinnabar, pyrite and stibnite; `systemd_unit_state` and `node_zfs_zpool_state` for magnetite, cinnabar and pyrite; pyrite's `smartctl_device_critical_warning_total` 1440 samples |
| posts in the last 24 h | `fleet-alerts` read back since the window's start | 14 posts, each caused: magnetite's B3 `FAILED` and `RESOLVED` at 03:00:04Z and 04:00:08Z and `[FIRING] PullRequestQueueWaitBurn` at 04:13:03Z (8.7); 8.2's pair; 8.3's doubled pairs; 8.4's pair; 8.3a's pair and `[FIRING] AlertBudgetExceeded` at 19:40:03Z; none since 19:48:03Z |

The controls of 8.2 to 8.6 are the rows of §9.3 above.

---

## 10. Migration flags (tasks.md 9.2)

Read-only on 2026-11-07, and again on 2026-11-08 (`9.2-flags-20261108T001524Z.log`), with plan Task 9 Step 2's `rg -n '\bcollect\b'` over its eight files and `rg -n 'collect = false' modules/lib/observability-hosts.nix`.
Stibnite's row has no `collect = false`; pull request 2 removed it.
When this section was first written the second command printed the file's header comment, which states the joining procedure; after tasks.md 11.9 reworded it without the literal, the command prints nothing and exits 1, as it did on 2026-11-08:

| Location | Line | Proposed disposition |
|---|---|---|
| `modules/lib/observability-hosts.nix:4-6` | "a host joining the fleet enters with its `collect` false until its watched first deploy", reworded by tasks.md 11.9 | permanent: it states the joining procedure the runbook and README repeat, and no row uses it (`review.md` F9) |
| `modules/lib/observability-hosts.nix:13` | the `agent` helper's `collect = true` | permanent: the default |
| `modules/clan/services/otel-collector/flake-module.nix:25`, `:999-1028` | the NixOS role's import and credential gate on `collect` | permanent: the role's import gate |
| `modules/clan/services/otel-collector/flake-module.nix:1043-1067` | the darwin role's account and secrets on every darwin row, and its fragment import where `collect` is true | permanent: the role's import gate |
| `modules/darwin/otel-collector-agent.nix:3` | header: imported where `collect` is true | permanent |
| `modules/nixos/fleet-alert/rules.nix:23`, `:63` | expected hosts from the collecting rows | permanent: the rules' `collecting` filter |
| `modules/checks/fleet-alert.nix:1567`, `:1573-1574` | `linuxSelectorDarwinOnly` and `stibniteNotCollecting`, with `collect` forced | permanent: fixtures rendering a table with `collect` forced; `stibniteNotCollecting`'s comment, which said the leg keeps its meaning "once the host table drops stibnite's collect = false", is reworded at the close-out to "Explicit, so the leg holds whatever stibnite's row says." |
| `modules/checks/fleet-alert.nix:25-27`, `:1192` | the pyrite legs' comments | reworded by tasks.md 11.9: the legs force pyrite's `collect` each way, so they hold whatever its row says (`review.md` F9) |
| `modules/checks/fleet-alert.nix:982`, `:989`, `:1203-1207`, `:1281-1282` | pyrite legs with `collect` forced each way | permanent: fixtures |
| `modules/clan/services/otel-collector/README.md:17-20`, `:30`, `:277`, `:280` | the role's gate and the joining procedure | permanent |

No conditional keyed to a darwin row's `collect` other than the role's import gate was found, so nothing this change added is a one-shot branch that can no longer apply, and the close-out removes no code.
The one reworded comment changes no host's collection derivation: with and without it, stibnite's six collection plists and magnetite's `fleet-alert`, `opentelemetry-collector` and `otel-envelope` units evaluate to the same store paths, and the stibnite plists equal those of the deployed closure `35zl7gwh…` (`9.2-drvpath-20261108T001615Z.log`); `checks.x86_64-linux.fleet-alert` evaluates.

The third list of plan Task 9 Step 1's check, run after this file was written, is pasted here:

```text
absent from verify.md:
```

---

## Overall Decision

Ready for archive.
6.1a and 8.1 are ticked under the operator's decision O2 of 2026-11-07, with its concessions (§9.3), and 10.1 read the last 24 h (§9.4).
The operator approved every recommended disposition of `review.md` on 2026-11-07, and tasks.md §11 applied them: the row check now prints only the expected `collected host` row (§8a.3), both unresolved nouns have rows (§8a.2), every requirement is discharged by name (§1), 3.8 and 7.4 are ticked (§2), 9.2's criterion prints nothing (§10), the specs state each platform's process floor and the checks that exist, and every listed statement of a per-executable sum is corrected; the sum itself is CAM-88's.

F3's condition is discharged by tasks.md 11.3: `otel-collector-darwin` reads the limiters, C5's limits and the `otlp` routing from stibnite's evaluated fragment, with five mutants each rejected on magnetite (`11-checks-20261107T221356Z.log`), at 175,478,368 B of evaluation (`9.x-cost-after-*.log`); stibnite's toplevel differs only through the flake `source` input; the otelcol, otel-envelope, probe and node-exporter derivations are identical (`9.x-drvpath-20261107T221025Z.log`, against a control that appends a blank line to an ADR).

F13's summary change, "A file system is more than …", is in code and takes effect on magnetite's next deploy.
F16 is deferred to CAM-88 and F17 rejected; F11's per-host derivation and F15's narrowing are new issues whose texts are in `logs/s5-evidence/new-issues.md`, not yet filed.
