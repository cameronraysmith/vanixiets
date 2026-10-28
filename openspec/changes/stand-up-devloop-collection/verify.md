# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `stand-up-devloop-collection`
**Verified at**: `2026-10-28 21:05–22:05 UTC`
**Verifier**: `S2Verify (agent), running plan/task-8.md Steps 1–5, 7 and 8 read-only; the 7.x evidence was recorded by the orchestrator's Task 7 runs between 2026-10-22 and 2026-10-28; Steps 2 and 3 (9.1) ran on 2026-10-28 against a substitute pull request and batch, as §10 states`

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
$ openspec validate stand-up-devloop-collection --strict   (2026-10-28 23:37 UTC, 8.1-validate-20261028T233717Z.log, after the close-out edits)
Change 'stand-up-devloop-collection' is valid
exit 0
```

This verifier ran no validator, by its brief; `openspec validate --all --json` and `openspec validate stand-up-devloop-collection --strict` are to be run once at Step 9, after the ticks, and their totals pasted here.
The change's artifacts on `origin/main` (`697a6f1ea`) last changed in #3591 (`03a95cf36`); the working copy adds `review.md`, this file and the 7.2 and 7.7 ticks in `tasks.md`.

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | — |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

`tasks.md` in the working copy has 69 ticked items and 2 unticked ones, 8.4 and 8.5.
7.2, 7.7, 8.1, 8.2, 8.3 and 9.1 were ticked on 2026-10-28 in the working copy, 8.3 under the operator's decision of §10.6; 6.4, 6.5 and 7.5 were ticked in #3591; 1.6, 1.7, 2.8 and 4.8 were ticked in #3564 (tasks.md 10.9).

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 8.4, 8.5 | the satisfaction projection, the spec sync and the archive | no; they are the archive |

---

## 3. Delta Spec Sync State

For each delta spec file under `openspec/changes/stand-up-devloop-collection/specs/`, compared against the corresponding main capability spec:

| Capability | Sync status | Notes |
|---|---|---|
| `devloop-collection` | pending sync | New capability; `openspec/specs/devloop-collection/` does not exist. |
| `devloop-collection-interface` | pending sync | New capability; `openspec/specs/devloop-collection-interface/` does not exist. |
| `fleet-alerting` | pending sync | ADDS `Pull-request builds that wait too long to start reach a person as a warning`; MODIFIES `Each known failure class on a host reaches a person as an alert` and `An unreachable telemetry store or a silent host freezes alerts`. |
| `fleet-alerting-interface` | pending sync | ADDS `The pull-request queue-wait rule reads devloop through SQL`; MODIFIES four requirements and `This capability states its own trust boundary`; RENAMES `The evaluator queries the fleet database as the regulators' store account` to `The evaluator queries each rule's database as the regulators' store account`. |
| `host-metrics-collection` | pending sync | MODIFIES `magnetite contributes its own signals to the telemetry store` (no log records narrowed to the `fleet` database). |
| `telemetry-store-interface` | pending sync | MODIFIES `Ingest is OTLP over HTTP with a database header`, `Databases and their retention are set at the telemetry store`, `Credentials exist only as activation-resolved files owned by non-worker users`, `Failure notices are posted to one topic` and `The collector's queue persists across a telemetry store restart`. |
| `world-assumptions` | pending sync | ADDS A43–A49; MODIFIES `Grounded vocabulary for behavioral requirements` (143 main rows, 178 in the delta, every main row carried; §10.6). |

All seven sync at archive, under the §10.6 decision.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 | `PullRequestQueueWaitBurn`, `warning`, `database = "devloop"`, `language = "sql"`, `for = "1h"`, no presence selector, first attempt of each build only, at least 10 builds and more than one in ten over an hour | FA `Pull-request builds that wait too long to start reach a person as a warning`; FAI `The pull-request queue-wait rule reads devloop through SQL` | none; the deployed rule renders as `{"alert":"PullRequestQueueWaitBurn","database":"devloop","language":"sql","for":3600}` (§10.5) |
| D6 | two `sqlquery` receivers as `opentelemetry-collector` by peer, `collection_interval: 60s`, `tracking_column: finished_at`, every value as text, five-minute overlap, `LIMIT 10000` | DCI `The collector reads nixbot's builds and attributes through two cursor queries`, `Each nixbot query re-reads a five-minute overlap in pages of 10,000 rows`, `Each nixbot query returns only allow-listed columns as text` | none |
| D9 | one rendered script per host appending `{"host","closure","previous_closure","ts"}` to `/var/log/deploy-record.jsonl`, mode `0644`, before the relink | DCI `Each activation appends one deploy record`, `magnetite's collector ships its own deploy records`; WA A49 | none |
| D11 | `devloop-reconcile`, `DynamicUser`, `systemd-journal`, `MemoryMax = "128M"`, daily at 02:15 UTC over the previous UTC day, clauses C1–C7 | DCI `devloop-reconcile runs daily as its own reader` and its three comparison requirements | none since #3564, which dropped `OOMScoreAdjust = 600` and its kill-order slot (tasks.md 10.6) and taught C1 the restarted-build case (tasks.md 10.2) |
| D12 | the deploy-record obligation in `withFleetObligations`, held by CI on the five x86_64-linux NixOS machine checks | DCI `The x86_64-linux NixOS machine checks carry the deploy-record snippet` | none; the claim was narrowed to the five checks by plan review F9 before implementation |

**Drift warnings** (non-blocking):

- none.

---

## 5. Implementation Signal

- [x] All related commits have been pushed
- [ ] No unstaged files in the worktree

Every S2 implementation commit is on `origin/main`.
The working copy's change directory differs from `origin/main` only by `review.md`, this file and the two ticks of `tasks.md`; it also carries other agents' unmerged chains, which this verification did not inspect.
Plan Task 8 Step 5's path-filtered `git log origin/main`, S2's commits, newest first:

```text
03a95cf36 docs(observability): S2 F1 disposition: updater bursts explain burn-rule firings; ticks 6.4, 6.5, 7.5   (#3591, tasks.md 10.10)
a106c086f fix(devloop): apply the S2 post-deployment review (F2-F10)                                         (#3564, tasks.md 10.1–10.9)
beea76ff4 docs(observability): S2 devloop runbook, collector logs path, check index and skill line          (#3563, Task 6)
a1b2aac08 feat(fleet-alert): per-rule database and language, SQL rules and the dev-loop burn rule           (#3562, Task 5)
70848c4f9 feat(devloop): daily devloop-reconcile against nixbot, the journal and the deploy record         (#3561, Task 4)
3d2baf0ed fix(devloop): journald/gitea-mq reads every retained boot                                        (#3560, before D4)
4174473d5 feat(devloop): collect nixbot, gitea-mq and deploy records into devloop                          (#3559, Task 3)
e94a1631e feat(devloop): the devloop allow-list, tables, pipelines and devloop-queries                     (#3558, Task 2)
ea7cbf60c feat(deploy-record): record every activation on the ten machines, held by the x86_64-linux NixOS machine checks (#3557, Task 1)
```

The plan landed before them as `24572bd11` (#3556).
The same path filter also lists later commits that are not S2's, among them `633362205` (`fleet-alert accepts Hypothesis's new failure banner`), which touched the `fleet-alert` check after S2.

**Commit range** (if known): `24572bd11..03a95cf36`, filtered to the S2 paths.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files, or any existing files are legitimate residue from before schema installation

The command printed nothing and exited 2, because the glob matched no file.

**Leak list** (if any):

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` and `plan/task-*.md` have no row marked `[~]`; the one `[~]` match is the instruction text at `plan/task-8.md:359`.
This section is blank by the template's rule.
7.2 and 7.7 were the human-timed `tasks.md` items; §9.4 and §9.9 record how each closed.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.
The designation table used is the one this change's `world-assumptions` delta carries (the MODIFIED `Grounded vocabulary for behavioral requirements`, 178 table lines including its header and separator).

### 8a. Designation lint

The proposal tags `devloop-collection`, `fleet-alerting` and `host-metrics-collection` `behavioral`.
A pass over the titles and statements of `devloop-collection`'s six requirements and `fleet-alerting`'s three, excluding scenarios and `Discharged by` lines, leaves these content nouns without a row:

| Noun | Requirement | Disposition proposed |
|---|---|---|
| day (UTC day), morning | `A gap in the dev-loop history reaches a person within a day` | designation table: world-only; `time zone` has a row, a calendar day does not |
| week | `The past week of the dev loop can be asked about` | designation table: world-only, the seven days before the question is asked |
| dependency (something an attribute depends on) | same, second sentence | designation table: shared; the `attribute` and `derivation` rows use it without a row |
| stored credential | `The build service's records are read without being changed and without a stored credential` | read as the existing `credential` row; the `store credential` row is the telemetry store's account, a different sense |
| kind of dev-loop record | `No error text, message body or other free text enters the dev-loop history` | read through the `dev-loop record` and `field` rows, or rephrase as "each dev-loop record" |
| hour (as a holding time) | `Pull-request builds that wait too long to start reach a person as a warning` | read through the existing `holding time` and `queue wait` rows |

Every other content noun resolves to a row: `attribute`, `outcome`, `build`, `build service`, `batch event`, `merge queue`, `deploy`, `collected host`, `dev-loop history`, `dev-loop record`, `collector`, `failure notice`, `person`, `source`, `field`, `error text`, `message body`, `free text`, `formation-to-land`, `queue wait`, `pull request`, `flaky attribute`, `abandoned attribute`, `closure`, `commit`, `host`, `database`, `service`, `alert`, `severity` (warning), `alert rule`, `alert instance`, `telemetry store`, `evaluator`, `memory pressure`, `kernel`, `process`, `out-of-memory`, `storage pool`, `unit`, `notifier`, `series` and `signal`.
Each row above is a finding for the retrospective's Promote section, not a rewrite applied here.

### 8b. Discharge coherence

Each behavioral requirement's `Discharged by` line names its interface requirements and world assumptions, and each `tasks.md` `Discharges:` clause names the requirements its task discharges; all 52 names quoted after `Discharges:` resolve to a requirement of the deltas (`review-c-discharge-names-20261022T043332Z.log`: `discharge names: 52 checked, 0 missing`).
Evidence names are files under `logs/s2-evidence/` (git-ignored); §9 to §11 paste the decisive lines.

| Requirement | Discharged by (tasks, evidence) | Under (W) | Status |
|---|---|---|---|
| devloop-collection: `Every dev-loop event is recorded once and kept for a year` | tasks.md 3.9, 4.6, 7.4, 7.7; `devloop-ingest` cases (`3.12-devloop-ingest-20261022T013937Z.log`, `4.6-devloop-ingest-20261022T015514Z.log`); 7.4 key counts equal to row counts in every table and nixbot's counts reached (`7.4-keys-…`, `7.4-backfill-…`); per-`msg` journal counts equal after the #3560 cursor reset (`7.4-cursor-reset-20261022T015702Z.log`); the `devloop` database's TTL of one year (`7.3-tables-…`); six scheduled reconcile passes (§9.9, §10.4) | A43, A44, A46, A47 | discharged; the year's retention is shown by the TTL, not by a year of data |
| devloop-collection: `A gap in the dev-loop history reaches a person within a day` | tasks.md 4.2, 4.6, 7.5, 7.7; every reconcile clause shown failing in `devloop-ingest` (`4.6-devloop-ingest-…`, `review-c-green-devloop-ingest-20261022T043329Z.log`); the forced failure posted `FAILED devloop-reconcile.service on magnetite` and its `RESOLVED` (`7.5-forced-fail-…`, `7.5-forced-resolve-…`) | A48 | discharged |
| devloop-collection: `No error text, message body or other free text enters the dev-loop history` | tasks.md 2.2, 2.6, 3.9; `devloop-queries`' error-cell clause with `selectError` and `errorUnderAlias` (`review-c-checks-20261022T042415Z.log`); `tableShape` "no error text" and the body removed (`3.12-devloop-ingest-…`); the deployed tables have no `body` or error column (`7.3-tables-…`) | — | discharged |
| devloop-collection: `The past week of the dev loop can be asked about` | tasks.md 3.8, 3.9, 7.7; `documentedQueries` (`3.12-devloop-ingest-…`); the three questions answered on magnetite over 2026-10-21 to 10-28: 22 batches, p50/p90/p99 queue wait 223/3,939/4,859 s over 82 builds, 103 build outcomes (`7.7-questions-20261028T210554Z.log`) | A43 | discharged |
| devloop-collection: `A deploy can be attributed to the commits that built it` | tasks.md 1.3, 1.5, 7.1, 7.2, 7.7; script test (`1.3-script-test-20261021T232312Z.log`); D1 line (`7.1-deploy-record-…`); boot line without `previous_closure` (`7.2-boot-record-20261028T210758Z.log`); D5's closure joins `D5_COMMIT` `a1b2aac08` (`7.7-join-…`, `9.1-closed-record-…`) | A49 | discharged on magnetite; the other nine machines carry the snippet and are not collected in S2 |
| devloop-collection: `The build service's records are read without being changed and without a stored credential` | tasks.md 2.6; `devloop-queries` runs both readers by peer under the rendered grants with the reduced-grant mutant (`2.6-devloop-queries-20261022T002747Z.log`); both roles read by peer on magnetite (`7.4-pg-grants-…`) | A45 | discharged |
| devloop-collection-interface: `The collector reads nixbot's builds and attributes through two cursor queries` | tasks.md 2.6, 3.2, 7.4; delivered queries equal the evaluated ones and `EXPLAIN ANALYZE` with the live cursor (`7.4-explain-20261022T013222Z.log`); backfill to nixbot's counts (`7.4-backfill-…`) | A43, A47 | discharged |
| devloop-collection-interface: `Each nixbot query re-reads a five-minute overlap in pages of 10,000 rows` | tasks.md 2.5, 2.6, 7.4; overlap fixtures and case (`3.12-devloop-ingest-…`: `ok: overlap`); widest `finished_at` tie 106 rows (`7.4-tie-…`); restart did not re-send the backfill (`7.4-restart-…`) | — | discharged |
| devloop-collection-interface: `Each nixbot query returns only allow-listed columns as text` | tasks.md 2.5, 2.6, 10.3; error-cell clause rejecting `selectError` and `errorUnderAlias` (`review-c-checks-20261022T042415Z.log`) | — | discharged |
| devloop-collection-interface: `The attribute query derives abandoned from the shared marker` | tasks.md 2.5, 2.6; marker fixtures and clause (`2.6-devloop-queries-…`, `review-c-checks-…`); `abandoned only for the marker` (`3.12-devloop-ingest-…`) | — | discharged |
| devloop-collection-interface: `The nixbot readers authenticate by peer and hold column grants only` | tasks.md 2.6, 3.1, 4.1; reduced-grant mutant (`2.6-devloop-queries-…`, `4.1-devloop-queries-20261022T010421Z.log`); both roles by peer on magnetite (`7.4-pg-grants-…`) | A45 | discharged |
| devloop-collection-interface: `Column grants are applied once nixbot's columns exist` (amended by #3564) | tasks.md 3.1, 7.4, 10.1; `devloop-pg-grants` ordered after `nixbot.service`, `PartOf=` empty, active (`7.4-pg-grants-…`); unit drvPath unchanged by the wording fix (`review-c-magnetite-before-…`, `review-c-magnetite-final-…`) | — | discharged |
| devloop-collection-interface: `gitea-mq's five batch messages are parsed from its journal` | tasks.md 3.3, 4.6; parser mutant rejected (`4.6-devloop-ingest-…`); per-`msg` counts equal on magnetite after #3560 (`7.4-batch-lines-20261022T015905Z.log`) | A44 | discharged; the first observation failed (282 of 772 lines) and #3560 fixed it (§12.1) |
| devloop-collection-interface: `The collector's journal read is asserted` | tasks.md 3.7; `journalGroupCleared` override fails with the assertion's message (`3.7-journal-assertion-20261022T004027Z.log`) | — | discharged |
| devloop-collection-interface: `Each activation appends one deploy record` | tasks.md 1.3, 3.9, 7.1, 7.2; script cases (`1.3-script-test-…`); `switch` case (`3.12-devloop-ingest-…`); D1 one line with the replaced closure (`7.1-deploy-record-…`); the boot line (`7.2-boot-record-…`) | A49 | discharged |
| devloop-collection-interface: `magnetite's collector ships its own deploy records` | tasks.md 3.4, 4.6; `deployRecordOtherPath` rejected by C6 and C7 (`4.6-devloop-ingest-…`); `deploy_record` sent 3 stored 3 (`7.4-budget-…`); C6 and C7 ok daily (§10.4) | — | discharged |
| devloop-collection-interface: `The devloop tables are pre-created with keys, a time index and deduplication` | tasks.md 2.2, 2.4, 2.7, 3.9, 7.3; pre-D2 compile check on a throwaway GreptimeDB 1.2.1 (`2.7-precheck-supplement-20261022T003115Z.log`); `SHOW CREATE TABLE` of the four tables (`7.3-tables-20261022T004207Z.log`); `count(*)` equals distinct keys (`7.4-keys-…`) | A46 | discharged |
| devloop-collection-interface: `Each devloop table has an ingest pipeline that keeps only its allow-listed fields` | tasks.md 2.2, 2.7, 3.9; `tableShape` and `pipelineWithoutFlaky` rejected by C5 (`4.6-devloop-ingest-…`); the four pipelines on magnetite (`7.3-tables-…`) | — | discharged |
| devloop-collection-interface: `One devloop allow-list decides every stored column` | tasks.md 2.1; evaluated allow-list (`2.1-allow-list-20261022T001738Z.log`); `DESC TABLE` against the list (`3.12-devloop-ingest-…`) | — | discharged |
| devloop-collection-interface: `Dev-loop sources are stamped and routed to their table` | tasks.md 3.5, 3.6; R3.1 mutants `logsToFleet`, `logsToMetricsExporter`, `otlpInLogsPipeline`, `logsQueueNotPersistent` rejected (`3.6-r31-20261022T004048Z.log`); every exporter `send_failed=0` (`7.4-exporters-…`) | — | discharged |
| devloop-collection-interface: `devloop-reconcile runs daily as its own reader` (amended by #3564) | tasks.md 4.3, 4.4, 7.5, 10.6; R8.2 `fourthRegulatorHolder` override rejected (`4.4-assertion-mutants-20261022T011708Z.log`); notified units (`4.4-notified-…`); memory peaks 11.5–20 MB against 128M (`7.5-scheduled-20261024T143937Z.log`); `OOMScoreAdjust=0` after REVC (`review-c-deployed-20261022T051146Z.log`) | — | discharged |
| devloop-collection-interface: `devloop-reconcile compares CI rows with nixbot every day` (amended by #3564) | tasks.md 4.2, 4.6, 10.2; C1 and C2 mutants and the restarted-build leg red then green (`review-c-F3-red-devloop-ingest-20261022T042358Z.log`, `review-c-green-devloop-ingest-…`) | — | discharged |
| devloop-collection-interface: `devloop-reconcile compares batch events with the journal every day` | tasks.md 4.2, 4.6; C3, C4, C5 mutants rejected (`4.6-devloop-ingest-…`) | A48 | discharged |
| devloop-collection-interface: `devloop-reconcile compares deploy records with the file and the current system` | tasks.md 4.2, 4.6; `deployRecordOtherPath` and `snippetSwapsClosures` rejected (`4.6-devloop-ingest-…`) | — | discharged |
| devloop-collection-interface: `devloop-queries binds the export queries to nixbot's migrations` | tasks.md 2.6, 4.1; schema of lexically applied migrations equals magnetite's dump (`2.6-schema-diff-20261022T002833Z.log`); PostgreSQL major assertion fails under a PostgreSQL 17 override (`2.4-postgresql-major-20261022T002114Z.log`); reconcile queries run as `devloop-reconcile` (`4.1-devloop-queries-…`) | A43 | discharged |
| devloop-collection-interface: `devloop-queries binds the abandonment marker to the patch's production code` (amended by #3564) | tasks.md 2.6, 10.4; the one marker clause (`review-c-checks-…`); evaluation cost (§9.1) | — | discharged |
| devloop-collection-interface: `The x86_64-linux NixOS machine checks carry the deploy-record snippet` | tasks.md 1.4, 1.5; the obligation fails for an emptied entry and another host's script on magnetite and for an emptied `postActivation` on stibnite (`1.5-obligation-control-20261021T235131Z.log`); each configuration's activation text runs its own script (`1.4-activation-20261021T232805Z.log`) | — | discharged as it is scoped: the snippet is installed on all ten machines, CI holds the obligation only on the five x86_64-linux NixOS machine checks (cinnabar, electrum, galena, magnetite, pyrite), and the four darwin machines and the deferred scheelite were shown once by evaluation in Task 1 and are not held by CI |
| devloop-collection-interface: `devloop-ingest shows the collection path and the reconcile able to fail` | tasks.md 3.9, 4.6, 5.6, 10.7; `3.12-devloop-ingest-…`, `4.6-devloop-ingest-…`, `5.6-devloop-ingest-20261022T031031Z.log`, `review-c-green-devloop-ingest-…` | — | discharged; the `switch` case takes its recorded fallback in the container (`limitation:` line, design D16) |
| devloop-collection-interface: `This capability states its own trust boundary` | tasks.md 8.1; the requirement's own statement in its scenarios; no regulator applies | — | discharged by statement |
| fleet-alerting: `Pull-request builds that wait too long to start reach a person as a warning` | tasks.md 5.1, 5.6, 7.6; burn-rule timeline leg red before 5.2–5.4 (`5.1-red-20261022T022822Z.log`) and green (`5.5-check-20261022T030212Z.log`); `burnRule` with `thresholdHalfHour`, `everyAttempt`, `noWindow` and other expression mutants rejected (`5.6-devloop-ingest-…`); the 14-day replay (`7.6-burn-history-20261022T034631Z.log`); two `[FIRING]` and one `[RESOLVED]` since D5, each from a flake-updater burst (`7.7-posts-20261028T210818Z.log`) | — | discharged |
| fleet-alerting: `Each known failure class on a host reaches a person as an alert` (MODIFIED) | tasks.md 5.5; two-database leg and its fleet-only mutant (`5.5-check-…`) | — | discharged |
| fleet-alerting: `An unreachable telemetry store or a silent host freezes alerts` (MODIFIED) | tasks.md 5.1; `devloopFailureLeg` and per-database freeze legs, `noStoreFreeze` rejected (`5.4-fixtures-20261022T025357Z.log`, `review-c-F6-fixture-20261022T042517Z.log`) | — | discharged; at runtime the 2026-10-25 failures ended the run before any freeze was evaluated (§12.3) |
| fleet-alerting-interface: `The pull-request queue-wait rule reads devloop through SQL` | tasks.md 5.1, 5.2, 5.6; rendered rule (`5.4-magnetite-config-20261022T030208Z.log`); one SQL query on `devloop` per run (`7.6-evaluator-20261022T035309Z.log`) | — | discharged |
| fleet-alerting-interface: `The evaluator queries each rule's database as the regulators' store account` (MODIFIED, RENAMED) | tasks.md 4.4, 5.3, 5.4, 5.5, 7.6; fixture refusals 404/400/401 (`5.3-refusals-…`, `5.5-check-…`); R8.2 admits `devloop-reconcile` and `fleet-alert` only (`4.4-assertion-mutants-…`); 15 PromQL on `fleet` and 1 SQL on `devloop` per run as `regulator`, `queriesPerRun` 16 (`7.6-evaluator-…`) | — | discharged |
| fleet-alerting-interface: `Alert rules are rendered from one Nix source to the evaluator and to promtool` (MODIFIED) | tasks.md 5.2; `SUCCESS: 7 rules found` and `malformedExpression` rejected (`5.2-rules-20261022T024654Z.log`) | — | discharged |
| fleet-alerting-interface: `Store errors and silent hosts freeze instance state` (MODIFIED) | tasks.md 5.1, 5.4, 10.5; per-database legs and `allDatabasesFreeze` rejected at fixture level (`review-c-F6-fixture-…`); property part green (`review-c-checks-…`) | — | discharged |
| fleet-alerting-interface: `Alerts are posted to fleet-alerts with a title and a severity priority` (MODIFIED) | tasks.md 5.4; `[FIRING] StoreQueryFailing <database>` titles in the fixture legs (`5.4-fixtures-…`); runtime `[FIRING] PullRequestQueueWaitBurn` posts (`7.7-posts-…`) | — | discharged |
| fleet-alerting-interface: `This capability states its own trust boundary` (MODIFIED) | tasks.md 8.1; the requirement's own statement in its scenarios; no regulator applies | — | discharged by statement |
| host-metrics-collection: `magnetite contributes its own signals to the telemetry store` (MODIFIED) | tasks.md 3.6, 7.4; R3.1 logs-pipeline clauses (`3.6-r31-…`); `fleet` holds no log table (`7.4-fleet-logs-20261022T010949Z.log`) | — | discharged |
| telemetry-store-interface: `Ingest is OTLP over HTTP with a database header` (MODIFIED) | tasks.md 3.5, 3.6; R3.1 mutants (`3.6-r31-…`); per-table exporters to `/v1/otlp/v1/logs` (`7.4-exporters-…`) | — | discharged |
| telemetry-store-interface: `Databases and their retention are set at the telemetry store` (MODIFIED) | tasks.md 2.3, 2.4, 7.3; schema-job script probe (`2.3-script-probe-20261022T002058Z.log`); `devloop` TTL, no table TTL (`7.3-tables-…`); `greptimedb-envelope` passed after D2 (`7.3-envelope-20261022T010132Z.log`) | — | discharged |
| telemetry-store-interface: `Credentials exist only as activation-resolved files owned by non-worker users` (MODIFIED) | tasks.md 4.4; `fourthRegulatorHolder` rejected (`4.4-assertion-mutants-…`) | — | discharged |
| telemetry-store-interface: `Failure notices are posted to one topic` (MODIFIED) | tasks.md 3.1, 4.5, 7.5; R3.1 drops-`devloop-reconcile` mutant (`4.5-r31-20261022T011947Z.log`); forced failure and resolve delivered (`7.5-forced-fail-…`, `7.5-forced-resolve-…`) | — | discharged; two notices were not delivered on 2026-10-25 while magnetite was redeployed (§12.3) |
| telemetry-store-interface: `The collector's queue persists across a telemetry store restart` (MODIFIED) | tasks.md 3.5, 3.6; `logsQueueNotPersistent` rejected (`3.6-r31-…`) | — | discharged |
| world-assumptions: `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times` | world assumption; magnetite's dump equals the lexically applied migrations (`2.6-schema-diff-…`), tasks.md 1.2, 2.6 | — | assumption, holding |
| world-assumptions: `A44 — gitea-mq announces each batch transition in one of five exact journal messages` | world assumption; five messages, per-`msg` counts equal (`7.4-batch-lines-20261022T015905Z.log`), tasks.md 7.4 | — | assumption, holding |
| world-assumptions: `A45 — PostgreSQL on magnetite admits a local role named after the connecting system user without a password` | world assumption; both roles connect by peer without a password (`7.4-pg-grants-…`), tasks.md 7.4 | — | assumption, holding |
| world-assumptions: `A46 — GreptimeDB 1.2.1 keeps one row per key and time in a pre-created non-append table` | world assumption; `count(*)` equals distinct keys after the overlap re-reads and the cursor reset (`7.4-keys-…`, `7.4-cursor-reset-…`), tasks.md 3.9, 7.4 | — | assumption, holding |
| world-assumptions: `A47 — The collector's sqlquery receiver resumes logs queries from the last row's tracking value` | world assumption; a collector restart re-read only the overlap, 4 records per query (`7.4-restart-…`), tasks.md 3.9, 7.4 | — | assumption, holding |
| world-assumptions: `A48 — magnetite's journal keeps gitea-mq's lines for longer than the reconcile's window` | world assumption; the oldest `gitea-mq.service` entry was 34 and 32 days old, no `SystemMaxUse` or `MaxRetentionSec` (`7.5-journal-retention-…`), tasks.md 7.5 | — | assumption, holding |
| world-assumptions: `A49 — NixOS and nix-darwin run activation snippets before the current system is relinked` | world assumption; D1's line names the replaced closure (`7.1-deploy-record-…`), tasks.md 3.9, 7.1 | — | assumption, holding |
| world-assumptions: `Grounded vocabulary for behavioral requirements` (MODIFIED) | tasks.md 8.1; the designation table in the delta | — | discharged, with the unresolved nouns of 8a |

No ADDED or MODIFIED requirement is undischarged.

### 8c. Alphabet check

`A gap in the dev-loop history reaches a person within a day` says "the previous UTC day", naming the clock the reconcile uses; recorded, not counted, because the world phenomenon is a calendar day.
`Every dev-loop event is recorded once and kept for a year` says "365 days", the `devloop` database's TTL phrased as a world quantity; recorded, not counted.
No interface requirement references world state the machine cannot observe: `This capability states its own trust boundary` in `devloop-collection-interface` states what the selection, parsing, keying, peer reading and daily comparison establish, and forbids reading them as an end-to-end guarantee that a dev-loop event reaches the store.

---

## 9. Deployment record

Sections 9 and 10 are the evidence ledger that `tasks.md` 7.1–7.7 and 9.1 require this file to hold.
`[operator]` marks an observation only the operator could make; every other entry gives the command and its output.
Times are from `logs/s2-evidence/window.env`, written by `s2-deploy.sh`, which deployed only magnetite, each time from a fresh worktree of `origin/main` after `nixbot-logs queue` printed `Queue is empty` (all seven `queue-<label>-*.log`).

| Deploy | Pull request | `origin/main` commit | Start (UTC) | End (UTC) | `clan` exit | Gate passed after it |
|---|---|---|---|---|---|---|
| D1 | #3557 | `ea7cbf60c` | 2026-10-22T00:19:03Z | 00:21:23Z | 0 | 7.1 |
| D2 | #3558 | `e94a1631e` | 2026-10-22T00:40:11Z | 00:41:09Z | 0 | 7.3 |
| D3 | #3559 | `4174473d5` | 2026-10-22T01:07:44Z | 01:08:46Z | 0 | 7.4, first part |
| D3B | #3560 | `3d2baf0ed` | 2026-10-22T01:55:45Z | 01:56:40Z | 0 | 7.4 (`ingest: PASS`) |
| D4 | #3561 | `70848c4f9` | 2026-10-22T02:30:59Z | 02:31:52Z | 0 | 7.5, all but the first scheduled run |
| D5 | #3562 | `a1b2aac08` | 2026-10-22T03:43:50Z | 03:44:43Z | 0 | 7.6 |
| REVC | #3564 | `a106c086f` | 2026-10-22T05:10:39Z | 05:11:35Z | 0 | tasks.md 10.2, 10.6 on magnetite |

Each `clan exit=0` line is in `d1-deploy-…` to `d5-deploy-…`, `d3b-deploy-…` and `revc-deploy-…`; the `clan machines update` output is in `magnetite-<label>-*.log`.
D3B and REVC were not in the plan: D3B deployed the `--boot=all` journal fix found by 7.4 (§12.1), and REVC deployed the review follow-ups of #3564 (§11).
#3563 (Task 6) changed documentation only and was not deployed.
`T_FORCED_FAIL=2026-10-22T02:32:27Z`, `T_FORCED_RESOLVE=2026-10-22T02:33:01Z`, `T_BOOT=2026-10-23T23:05:38Z`.

Before pasting, `rg -n 'tk_[-_A-Za-z0-9]{29}' logs/s2-evidence` was run and matched nothing; every store password reaches a command through a netrc or credentials file in `gsql.sh` and the units, never as an argument.

### 9.1 Evaluation cost of each new or changed check

The budget is 0.5 GiB, 536,870,912 bytes of `gc.totalBytes`; every figure below uses the leading-dot method of tasks.md line 6, `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`.

| Check | Revision | `gc.totalBytes` | GiB | cpuTime (s) | drvPath | Log |
|---|---|---|---|---|---|---|
| `devloop-queries` (new) | Task 2 working copy | 142,573,344 | 0.133 | 0.39 | `/nix/store/hnc2a9i7fygbdv3k8gnsjgvdjhdsy00x-devloop-queries.drv` | `2.6-devloop-queries-cost-20261022T002832Z.log` |
| `devloop-queries` | Task 4 working copy | 143,284,368 | 0.133 | 0.40 | `/nix/store/wwbypjd938vd5bzpxhzfrc1cf6xbrcc4-devloop-queries.drv` | `4.1-devloop-queries-cost-20261022T010501Z.log` |
| `devloop-queries` | #3564 before / after | 143,284,592 / 143,121,472 | 0.133 | 0.38 / 0.40 | `…/9dkmlsvcy43vircsn0lk7lp7kqv6mvvb-devloop-queries.drv` (after) | `review-c-cost-before-20261022T041928Z.log`, `review-c-cost-after-20261022T042525Z.log` |
| `devloop-queries` | `origin/main` `697a6f1ea` | 135,629,648 | 0.126 | 0.41 | `/nix/store/faz1qmslp1394bbgm6w8nn190akdsvg5-devloop-queries.drv` | `8.1-eval-cost-20261028T211215Z.log` |
| `otel-collector-config` (extended) | Task 3 working copy | 489,223,840 | 0.456 | 1.63 | not recorded | `3.6-r31-cost-20261022T004357Z.log` |
| `otel-collector-config` | Task 4 working copy | 491,445,792 | 0.458 | 1.62 | `/nix/store/s5fpvqb2pdx1qavihfm60zk7hmx9v6zj-otel-collector-config.drv` | `4.5-r31-cost-20261022T012150Z.log` |
| `otel-collector-config` | `origin/main` `697a6f1ea` | 488,431,056 | 0.455 | 1.65 | `/nix/store/vyzijzbrsjv9b6zk70wsjkh9fqr6hxzx-otel-collector-config.drv` | `8.1-eval-cost-20261028T211215Z.log` |
| `fleet-alert` (extended) | before Task 5 / after Task 5 | 328,275,344 / 333,046,656 | 0.306 / 0.310 | 1.05 / 0.91 | `…/96s5ajxc4vr09i6w4nwlms58cdhkdd71-fleet-alert.drv` (after) | `5.5-eval-cost-before-20261022T022800Z.log`, `5.5-eval-cost-after-20261022T030316Z.log` |
| `fleet-alert` | #3564 after | 333,040,480 | 0.310 | 0.98 | `/nix/store/6lg2bp6mp3jl6sgw9f4f7f26zsvas39m-fleet-alert.drv` | `review-c-cost-after-…` |
| `fleet-alert` | `origin/main` `697a6f1ea` | 339,763,552 | 0.316 | 1.01 | `/nix/store/sdxd7kz1riaxrc4mxydc546p74qymvz2-fleet-alert.drv` | `8.1-eval-cost-20261028T211215Z.log` |
| `greptimedb-envelope` (unchanged by S2) | #3564 after | 405,618,800 | 0.378 | 1.07 | `/nix/store/fysddi6610q8ldz0m3dqc1qqm3lrz7sj-greptimedb-envelope.drv` | `review-c-cost-after-…` |
| `nixos-magnetite` (machine check carrying the obligation) | before / after Task 1 | 2,809,897,568 / 2,810,108,864 (Δ 211,296) | 2.62 | 11.7 / 11.3 | — | `1.5-nixos-magnetite-cost-20261022T001210Z.log` |
| `nixos-magnetite` | `origin/main` `697a6f1ea` | 2,856,206,336 | 2.66 | 11.46 | `/nix/store/cc9v3x29badp6a1vy1hr0vb25kzihj12-nixos-system-magnetite-26.11.20261023.3a32588.drv` | `8.1-eval-cost-20261028T211215Z.log` |

Every S2 check is under budget at `origin/main`; `otel-collector-config` is the closest, at 0.455 GiB, as it was after Task 3.
The machine check is above 0.5 GiB by its nature, as design D12 states (2.61 GiB before S2); S2's obligation added 211,296 bytes to it, and the further 46 MB by 2026-10-28 came after S2, with `origin/main` now on nixpkgs `3a32588` [INFERENCE: not bisected].

```text
$ plan/task-8.md Step 7, at origin/main (8.1-eval-cost-20261028T211215Z.log)
origin/main: 697a6f1ea Update flake inputs: llm-agents.nix
/nix/store/faz1qmslp1394bbgm6w8nn190akdsvg5-devloop-queries.drv
devloop-queries gc.totalBytes=135629648 cpuTime=0.4090920090675354 under 0.5 GiB: true
/nix/store/vyzijzbrsjv9b6zk70wsjkh9fqr6hxzx-otel-collector-config.drv
otel-collector-config gc.totalBytes=488431056 cpuTime=1.6465480327606201 under 0.5 GiB: true
/nix/store/sdxd7kz1riaxrc4mxydc546p74qymvz2-fleet-alert.drv
fleet-alert gc.totalBytes=339763552 cpuTime=1.009788990020752 under 0.5 GiB: true
/nix/store/cc9v3x29badp6a1vy1hr0vb25kzihj12-nixos-system-magnetite-26.11.20261023.3a32588.drv
nixos-magnetite gc.totalBytes=2856206336 cpuTime=11.458525657653809 under 0.5 GiB: false
method: NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/s2cost-<c>.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<c>.drvPath, at the origin/main above
```

### 9.2 Planning-time evidence and the schema baseline (tasks.md 1.1, 1.2, 2.6)

The plan review of tasks.md 1.1 (`1.1-plan-review-20261021T232002Z.md`) found 0 critical, 1 high, 9 medium and 12 low findings; the operator accepted all 22, and they were applied in #3556 and #3557 (`d1500350b`).
Among them, F1 (count only each build's first attempt), F5 (the pre-D2 compile check, tasks.md 2.7), F7 (per-database freeze), F9 (the obligation scoped to five checks), F17 (1.2 reduced to a read-only dump) and F18 (7.2 made opportunistic) shaped what §9.3–§9.9 record.

```text
$ sha256 of magnetite's normalised schema dump and of the lexically applied migrations' dump
6c437de367871ef2f0c20642e03c8a154c4f896745936ec066b8e3542b9f71cb  logs/s2-evidence/1.2-schema-magnetite.norm.sql
6c437de367871ef2f0c20642e03c8a154c4f896745936ec066b8e3542b9f71cb  logs/s2-evidence/2.6-schema-check.norm.sql
schema equals magnetite's
```

The diff was empty, so `devloop-queries` applies nixbot's migrations lexically with `--single-transaction` and has no migrator fallback (`2.6-schema-diff-20261022T002833Z.log`); `pg_dump` reported PostgreSQL 16.15 and `schema_migrations` held 37 versions (`1.2-schema-magnetite-20261021T231946Z.log`).

### 9.3 D1 and the deploy record (tasks.md 1.7, 7.1)

`7.1-deploy-record-20261022T002142Z.log`:

```text
PRE_D1_SYSTEM=/nix/store/nr271s90m7sijqmbf6wfxn2ikqjjikif-nixos-system-magnetite-26.11.20261007.ac1faec PRE_D1_LINES=0 D1_START=2026-10-22T00:19:03Z D1_END=2026-10-22T00:21:23Z
stat 644 root root
lines 1
current /nix/store/kq52fjpvc4marssw1lw6hg8rzgjzfcyw-nixos-system-magnetite-26.11.20261007.ac1faec
last {"host":"magnetite","closure":"/nix/store/kq52fjpvc4marssw1lw6hg8rzgjzfcyw-nixos-system-magnetite-26.11.20261007.ac1faec","previous_closure":"/nix/store/nr271s90m7sijqmbf6wfxn2ikqjjikif-nixos-system-magnetite-26.11.20261007.ac1faec","ts":"2026-10-22T00:21:08Z"}
parsed: host=magnetite closure=/nix/store/kq52fjpvc4marssw1lw6hg8rzgjzfcyw-nixos-system-magnetite-26.11.20261007.ac1faec previous_closure=/nix/store/nr271s90m7sijqmbf6wfxn2ikqjjikif-nixos-system-magnetite-26.11.20261007.ac1faec ts=2026-10-22T00:21:08Z
deploy record: PASS
```

`queue-D1-20261022T001903Z.log`: `Queue is empty on https://nixbot.scientistexperience.net.`; the D1 log ends `[magnetite] the following new units were started: niks3-gc.service` and `clan exit=0`.

### 9.4 The boot record, opportunistic (tasks.md 7.2)

magnetite rebooted naturally on 2026-10-23 at 23:05:38 UTC, after REVC; `7.2-boot-record-20261028T210758Z.log`:

```text
D1_END=2026-10-22T00:21:23Z
source-of-boot: /proc/stat btime (coreutils uptime has no -s)
boot 2026-10-23T23:05:38Z
booted /nix/store/b6wxsch1hv7id78qyf7ky39yn0rcczb9-nixos-system-magnetite-26.11.20261007.ac1faec
current /nix/store/6hnpc7wd2w38wvsyhnhrppgrjcjcs860-nixos-system-magnetite-26.11.20261023.3a32588
boots 5
first-after-boot {"host":"magnetite","closure":"/nix/store/b6wxsch1hv7id78qyf7ky39yn0rcczb9-nixos-system-magnetite-26.11.20261007.ac1faec","ts":"2026-10-23T23:05:45Z"}
no-previous-after-boot 1
T_BOOT=2026-10-23T23:05:38Z
boot record: PASS
```

The booted closure is REVC's (`review-c-deployed-20261022T051146Z.log`); the later `current` closure is a nixpkgs `20261023.3a32588` system, deployed after the reboot.
Two earlier runs of the same day are kept with `-superseded-` in their names: one called `uptime -s`, which magnetite's coreutils lacks, and one misparsed the boot list.

### 9.5 D2 and the devloop tables (tasks.md 2.7, 2.9, 7.3)

The pre-D2 compile check on a throwaway GreptimeDB 1.2.1 passed (`2.7-precheck-supplement-20261022T003115Z.log`, ending `ok: the collector wrote 11 log lines`, `ok: the collector logged no failed export`, `precheck passed`); its first run, `2.7-precheck-20261022T003015Z.log`, read an empty user journal, and the plan was fixed to read the collector's log file in #3558 (§12.2).

`7.3-tables-20261022T004207Z.log`, abridged to one table and the closing lines:

```text
$ SHOW CREATE TABLE ci_build
CREATE TABLE IF NOT EXISTS "ci_build" (
  "build_id" BIGINT NULL,
  "created_at" TIMESTAMP(6) NULL,
  "started_at" TIMESTAMP(6) NULL,
  "finished_at" TIMESTAMP(6) NOT NULL,
  "eval_duration_ms" BIGINT NULL,
  "status" STRING NULL,
  "pr_number" BIGINT NULL,
  "branch" STRING NULL,
  TIME INDEX ("finished_at"),
  PRIMARY KEY ("build_id")
)
ENGINE=mito
WITH(
  append_mode = 'false',
  sst_format = 'flat',
  ttl = '11months 30days 3h 50m 24s'
)
ci_build rows=0
$ information_schema.tables create_options for devloop
["batch_event","append_mode=false sst_format=flat"]
["ci_attribute","append_mode=false sst_format=flat"]
["ci_build","sst_format=flat append_mode=false"]
["deploy_record","append_mode=false sst_format=flat"]
$ SHOW CREATE DATABASE devloop
["devloop","CREATE DATABASE IF NOT EXISTS devloop\nWITH(\n  ttl = '11months 30days 3h 50m 24s'\n)"]
$ pipelines
["devloop_batch_event"]
["devloop_ci_attribute"]
["devloop_ci_build"]
["devloop_deploy_record"]
devloop tables: PASS
```

The next scheduled `greptimedb-envelope` run after D2 passed at 01:01:26 UTC (`7.3-envelope-20261022T010132Z.log`: `greptimedb-envelope: all checks passed`).

### 9.6 D3, D3B and ingest (tasks.md 3.11, 7.4)

`7.4-gate-20261022T015914Z.log`, after D3B and the receiver cursor reset:

```text
found: backfill: PASS
found: exporters: PASS
found: grants: PASS
found: pg-grants: recorded
found: batch lines: PASS
found: keys: PASS
found: explain: recorded
found: tie: PASS
found: budget: recorded
found: restart: PASS
found: fleet logs: PASS
ingest: PASS
7.4 passed: D4 may start
```

Decisive lines of the parts:

```text
(7.4-backfill) poll 1 2026-10-22T01:09:16Z ci_attribute keys=10000 nixbot finished attributes=202041 ci_build keys=1837 nixbot finished builds=1837
(7.4-backfill) ci_attribute reached nixbot's count at poll 19
(7.4-exporters) otlp_http/devloop_batch_event sent=282 send_failed=0; ci_attribute sent=202061 send_failed=0; ci_build sent=1857 send_failed=0; deploy_record sent=3 send_failed=0
(7.4-keys) ci_attribute [202041,202041]; ci_build [1837,1837]; batch_event [282,282]; deploy_record [3,3]
(7.4-tie) widest build_attributes tie 106 rows
(7.4-restart) accepted since restart: sqlquery/ci_attribute=4 sqlquery/ci_build=4 journald/gitea-mq=0 file_log/deploy-record=0
(7.4-fleet-logs) no opentelemetry_logs, ci_attribute, ci_build, batch_event or deploy_record table in fleet (header only); fleet holds 403 tables; fleet logs: PASS
(7.4-budget) D3 day 2026-10-22 sent=204203 stored=204163 against ADR-004's 100000 rows a day; exceedance: the backfill of nixbot's retained history, accepted once on the deploy day (design Risks)
(7.4-cursor-reset, after D3B) batch bisecting 9, batch built 218, batch done 181, batch formed 181, batch landed 187 in both the journal (every boot) and batch_event; [776,776]; cursor reset: PASS
(7.4-explain) ci_attribute: Index Scan using build_attributes_build_finished_idx, Execution Time: 8.974 ms; ci_build: Seq Scan on builds, Execution Time: 3.267 ms
```

The first `batch lines` run after D3 found 282 of 772 retained lines (`7.4-batch-lines-20261022T012950Z.log`); §12.1 records the cause and fix.

### 9.7 D4 and devloop-reconcile (tasks.md 4.8, 7.5)

```text
(7.5-hand-start-20261022T023211Z.log) devloop-reconcile: C1 attributes: ok … C7 current-system: ok; 11.5M memory peak; MemoryMax=134217728
(7.5-forced-fail-20261022T023227Z.log) T_FORCED_FAIL=2026-10-22T02:32:27Z
greptimedb-sql: HTTP 400: 4001 Failed to plan SQL: Table not found: greptime.devloop_absent.ci_attribute
devloop-reconcile.service: Main process exited, code=exited, status=2/INVALIDARGUMENT
$ tail -1 failed.log
1792636350 devloop-reconcile.service magnetite
{"time":"2026-10-22T02:32:30Z","title":null,"priority":null,"message":"FAILED devloop-reconcile.service on magnetite"}
(7.5-forced-resolve-20261022T023301Z.log) T_FORCED_RESOLVE=2026-10-22T02:33:01Z
{"id":"7imVb4pebm8f","time":1792636384,…,"topic":"fleet-alerts","message":"RESOLVED devloop-reconcile.service on magnetite"}
(7.5-scheduled-20261024T143937Z.log) first scheduled run day: 2026-10-23; C1–C7 ok; 18.6M memory peak (2026-10-23), 17.9M (2026-10-24)
(7.5-journal-retention) oldest gitea-mq.service entry: 2026-09-17T21:55:28Z, age 34 days (2026-10-22); 2026-09-22T07:56:42Z, age 32 days (2026-10-24); no SystemMaxUse or MaxRetentionSec set
7.5 passed: D5 may start
```

The highest peak recorded is 20M, the run after REVC at 05:11 UTC, against the 128M ceiling.

### 9.8 D5 and the burn rule (tasks.md 5.8, 7.6)

`7.6-evaluator-20261022T035309Z.log`:

```text
{"user":"regulator","storeUrl":"http://127.0.0.1:4000","topLevelDatabase":false,"rules":10,"byDatabase":[{"database":null,"languages":[null],"n":1},{"database":"devloop","languages":["sql"],"n":1},{"database":"fleet","languages":["promql"],"n":8}],"queriesPerRun":16,"promqlPerRun":15,"sqlPerRun":1}
{"alert":"PullRequestQueueWaitBurn","database":"devloop","language":"sql","for":3600,"severity":"warning","presence":[]}
no StoreQueryFailing post
greptime_servers_http_requests_total{code="200",db="devloop",method="POST",path="/v1/sql"} 1.000000
greptime_servers_http_requests_total{code="200",db="fleet",method="GET",path="/v1/prometheus/api/v1/query"} 15.000000
run wall time 1.726 s   (windows 2 and 3: 1.761 s, 1.708 s)
LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password
```

The store-side elapsed time of one run's queries was 0.03 s for the one SQL query and 0.51–0.57 s for the 15 PromQL queries.
`7.6-burn-history-20261022T034631Z.log`, seven days before D5:

```text
2026-10-15T00:00:00Z holds value=0.2558139534883721
2026-10-16T00:00:00Z silent
2026-10-17T00:00:00Z silent
2026-10-18T00:00:00Z holds value=0.20833333333333334
2026-10-19T00:00:00Z silent
2026-10-20T00:00:00Z silent
2026-10-21T00:00:00Z silent
design D1 expects rows for the days 2026-10-10, -14, -17, -21 (windows ending 2026-10-11, -15, -18, -22) and silence on the others (logs/s2/grounding.md §1.6)
burn rule history: recorded
```

Over D1's fourteen windows the rule held at 2026-10-08, -11, -15, -18 and -22, D1's four expected windows plus 2026-10-08.
D5 ran before 7.5's first scheduled reconcile run, by the orchestrator's decision (`5.8-verify-20261022T035642Z.log`; §12.2).

### 9.9 CAM-69 acceptance (tasks.md 7.7)

The operator shortened 7.7's window on 2026-10-28 from at least seven days after D3 to the six scheduled reconcile runs after D4 (§12.2).

```text
(7.7-reconcile-20261028T210531Z.log)
operator decision 2026-10-28: window is D4_END through now, shorter than the plan's seven days; the age>=7 and runs>=7 thresholds are recorded, not gated
2026-10-23 02:15 run: ok=7 fail=0
2026-10-24 02:15 run: ok=7 fail=0
2026-10-25 02:15 run: ok=7 fail=0
2026-10-26 02:15 run: ok=7 fail=0
2026-10-27 02:15 run: ok=7 fail=0
2026-10-28 02:15 run: ok=7 fail=0
scheduled runs checked: 6; FAILED posts outside the forced failure: 0
reconcile: PASS
(7.7-questions-20261028T210554Z.log, main=697a6f1ea)
formationToLand rows=22   (batches 181–202; 10.0–14.7 s except 191: 657.1 s, 193: 250.9 s, 195: 254.8 s)
queueWait ["p50_s","p90_s","p99_s","builds"] [222.7473515,3939.0369473,4859.368513665484,82]
buildOutcome rows=103
questions: PASS
(7.7-join-20261028T210618Z.log)
{"host":"magnetite","closure":"/nix/store/kxzj76f2ryzqmyzprkrmkxrarnacddx5-nixos-system-magnetite-26.11.20261007.ac1faec","previous_closure":"/nix/store/m56z3m631d7djpf0hr70wkivwffcid1d-nixos-system-magnetite-26.11.20261007.ac1faec","ts":"2026-10-22T03:44:29Z"}
D5 lines: 1
[1840,"a1b2aac08cd679691afbea93bd9db3ef6e27bed3","main",null,"succeeded",false]
join: PASS
journal 24 h: {"PullRequestQueueWaitBurn":1}
state.json 24 h: {"PullRequestQueueWaitBurn":1}
acceptance: PASS
```

Posts to `fleet-alerts` since `D5_END`, from the evaluator's journal (`7.7-posts-20261028T210818Z.log`) and, for the notifier's own posts, the journal of `observability-notify@*` (`9.1-closed-record-20261028T211541Z.log`):

| Time (UTC) | Title or message | Source |
|---|---|---|
| 2026-10-24T00:32:02Z | `[FIRING] PullRequestQueueWaitBurn` | evaluator |
| 2026-10-24T23:45:02Z | `[RESOLVED] PullRequestQueueWaitBurn` | evaluator |
| 2026-10-25T16:09:07Z | `FAILED fleet-alert.service on magnetite` (ntfy id `PwhTyb70nKNA`) | notifier |
| 2026-10-25T16:10:02Z | `RESOLVED fleet-alert.service on magnetite` | the evaluator's resolve hook |
| 2026-10-26T13:00:02Z | `[FIRING] WeeklyPipelineTest` | evaluator |
| 2026-10-28T00:35:02Z | `[FIRING] PullRequestQueueWaitBurn` (open at 21:08 UTC) | evaluator |

That is six posts; `7.7-posts-…` lists five, because it read only the evaluator's journal, and the 16:09:07 `FAILED` came from the notifier's unit.
`StoreQueryFailing` was posted 0 times and `PullRequestQueueWaitBurn` fired twice and resolved once; each firing followed a burst of six flake-updater pull requests (#3583–#3588 opened 2026-10-23 22:14:46–22:15:46Z; #3622–#3627 opened 2026-10-27 22:12:35–22:14:02Z), the cause tasks.md 10.10 names.
The `failed.log` holds one line since `D5_END`, `1792944547 fleet-alert.service magnetite`.

## 10. Integration verification (tasks.md 9.1) and the sync order (tasks.md 8.3)

Pull request 5 (#3562) merged on 2026-10-22, before plan/task-8.md Step 2's arrival watch was started, so its arrival time cannot be measured after the fact: `devloop` keeps no ingestion time, and the collector's cursor holds only its latest value.
At the orchestrator's direction (2026-10-28), §10.1 measures arrival on the nixbot builds that finished during a 30 s watch started that evening, and §10.2 uses the most recently landed batch, 202, which merged #3603; §10.3 keeps D5 and pull request 5 as the plan names them.

### 10.1 A pull-request build and its attributes reach devloop within 10 minutes

The proxy is plan/task-8.md Step 2's own measure, run on the builds that finished during the watch: every 30 s, `9.1-arrival-watch.sh` read nixbot's `finished_at` and finished-attribute count as `postgres` and the `ci_build` and `ci_attribute` row counts for the same `build_id` from `devloop` as `regulator`, so each arrival time is known to within one sample (about 36 s with the query time).
Its limits: the three builds are pull-request builds of #3513, #3628 and #3565, not of pull request 5; the sample time is stibnite's clock and `finished_at` magnetite's, so a negative first sight means the build finished during that sample; and no batch formed during the watch, so a batch line's arrival was not timed (batch 202's lines were in `devloop` by the next day's reconcile, §10.2).
`9.1-arrival-watch.log` (2026-10-28T21:16:29Z to 21:28:33Z) and its summary in `9.1-closed-record-20261028T211541Z.log`:

```text
columns: <stibnite now> <build_id> <nixbot finished_at> <nixbot finished attrs> <ci_build rows> <ci_attribute rows>
1793222189 1964 1793222188 255 0 252
1793222260 1964 1793222188 255 1 255
1793222403 1965 1793222385 255 0 250
1793222439 1965 1793222385 255 1 255
1793222626 1966 1793222628 255 0 250
1793222661 1966 1793222628 255 1 255
build 1964 (PR 3513) finished_at=2026-10-28T21:16:28Z attrs=255 first watched +1s ci_build +72s ci_attribute complete +72s
build 1965 (PR 3628) finished_at=2026-10-28T21:19:45Z attrs=255 first watched +18s ci_build +54s ci_attribute complete +54s
build 1966 (PR 3565) finished_at=2026-10-28T21:23:48Z attrs=255 first watched -2s ci_build +33s ci_attribute complete +33s
PASS: 9.1 arrival within 10 minutes (substitute builds)
```

Each build's `ci_build` row and all 255 of its attributes were in `devloop` within 72 s of nixbot's `finished_at`, against the 10-minute bound; most attributes were there before the build finished, because each attribute is read once it finishes.

### 10.2 Its merge-queue batch and formation-to-land

Batch 202 is the most recent batch with a `batch done` row on 2026-10-28; it landed #3603 (`58f63733c`, merged 2026-10-27T21:24:51Z).
`9.1-closed-record-20261028T211541Z.log`:

```text
PR 3603 MERGED 2026-10-27T21:24:51Z 58f63733c4ca425c5d9372bef89d1250aa0e656e
["batch","msg","build","sha","members","landed","ejected","builds","flaky","ts"]
[202,"batch formed",null,null,1,null,null,null,null,1793136281844082]
[202,"batch built",1,"58f63733c4ca425c5d9372bef89d1250aa0e656e",null,null,null,null,null,1793136283138017]
[202,"batch landed",null,"58f63733c4ca425c5d9372bef89d1250aa0e656e",null,null,null,null,null,1793136290051639]
[202,"batch done",null,null,null,1,0,1,false,1793136292325311]
$ formationToLand (rendered at origin/main 697a6f1ea), row of batch 202
["batch","formation_to_land_s"]
[202,10.481229]
## nixbot build 1931 of #3603's commit 58f63733c and its devloop rows
1931|main|3603|2026-10-27 21:23:45.038865+00|succeeded|255
[1931,"succeeded","main",1793136225038865]
["count(*)"]
[255]
```

The batch has exactly one `batch formed` and one `batch done`, the latter with `landed` 1, and its formation-to-land is 10.48 s (21:24:41Z to 21:24:52Z).
nixbot's build 1931 of the landed commit, finished 2026-10-27T21:23:45Z with 255 finished attributes, has one `ci_build` row and 255 `ci_attribute` rows in `devloop`.
The scheduled reconcile of 2026-10-28 02:15 UTC compared the day 2026-10-27, including these rows and batch 202's journal lines, and passed (§10.4).

### 10.3 D5's deploy record joined to the commit it deployed

```text
["magnetite","/nix/store/kxzj76f2ryzqmyzprkrmkxrarnacddx5-nixos-system-magnetite-26.11.20261007.ac1faec","/nix/store/m56z3m631d7djpf0hr70wkivwffcid1d-nixos-system-magnetite-26.11.20261007.ac1faec",1792640669]
D5 deploy-record rows: 1
["commit_sha","branch","build_id"]
["a1b2aac08cd679691afbea93bd9db3ef6e27bed3","main",1840]
D5_COMMIT a1b2aac08cd679691afbea93bd9db3ef6e27bed3 joins the D5 closure
#3562 merge commit a1b2aac08cd679691afbea93bd9db3ef6e27bed3
PullRequestQueueWaitBurn occurrences in rules.nix at D5_COMMIT: 2
```

`D5_COMMIT` is pull request 5's own merge commit, so the `main` D5 deployed contains it.
The plan's `git log -S PullRequestQueueWaitBurn … -- modules/nixos/fleet-alert/rules.nix` printed nothing in this run, so the containment is shown from the merge commit itself.

### 10.4 Consecutive scheduled devloop-reconcile passes

```text
2026-10-22T02:32:13Z ok=7 fail=0 result=done     (7.5 hand start)
2026-10-22T02:32:30Z ok=0 fail=0 result=failed   (7.5 forced failure, T_FORCED_FAIL)
2026-10-22T02:33:03Z ok=7 fail=0 result=done     (7.5 resolve)
2026-10-22T05:11:50Z ok=7 fail=0 result=done     (after REVC, tasks.md 10.2)
2026-10-23T02:15:00Z ok=7 fail=0 result=done
2026-10-24T02:15:00Z ok=7 fail=0 result=done
2026-10-25T02:15:00Z ok=7 fail=0 result=done
2026-10-26T02:15:00Z ok=7 fail=0 result=done
2026-10-27T02:15:00Z ok=7 fail=0 result=done
2026-10-28T02:15:00Z ok=7 fail=0 result=done
scheduled runs since D4: 6; passing: 6
FAILED devloop-reconcile lines in failed.log since D4: 1
```

The one `failed.log` line is the forced failure at `T_FORCED_FAIL` (`1792636350`).
Six consecutive scheduled passes, not the plan's seven, by the operator's decision of 2026-10-28; the seventh scheduled run falls on 2026-10-29 02:15 UTC.

### 10.5 The burn rule evaluated every minute on devloop, with no StoreQueryFailing since D5

```text
{"alert":"PullRequestQueueWaitBurn","database":"devloop","language":"sql","for":3600}
{"topLevelDatabase":false}
$ completed fleet-alert.service runs since D5_END (job-completion entries: JOB_TYPE=start with a JOB_RESULT)
runs=9692 done=9690 first=+18s maxgap=112s minutes=9692
not done: 2026-10-25T14:38:00Z failed
not done: 2026-10-25T16:09:07Z failed
gap: 2026-10-23T23:04:09Z -> 2026-10-23T23:06:01Z 112s
store-failure lines since D5: 4
2026-10-25T14:38:00+00:00 magnetite fleet-alert[3571796]: fleet-alert: query failed: count by (host_name) (node_vmstat_oom_kill)
2026-10-25T14:38:00+00:00 magnetite fleet-alert[3571796]: fleet-alert: the store did not answer queries on fleet; its instances are frozen this run
2026-10-25T14:38:00+00:00 magnetite fleet-alert[3571796]: fleet-alert: query failed: SELECT CAST(sum(CASE WHEN … FROM ci_build c …
2026-10-25T14:38:00+00:00 magnetite fleet-alert[3571796]: fleet-alert: the store did not answer queries on devloop; its instances are frozen this run
StoreQueryFailing posts since D5: 0
```

The evaluator completed a run in each of the 9,692 minutes since `D5_END`, with one gap of 112 s across magnetite's reboot of 2026-10-23, and 9,690 of them succeeded.
The plan's count of `JOB_TYPE == "start"` entries counts each run twice, because systemd writes that field on both the job's start and its completion entry; the filter above keeps only completion entries.
The two failed runs and the four store-failure lines are the known limitation of §12.3; the plan's expectation `store-failure lines since D5: 0` is therefore not met, while its purpose, no `StoreQueryFailing` posted, holds.

### 10.6 Sync order against stand-up-gitea-mq-on-magnetite and stand-up-nixbot-on-magnetite

`8.3-sync-order-20261028T211232Z.log`:

```text
stand-up-gitea-mq-on-magnetite: not archived
stand-up-nixbot-on-magnetite: not archived
main rows: 143  S2 delta rows: 178
# main rows missing from the S2 delta (S2 must carry every one)
stand-up-gitea-mq-on-magnetite delta rows: 65
# main rows missing from the stand-up-gitea-mq-on-magnetite delta: 100
# term|sense pairs both S2 and stand-up-gitea-mq-on-magnetite add to main:
batch|—
merge queue|—
pull request|—
stand-up-nixbot-on-magnetite delta rows: 56
# main rows missing from the stand-up-nixbot-on-magnetite delta: 88
# term|sense pairs both S2 and stand-up-nixbot-on-magnetite add to main:
# other open changes whose deltas name a requirement S2 modifies or renames
openspec/changes/stand-up-gitea-mq-on-magnetite/specs/world-assumptions/spec.md:99:### Requirement: Grounded vocabulary for behavioral requirements
openspec/changes/stand-up-nixbot-on-magnetite/specs/world-assumptions/spec.md:48:### Requirement: Grounded vocabulary for behavioral requirements
# open changes with no specs/ directory
stand-up-linux-fleet-collection
```

The S2 delta carries every main row, so S2's own sync loses nothing.
The case is plan/task-8.md Step 4's first: both siblings are unarchived and each MODIFIES `Grounded vocabulary for behavioral requirements` from a copy that lacks main rows (100 and 88), so whichever syncs after S2 would delete those rows and S2's 35 new ones unless it first rebuilds its block on S2's synced main.
`stand-up-gitea-mq-on-magnetite` also adds `batch`, `merge queue` and `pull request` under the same term and sense as S2, with different text.
No other open change modifies or renames a requirement S2's deltas touch: the `world-assumptions` deltas of `capi-hetzner-cluster`, `filter-check-sources-for-substitution`, `k3s-nixos-vm-tests` and `path-scope-plugin-releases` only ADD assumptions, and no open change has a `fleet-alerting`, `fleet-alerting-interface`, `host-metrics-collection` or `telemetry-store-interface` delta; `stand-up-linux-fleet-collection` has no `specs/` yet.
Plan/task-8.md Step 4 required a stop here until the operator answered; the operator decided on 2026-10-28.
**Decision** (operator, 2026-10-28): S2 archives first.
S2's delta carries every main row: the orchestrator counted 136 `| <lowercase>` term rows in main's `Grounded vocabulary for behavioral requirements` table, all 136 present among the 171 of S2's delta, 35 new and 0 missing.
Each of `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite` must rebuild its `Grounded vocabulary` block from S2's synced main before its own archive, and `stand-up-gitea-mq-on-magnetite`'s wording of `batch`, `merge queue` and `pull request` is reconciled with S2's then.
S2 edits neither sibling's specs.

## 11. Review follow-ups (tasks.md section 10)

`review.md` records the holistic review of S2 as merged and deployed (2026-10-22): nothing critical, one significant finding (F1) and nine minor ones (F2–F10).

### 11.1 #3564: F2–F10 (tasks.md 10.1–10.9)

#3564 (`a106c086f`, merged 2026-10-22T05:10:38Z) applied F2–F10 and was deployed as REVC.

```text
(review-c-validate-20261022T043418Z.log) Change 'stand-up-devloop-collection' is valid; exit 0
(review-c-F3-red-devloop-ingest-20261022T042358Z.log) C1 attributes: FAIL unexplained in devloop.ci_attribute: 1 (first: 9203/checks.aarch64-linux.reconcile-dropped/…/absent)
(review-c-green-devloop-ingest-20261022T043329Z.log) ok: C1 attributes names the 3 keys missing from ci_attribute; ok: C2 builds names the 2 keys missing from ci_build
(review-c-checks-20261022T042415Z.log) mutant selectError rejected: FAIL: no ci_attribute cell holds any error text the fixtures stored; mutant noRepost rejected
(review-c-F6-fixture-20261022T042517Z.log) mutant allDatabasesFreeze rejected
(review-c-deployed-20261022T051146Z.log) devloop-reconcile OOMScoreAdjust=0; no OOMScoreAdjust in unit; ExecStart=/nix/store/9n6z9sdbb6ww40q80ps37w10zm3pspzr-devloop-reconcile/bin/devloop-reconcile
```

The reconcile run after REVC, at 05:11:50 UTC, passed C1–C7 (§10.4).
The evaluation costs before and after are in §9.1.

### 11.2 #3591: F1 (tasks.md 10.10)

The operator decided on 2026-10-24 (decision O3) to keep the per-input flake-updater pull requests and the burn rule unchanged, because `mic92/update-flake-inputs` cannot group inputs and one combined pull request would let any failing input hold back every other update.
#3591 (`03a95cf36`, merged 2026-10-24T15:13:08Z) recorded it as tasks.md 10.10, put the expected cause of a firing in the runbook, and ticked 6.4, 6.5 and 7.5.
Both firings since D5 came from flake-updater bursts, as F1 predicted (§9.9).

## 12. Deviations and known limitations

### 12.1 Defects found and fixed during deployment

- 7.4 after D3 found `batch_event` holding 282 of the 772 retained `gitea-mq.service` batch lines: the journald receiver always runs `journalctl --follow`, which systemd 261 limits to the current boot.
  #3560 set the receiver's `journalctl_path` to a wrapper adding `--boot=all`, with a `devloop-ingest` assertion, and was deployed as D3B before D4; the receiver's cursor was then reset (`7.4-cursor-reset-20261022T015702Z.log`) and the counts matched.
- The plan's 7.6 and 7.7 commands first used GNU `date` options on stibnite and an evaluator window that started 7 s early; their outputs are kept with `-superseded-` in their names, and the reruns are the logs cited here.

### 12.2 Deviations from the plan

- 7.7's window was shortened by operator decision on 2026-10-28: from at least seven days after D3 to the six scheduled reconcile runs after D4 (2026-10-23 to 10-28); §9.9 and §10.4 record six passes where the plan expected seven.
- D5 ran on 2026-10-22 before 7.5's first scheduled reconcile run, by the orchestrator's decision; that run passed on 2026-10-23 and 7.5 was ticked in #3591 (`5.8-verify-20261022T035642Z.log`, `7.5-scheduled-20261024T143937Z.log`).
- Two deploys outside the plan: D3B (#3560, §12.1) and REVC (#3564, §11.1).
- 9.1 was measured on a substitute build and batch, not on pull request 5, because the arrival watch was never started while #3562's builds finished (§10).
- Plan text fixed during implementation, each in the pull request named:
  - #3557 (`d1500350b`): the plan review's findings F14–F22 applied across `plan.md` and `plan/task-1.md`–`task-8.md`.
  - #3558 (`c6e9abe0e`): journal reads on magnetite need `sudo`, because the operator is not in `systemd-journal` (`plan/task-2.md`, `task-3.md`, `task-5.md`, `task-7.md`, `task-8.md`); the pre-D2 check reads the collector's log file instead of the user journal, and keeps its exit code in `rc` because `status` is read-only in zsh.
  - #3559 (`4174473d5`): `plan/task-3.md`'s `switch` case uses an `extendModules` variant linked from `/etc`, because nixpkgs' nspawn container module forbids `specialisation`; the collector restart waits for its telemetry endpoint; the expected RED list gains `queueOver512MiB`; and the `switch` case's recorded fallback.
  - #3560 (`3d2baf0ed`): `plan/task-3.md` and `task-7.md` gain the `--boot=all` wrapper, its assertion and the cursor-reset step.
  - #3561 (`70848c4f9`): `plan/task-4.md` gives the reconcile `diffutils` for C3's `cmp` and the container test a `chgrp systemd-journal` after journal rotation.
  - #3562 (`a1b2aac08`): `plan/task-5.md` looks up `StoreQueryFailing` by name in the timeline test instead of by index.
  - #3564 (`a106c086f`): `plan.md` and `plan/task-3.md`, `task-4.md`, `task-6.md`, `task-7.md` say "once per boot, and at an activation only when the unit changes" for `devloop-pg-grants` (review F2).

### 12.3 Known limitations

- The evaluator failed twice on 2026-10-25, at 14:38:00 and 16:09:07 UTC, inside magnetite's nixpkgs deploy and redeploy windows: the store briefly refused connections, the 14:38 run logged a failed query on both `fleet` and `devloop` and froze their instances for that run, and both runs failed to post their heartbeat.
  No `StoreQueryFailing` was posted, because the failure lasted one run, not 3 minutes.
- In the same window the notifier could not post: `observability-notify@opentelemetry-collector.service` at 14:37:48 and `observability-notify@fleet-alert.service` at 14:38:00 exited 1, so those two `FAILED` notices were not delivered, and the 16:09:07 `FAILED fleet-alert.service on magnetite` and its 16:10:02 `RESOLVED` were.
- `PullRequestQueueWaitBurn` fired on 2026-10-24 and 2026-10-28, each after a flake-updater burst, the behaviour tasks.md 10.10 accepts; each firing stays open about a day.
- The year-long retention is shown by the `devloop` TTL, not by data a year old; 7.2's boot record was observed once.
- nixbot's database reports a collation version mismatch (2.42 against 2.44) on every connection; the review placed its `REINDEX` outside S2.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: 9.1's arrival and batch legs were measured on substitutes, not on pull request 5 (§10.1, §10.2); the 7.7 and 9.1 reconcile window is six scheduled runs by operator decision, not seven (§10.4); and 10.5's store-failure count is 4, not 0, from the two evaluator failures of 2026-10-25, which posted no `StoreQueryFailing` (§10.5, §12.3)
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Every 7.1–7.7 expectation held, 7.7 over the shortened window, and every S2 check is under its evaluation budget at `origin/main` (§9.1).
Every ADDED and MODIFIED requirement is tied to a task and its evidence (§8b); §4 records no drift, and §8a's nouns go to the retrospective's promote list.
The warnings are recorded deviations and one runtime limitation, none of which failed a 7.x or 9.1 criterion as the operator scoped them.

**Next step**:

Step 9's validation, the satisfaction projection (tasks.md 8.4) and the archive (tasks.md 8.5).
