# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `stand-up-linux-fleet-collection`
**Verified at**: `2026-11-01 17:40 UTC`, with later reads to 18:07 UTC (A42's poll) and the review corrections of 18:38–18:50 UTC
**Verifier**: `VerifyMd (agent), writing tasks.md 10.1 read-only from tasks.md, design.md, proposal.md, plan/, specs/, logs/s4/ and logs/s4-evidence/; it measured nothing and ran no validator`; this file was then updated on 2026-11-01 with #3672's record of 5.7 and with read-only evidence and evaluation costs taken at origin/main `fcaf4e2d0` (`logs/s4-evidence/`, files named in §8b and §9.1), and again from 18:38 UTC with `review.md`'s findings F3, F4, F7, F8, F9 and F13 (tasks.md 12.3, 12.4, 12.7, 12.8, 12.9), read-only on magnetite, cinnabar and pyrite and at origin/main `f889b8321`

---

## 1. Structural Validation (`openspec validate stand-up-linux-fleet-collection --strict`)

- [x] The change reports valid; `openspec validate --all --json` did not run

**Result**:

`openspec validate stand-up-linux-fleet-collection --strict` and plan Task 10 Step 1's three discharge-name lists ran on 2026-11-01 against the working copy:

```text
undischarged:
unknown:
absent from verify.md:
Change 'stand-up-linux-fleet-collection' is valid
```

The deltas hold 40 requirements, three more than plan Task 10 Step 1 expects.
The three entered the deltas in #3666 (`9b0438fda`, "feat(ntfy): keep fleet alerts on disk for a week", merged 2026-11-01T05:55Z), which set cinnabar's ntfy `cache-duration` to `168h`, renamed A42 and modified the two requirements that rest on it; tasks.md 9.5 discharges them with the evidence §8b cites.
The third list fails as first written, because its `sed` output reaches `comm` unsorted; `plan/task-10.md` now sorts it with `| LC_ALL=C sort -u`.

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | none |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

The working copy's `tasks.md` has 54 ticked items and 6 unticked ones: 5.8, 10.2–10.5 and 11.1.
#3672 (`fcaf4e2d0`, "openspec: record pyrite's replay over its observed first hours", merged 2026-11-01T17:39Z) ticked 5.7 over the observed window 2026-11-01T05:59:08Z to 17:33:08Z, by the operator's decision of 2026-11-01, and added 5.8, which repeats the replay over pyrite's full first day.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 5.8 | runs after 2026-11-02T05:59Z: repeats 5.7's replay with `logs/s4-evidence/5.7-pyrite-replay.sh` over pyrite's full first day, runs 11.1 and runs 9.1's capture for pyrite; it also records the number of pyrite's `systemd-suspend` runs over the window (`sudo journalctl -b all -u systemd-suspend.service` on pyrite), and if that number is zero, as on 2026-11-01 at 18:15Z when the journal held none since boot 0 began on 2026-10-28 (`review.md` F13), this file states the laptop's resume path (the timer stopping in sleep, the exporter and the queue after resume) unexercised; evidence `5.8-pyrite-replay-<ts>.log` | yes; 11.1, the full-day replay and pyrite's 9.1 capture are inputs to this file |
| 11.1 | runs after 2026-11-02T05:59Z, with 5.8: 24 h of memory, unit, ZFS and file-system series for magnetite, cinnabar and pyrite, pyrite's NVMe series, and each host's `deploy_record` rows equal to its file's lines | yes |
| 9.1, pyrite's part | 9.1 is ticked for magnetite and cinnabar only (`9.1-day-20261101T045619Z.log`: "pyrite: not covered"); `9.1-due.md` sets pyrite's window from its deploy epoch, `PYRITE_DEPLOY_EPOCH=1793512554` (2026-11-01T05:55:54Z), so it reads after 2026-11-02T05:55:54Z, with 5.8 | yes, for HMC `Series cardinality stays bounded` and FII `otel-envelope regulates each agent from its own collector` on pyrite |
| 10.2 | review and retrospective | no |
| 10.3 | the archive-time row check; its `comm` output is pending and is pasted in §8a.3 when it runs; it prints exactly main's old `collected host` row, which this change's delta corrects, and that row is expected rather than a stop | yes, if it prints any other row |
| 10.4, 10.5 | the satisfaction projection and the archive | no; they are the archive |

---

## 3. Delta Spec Sync State

For each delta spec file under `openspec/changes/stand-up-linux-fleet-collection/specs/`, compared against the corresponding main capability spec:

| Capability | Sync status | Notes |
|---|---|---|
| `devloop-collection` | pending sync | MODIFIES `Every dev-loop event is recorded once and kept for a year` and `A gap in the dev-loop history reaches a person within a day` (the source "on magnetite"). |
| `devloop-collection-interface` | pending sync | RENAMES `magnetite's collector ships its own deploy records` to `Each agent host's collector ships its own deploy records`; MODIFIES it, `Dev-loop sources are stamped and routed to their table` and `This capability states its own trust boundary`. |
| `fleet-alerting` | pending sync | MODIFIES `Each known failure class on a host reaches a person as an alert`, `A missing signal is itself reported` and, through #3666, `A silent evaluator is reported from another host`. |
| `fleet-alerting-interface` | pending sync | MODIFIES `The evaluator queries each rule's database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Each rule's presence selector is watched`, `An always-on host's silence is reported` and, through #3666, `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe`. |
| `fleet-ingress-interface` | pending sync | New capability; `openspec/specs/fleet-ingress-interface/` does not exist; ADDS eight requirements. |
| `host-metrics-collection` | pending sync | RENAMES `magnetite contributes its own signals to the telemetry store` to `Each agent host contributes its own signals to the telemetry store`; MODIFIES it and four others. |
| `telemetry-store-interface` | pending sync | MODIFIES eight requirements, from `Listeners are bound to loopback only` to `Failure notices are posted to one topic`. |
| `world-assumptions` | pending sync | RENAMES A42; MODIFIES `Grounded vocabulary for behavioral requirements` (176 main rows, 192 in the delta), A13, A37, A38, A39, A40 and A42; ADDS A50, A51 and A52. |

All eight sync at archive.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D2 | the agent's 400 MiB metrics queue holds 24 h at the 256,000 bytes a minute R3.1 assumes (`design.md:166`) | HMC `Collection survives a telemetry store restart without losing the queued interval`; FII `Each agent exports by its role` | none; cinnabar's queue filled at 22,784 bytes a minute before magnetite's receiver started (`4.5-magnetite-20261029T083643Z.log`) |
| D8 | at most 40 ordinary unit names and 30 process names per host, notifier instances counted apart | HMC `Series cardinality stays bounded`; FII `otel-envelope on the ingress host regulates the fleet budget` | none for magnetite and cinnabar: unit names 29 and 6, process names 27 and 5 over the last 24 h (30 and 6 in the window), notifier instances 17 and 3 (`9.1-day-20261101T045619Z.log`); pyrite pending (§2) |
| D10 | each changed check's cost estimated and measured before and after | tasks.md preamble line 8 | measured costs fall inside D10's estimates except as §9.1 notes; the machine checks with the agent role on cinnabar and pyrite were measured only at origin/main `fcaf4e2d0` (§9.1) |

**Drift warnings** (non-blocking):

- `fleet-alerting`, `fleet-alerting-interface` and `world-assumptions` carry #3666's A42 change, which no section of `design.md` or `tasks.md` describes.

---

## 5. Implementation Signal

- [x] All related commits have been pushed
- [ ] No unstaged files in the worktree

The change's pull requests, all merged to `main`:

| Pull request | Merged (UTC) | Content | tasks.md |
|---|---|---|---|
| #3631 | 2026-10-29T04:52Z | the planning pull request | 1.1 |
| #3632 | 2026-10-29T07:57Z | pull request 1: host table, certificates, the agent by role, `otel-envelope`, `fleet-ingress` | 2.1–3.5 |
| #3633 | 2026-10-29T08:11Z | cinnabar's `collect` flag | 4.2 |
| #3634 | 2026-10-29T09:47Z | ZFS mounts in the file-system scraper | 6.1 |
| #3635 | 2026-10-29T10:36Z | pull request 2: file-system and NVMe rules, cinnabar's silence | 6.2–6.4 |
| #3636 | 2026-10-29T12:12Z | pull requests 3 and 4 in one: the hourly budget and the documentation | 7.1–7.4, 8.1–8.4 |
| #3664 | 2026-11-01T05:41Z | the fleet-collection acceptance checks recorded, and a warning against pinning ntfy's certificate | — |
| #3665 | 2026-11-01T05:55Z | pyrite's `collect` flag | 5.2 |
| #3666 | 2026-11-01T05:55Z | ntfy keeps fleet alerts for a week | none (§1) |
| #3667 | 2026-11-01T06:26Z | observability timers on UTC calendars | 5.4 |
| #3668 | 2026-11-01T06:26Z | pyrite's NVMe read without the error-information log | 5.3 |
| #3669 | 2026-11-01T07:05Z | the NVMe rules read the stored `_total` names | 5.3 |
| #3670 | 2026-11-01T15:24Z | pyrite's wifi left to NetworkManager, so systemd-networkd no longer runs a second DHCP client on `wlp2s0` | 5.6 |
| #3671 | 2026-11-01T15:24Z | pyrite's presence and offline test recorded | 5.5, 5.6 |
| #3672 | 2026-11-01T17:39Z | pyrite's replay over its observed first hours recorded, and 5.8 added | 5.7 |

#3670 fixed the second DHCP client that 5.6 found, after pyrite took about 6 min to answer once its wifi returned.
Its effect was not settled when it merged: pyrite deployed again at 15:41:19Z (its `/var/log/deploy-record.jsonl`), and a wifi toggle from 15:44:08Z left it unreachable until 16:02:04Z, 1,076 s (`logs/pyrite-wifi-toggle-20261101T154158Z.log`).

The working copy also carries other agents' unmerged chains, which this verification did not inspect.

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

`plan.md` and `plan/task-*.md` have no row marked `[~]`, so this section is blank by the template's rule.
The operator-timed items were 5.1, 5.5, 5.6, 9.2 and 9.3; §8b cites how each closed.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.

### 8a. Designation lint

#### 8a.1 Method

The proposal tags `host-metrics-collection`, `fleet-alerting` and `devloop-collection` `behavioral` (`proposal.md:80`, `:82`, `:84`).
The pass read the title and statement of each requirement these three deltas carry, five in `host-metrics-collection`, three in `fleet-alerting` and two in `devloop-collection`, excluding scenarios and `Discharged by` lines.
Each content noun was looked up in the `Term` column of `openspec/specs/world-assumptions/spec.md`'s designation table (176 rows), by the whole term or by a listed term the noun phrase is built from, such as `memory signal` from `memory` and `signal`.
A noun with no main row was then looked up among the 10 rows this change's `world-assumptions` delta then added (186 rows, every main row carried, by a sorted-row comparison run read-only on 2026-11-01); tasks.md 12.8 later added six more, for 192.
Quantities and identifiers (`fleet`, `devloop-collection`, host names, "24 hours", "512 MiB", "365 days") were not counted as nouns.

#### 8a.2 Result

Seven nouns have no row in the main table and resolve to a row this change's delta adds:

| Noun | Requirement | Delta row |
|---|---|---|
| agent host | HMC `Each agent host contributes its own signals to the telemetry store`, `Series cardinality stays bounded`, `Collection survives a telemetry store restart without losing the queued interval`, `A failed collection or store job notifies a person` | `agent host` |
| provisioned (agent host) | HMC `Each agent host contributes its own signals to the telemetry store` | `provisioned host` |
| file system | same; FA `Each known failure class on a host reaches a person as an alert` | `file system` |
| laptop | HMC `Each agent host contributes its own signals to the telemetry store`; FA `Each known failure class on a host reaches a person as an alert`, `A missing signal is itself reported` | `laptop` |
| disk health; disk (a laptop's, "failing or worn") | HMC `Each agent host contributes its own signals to the telemetry store`; FA `Each known failure class on a host reaches a person as an alert` | `disk health`, which defines the physical disk |
| ingress | HMC `Collection survives a telemetry store restart without losing the queued interval` | `ingress` |
| identifier that changes with each start of the collector | HMC `Series cardinality stays bounded` | `identifier` (collector start) |

Seven nouns resolved to no row in either table when the pass ran; `review.md` F8 took them up, and tasks.md 12.8 applied its dispositions:

| Noun | Requirement | Disposition (tasks.md 12.8) |
|---|---|---|
| owner | HMC `Stored unit names carry no owner's name` (title) | delta row `owner`, world-only; the title stays, because tasks.md and this file quote it |
| collection | HMC `Collection survives a telemetry store restart without losing the queued interval` (title, and "24 hours of collection"); `A failed collection or store job notifies a person` (title) | delta row `collection`, shared |
| job | HMC `A failed collection or store job notifies a person` (title) | delta row `job`, shared; it also grounds the word in the `unit`, `notifier` and `evaluator` rows |
| disk (where the queue is held, "on disk") | HMC `Collection survives a telemetry store restart without losing the queued interval` | the statement now reads "in its local state", the existing `local state` row |
| expected host ("a host expected to emit it") | FA `A missing signal is itself reported` | delta row `expected host`, shared |
| silence, silent | FA `A missing signal is itself reported` ("a laptop's silence", "every expected host is silent") | delta row `silent`, shared, one sense for a host and for a job |
| day, morning | DC `A gap in the dev-loop history reaches a person within a day` | delta row `day`, shared, a UTC calendar day; the statement's "by the end of the following morning" now reads "by 03:00 UTC of the following day", since the reconcile runs at 02:15 UTC (`modules/nixos/devloop-collection.nix:938`) |

The four ntfy assumptions in main, `openspec/specs/world-assumptions/spec.md:366`, `:378`, `:390` and `:402`, cited ntfy 2.28.0 while cinnabar runs 2.31.0; tasks.md 12.4 read their cited paths at the v2.31.0 tag and the delta now MODIFIES A37 to A40 (§8b).

One row resolved a noun with a sense this change made stale, and the delta now corrects it:

| Noun | Requirement | Finding |
|---|---|---|
| collected host | DC `Every dev-loop event is recorded once and kept for a year` | main's row reads "magnetite alone until the fleet's other collectors arrive", while cinnabar and pyrite have been collected hosts since #3633 and #3665; the delta's row now names magnetite, cinnabar and pyrite, and says stibnite is not one yet |

Every other content noun resolves to a main row: `collector`, `host`, `memory`, `compressed swap`, `process`, `unit`, `storage pool`, `out-of-memory`, `signal`, `service`, `database` (telemetry), `source`, `series`, `log record`, `trace`, `dev-loop record`, `telemetry store`, `cardinality`, `identifier` (per-process), `process number`, `command line`, `queued interval`, `gap`, `Omnigent worker`, `person`, `alias`, `regulator`, `envelope`, `disk share`, `failure notice`, `notification service`, `fleet`, `failure class`, `alert`, `alert rule`, `memory pressure`, `kernel`, `notifier`, `always-on host`, `heartbeat`, `evaluator` (alerting), `event` (dev-loop), `attribute`, `outcome`, `build service`, `build` (build service), `batch event`, `batch`, `merge queue`, `deploy` and `dev-loop history`.
Apart from the `collected host` row, each finding above went to the holistic review (`review.md` F8) and was applied by tasks.md 12.8.

#### 8a.3 Archive-time row check (tasks.md 10.3)

Pending; it runs at archive time:

```bash
row() { awk '/^\| /' "$1" | grep -vE '^\| *(Term|---)' | LC_ALL=C sort -u; }
LC_ALL=C comm -23 <(row openspec/specs/world-assumptions/spec.md) <(row openspec/changes/stand-up-linux-fleet-collection/specs/world-assumptions/spec.md)
```

Its output is pasted here when tasks.md 10.3 runs.
Because the delta rewrites the `collected host` row, the check will print main's `collected host` row, the one row the delta replaces on purpose rather than drops.

### 8b. Discharge coherence

Each behavioral requirement's `Discharged by` line names its interface requirements and world assumptions, and each `tasks.md` `Discharges:` clause names the requirements its task discharges.
Evidence names are files under `logs/s4-evidence/`, which is git-ignored.

| Requirement | Discharged by (tasks, evidence) | Under (W) | Status |
|---|---|---|---|
| devloop-collection: `Every dev-loop event is recorded once and kept for a year` | tasks.md 2.7, 4.6, 5.4; receiver id and settings and both `sqlquery` texts unchanged (`2.7-before-20261029T051753Z.log`, `2.7-after-20261029T051839Z.log`: "hashes equal"); lines equal rows on magnetite and cinnabar (`4.6-deploy-records-20261029T083717Z.log`, `4.6-deploy-records-20261101T045542Z.log`) and on pyrite, 31 and 31 (`5.4-pyrite-20261101T060249Z.log`) | A43, A44, A46, A47 | discharged; 11.1 repeats the line counts after 2026-11-02T05:59Z |
| devloop-collection: `A gap in the dev-loop history reaches a person within a day` | tasks.md 4.6; the passing path: the scheduled `devloop-reconcile` runs of 2026-10-30, 10-31 and 11-01 pass after the receiver moved (`4.6-deploy-records-20261101T045542Z.log`); the failing path: each of design D11's eight mutants in `vmTests.devloop-ingest` makes `devloop-reconcile` fail naming its clause, C1 to C7 (`3.0-devloop-ingest-20261029T061132Z.log:4646-8212`), and the reconcile runs at 02:15 UTC (`modules/nixos/devloop-collection.nix:938`), inside the statement's 03:00 UTC of the following day | A33, A43, A48 | discharged |
| devloop-collection-interface: `Each agent host's collector ships its own deploy records` | tasks.md 2.7, 3.4, 4.6, 5.4; `fleet-ingress` delivery case (`3.4-fleet-ingress-20261029T072517Z.log`); line and row counts (`4.6-deploy-records-…`, `5.4-pyrite-20261101T060249Z.log`) | — | discharged |
| devloop-collection-interface: `Dev-loop sources are stamped and routed to their table` | tasks.md 2.5, 2.7; R3.1 with `otlpInLogsPipeline` rejected (`2.5-r31-20261029T051525Z.log`); electrum's `logs/devloop-deploy_record` exports to `otlp_http/ingress-logs` (`2.7-after-20261029T051839Z.log`) | — | discharged |
| devloop-collection-interface: `This capability states its own trust boundary` | tasks.md 10.1; the requirement's own statement, §8d | — | discharged by statement |
| fleet-alerting: `Each known failure class on a host reaches a person as an alert` | tasks.md 2.8, 5.7, 6.1, 6.3; exclusion legs over the notified-unit union (`2.8-fleet-alert-20261029T053142Z.log`); replay before the rules shipped (`6.1-replay-20261029T094134Z.log`, `6.1-replay-fs-20261029T102912Z.log`, `6.1-replay-fs-20261029T103045Z.log`); `SUCCESS: 11 rules found` and the new legs (`6.3-rules-20261029T101800Z.log`); pyrite's replay over 05:59:08Z–17:33:08Z, no would-be firing (`5.7-pyrite-replay-20261101T173317Z.log`); the NVMe rules read the stored names (`5.3-nvme-names-red-20261101T063615Z.log`, `5.3-nvme-names-green-20261101T064653Z.log`, `5.3-nvme-names-replay-20261101T065651Z.log`); the scenario `The new rules meet the stored history` could not hold for pyrite: 6.1's NVMe replay was empty because pyrite did not collect until 2026-11-01, so the NVMe rules shipped on 2026-10-29 unreplayed and under names the store never gives, and 5.7's replay and 5.8's full day stand in for the replay before shipping | A33, A40, A41, A51 | discharged, with pyrite's replay made after the rules shipped; pyrite's full-day replay is 5.8, after 2026-11-02T05:59Z |
| fleet-alerting: `A missing signal is itself reported` | tasks.md 5.6, 5.7, 6.2, 6.7, 9.2; legs red before 6.3 (`6.2-red-20261029T094638Z.log`); 30 min with no `RuleSignalMissing` and the misspelt-selector control (`6.7-control-20261029T103909Z.log`, `6.7-signals-20261029T110916Z.log`); `[FIRING]` and `[RESOLVED] RuleSignalMissing cinnabar` (`9.2-cinnabar-20261029T133229Z.log`); the live run of the scenario `pyrite reports memory but no disk health`: magnetite's evaluator, expecting pyrite from its 06:28:35Z deploy, posted `[FIRING] RuleSignalMissing` for `rule=NvmeCriticalWarning, selector=smartctl_device_critical_warning` at 06:59:02.150Z and for `rule=NvmeWearHigh, selector=smartctl_device_percentage_used` at 06:59:02.225Z, and `[RESOLVED]` for both at 07:11:02.818Z and 07:11:02.886Z, after #3669's deploy at 07:06:26Z (`12.3-nvme-posts-20261101T183805Z.log:3-6`, `:9-10`); pyrite off its network 1,387 s with no evaluator post naming it (`5.6-offline-20261101T070658Z.log`, `5.6-acceptance-20261101T144554Z.log`), while the notifier's read in the same log printed `Failed to add filter for units: No data available` (`5.6-acceptance-20261101T144554Z.log:12-13`), journalctl's answer when no `observability-notify@*` unit has a journal entry, which a read on pyrite at 18:15Z repeated (`review.md` F7); the store's PromQL lookback is 300 s, GreptimeDB 1.2.1's default, since magnetite's `greptimedb.toml` sets none: cinnabar's last memory sample before 9.2's stop is at 13:02:28.858Z, and an instant `count by (host_name)` returns it at 13:07:28Z and not at 13:07:29Z (`12.9-lookback-20261101T184133Z.log`), so the 9.2 post at 13:17:02Z came 14 min 33 s after the last sample, inside the statement's 15 minutes | A13, A50 | discharged; 5.8 pending |
| fleet-alerting: `A silent evaluator is reported from another host` (MODIFIED by #3666, which brought it into the deltas) | no `tasks.md` item; cinnabar's `fleet-deadman.timer` ran 1,077 times from 2026-10-29T00:00Z to 2026-11-01T17:40Z with no failed run, each probe refused with 403 and each poll finding 9 to 11 heartbeats (`fa-silent-evaluator-20261101T174309Z.log`, its corrected summary); the build-time leg `an empty window posts one FIRING, resumed heartbeats one RESOLVED` (`modules/checks/fleet-alert.nix:273-283`) passes on the current code at every pull request; the live silence test is S3's: `[FIRING] AlertEvaluatorSilent magnetite` at 2026-10-18T09:20:02Z and `[RESOLVED]` at 09:25:02Z (`logs/s3-evidence/7.5-silent-20261018T092040Z.log`, `logs/s3-evidence/7.5-resolved-20261018T093153Z.log`), on code that e48bf7b2d, a1b2aac08, cdd4e49e5, a76ffc452, 493bd3981 (the dead-man's own timer) and 54a9613e7 have changed since | A33, A42 | discharged by the build-time leg on the current code and by S3's live test on the code of 2026-10-18; a live test on the deployed code, stopping `fleet-alert.timer` for 15 min at 5.8's sitting, waits on the operator (`review.md` question 3) |
| fleet-alerting-interface: `The evaluator queries each rule's database as the regulators' store account` | tasks.md 6.6, 7.3; the first run after 6.5 (`6.6-first-run-20261029T103804Z.log`); a fifth `regulator-password` holder fails magnetite's evaluation (`7.3-holders-20261029T095322Z.log`, `7.3-holders-20261029T105957Z.log`) | — | discharged |
| fleet-alerting-interface: `Alert rules are rendered from one Nix source to the evaluator and to promtool` | tasks.md 2.8, 6.3; `fleetAlertRules` red without `notifiedUnits` (`2.8-red-20261029T051915Z.log`), then green (`2.8-fleet-alert-20261029T052539Z.log`, `2.8-fleet-alert-20261029T053142Z.log`); `6.3-rules-20261029T101800Z.log` | — | discharged |
| fleet-alerting-interface: `Each rule's presence selector is watched` | tasks.md 6.2, 6.3, 6.7; `6.2-red-…`, `6.3-rules-…`, `6.3-red-nofilter-20261029T095500Z.log`, `6.3-red-nofilter-20261029T100657Z.log`, `6.7-signals-…` | — | discharged |
| fleet-alerting-interface: `An always-on host's silence is reported` | tasks.md 5.6, 6.2, 6.3, 9.2; `6.2-red-…`, `6.3-rules-…`, `9.2-cinnabar-20261029T133229Z.log`, `5.6-acceptance-20261101T144554Z.log` | — | discharged |
| fleet-alerting-interface: `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe` (MODIFIED by #3666, which brought it into the deltas) | no `tasks.md` item; cinnabar's journal logs `R9.4 probe refused with HTTP 403` at 17:35:00.340Z and `10 heartbeat(s) on fleet-heartbeat in the last 10m` at 17:35:00.355Z, and the 17:40:02Z run in the same order; the deployed script exits 1 unless the probe returns 403 and only then polls `json?poll=1&since=$window` (`fai-deadman-probe-poll-20261101T174326Z.log`) | A42 | discharged: each run probes an anonymous publish, stops unless it is refused, and then polls the heartbeat topic |
| fleet-ingress-interface: `One host table declares the agent hosts and what each reports` | tasks.md 2.2; the evaluated table (`2.2-table-20261029T050552Z.log`); the three overrides fail evaluation (`2.2-assertions-20261029T052304Z.log`, `2.2-overrides.nix`) | — | discharged |
| fleet-ingress-interface: `The collection CA issues each agent host one certificate` | tasks.md 2.3, 3.4; the vars step with every token hash equal (`2.3-vars-20261029T050844Z.log`, `2.3-validation-20261029T050659Z.log`, `2.3-validation-20261029T050722Z.log`, `2.3-red-rerun-20261029T051007Z.log`); `fleet-ingress` (`3.4-fleet-ingress-…`) | — | discharged |
| fleet-ingress-interface: `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address` | tasks.md 2.1, 2.5, 3.4, 4.5; R3.1 red (`2.1-red-20261029T050442Z.log`); `zt+` lists 4318 (`2.5-r31-…`); `absentClientCa` (`3.4-fleet-ingress-20261029T072517Z.log`); stibnite refused with curl exit 56, "certificate required" (`4.5-magnetite-20261029T083643Z.log`) | — | discharged |
| fleet-ingress-interface: `Each agent exports by its role` | tasks.md 2.4, 3.4, 4.3, 4.5; queue assertion red on electrum, then the overrides (`2.4-red-20261029T051112Z.log`, `2.4-queue-20261029T051313Z.log`, `2.4-overrides.nix`); cinnabar's queue growing before magnetite's receiver (`4.3-cinnabar-20261029T081444Z.log`) and draining after it (`4.5-magnetite-…`) | — | discharged |
| fleet-ingress-interface: `otel-envelope regulates each agent from its own collector` | tasks.md 3.1, 3.2, 3.4, 9.1, 9.2, 9.3; `3.1-red-20261029T055301Z.log`; every case `ok` and five mutants rejected (`3.2-check-20261029T055436Z.log`); `fleet-ingress`; no unattributed `FAIL` over magnetite's and cinnabar's 24 h (`9.1-day-20261101T045619Z.log`); `FAILED otel-envelope.service on cinnabar` and its `RESOLVED` (`9.2-cinnabar-…`, `9.3-exporter-20261101T051622Z.log`) | — | discharged for magnetite and cinnabar; pyrite's 24 h capture pending (§2) |
| fleet-ingress-interface: `otel-envelope on the ingress host regulates the fleet budget` | tasks.md 7.1, 7.2, 7.6; `budget` case red (`7.1-red-20261029T094804Z.log`) then green with each fixture failing its clause (`7.4-fleet-ingress-20261029T113746Z.log`); `budgetOnlyHourly` (`7.2-check-20261029T104006Z.log`); B1–B6 on magnetite (`7.2-budget-runtime-20261029T101012Z.log`); the drop-in control's `FAILED` and `RESOLVED` (`7.6-dropin-20261029T122000Z.log`) | — | discharged |
| fleet-ingress-interface: `pyrite's NVMe health is read by a loopback exporter` | tasks.md 2.6, 5.3; scrape render (`2.6-scrapes-20261029T051732Z.log`); ACL present, btime before the deploy, critical warning 0 and percentage used 11 stored (`5.3-smart-20261101T060029Z.log`, `5.3-smart-20261101T063202Z.log`) | A51 | discharged after #3668 and #3669 |
| fleet-ingress-interface: `This capability states its own trust boundary` | tasks.md 8.2, 10.1; the runbook's certificate, rotation and refusal sections (`8.2-runbook-20261029T111856Z.log`); the requirement's own statement, §8d | — | discharged by statement |
| host-metrics-collection: `Each agent host contributes its own signals to the telemetry store` | tasks.md 2.6, 2.10, 3.4, 4.5, 5.3, 5.4, 9.4; `2.6-scrapes-…`; eight drvPaths (`2.10-hosts-20261029T061006Z.log`, `2.10-scratch-20261029T063930Z.log`); `fleet-ingress`; magnetite and cinnabar in `count by (host_name)` (`4.5-magnetite-…`); pyrite's series (`5.4-pyrite-20261101T060249Z.log`, `5.3-smart-…`); no electrum, galena or scheelite (`9.4-unprovisioned-20261029T130212Z.log`) | A50, A51 | discharged; 11.1's 24 h read is pending |
| host-metrics-collection: `Series cardinality stays bounded` | tasks.md 2.2, 7.2, 9.1; `2.2-assertions-…` (50 of pyrite's services over 40 rejected); `7.2-check-…`; bounds held on magnetite and cinnabar (`9.1-day-20261101T045619Z.log`) | — | discharged for magnetite and cinnabar; pyrite pending (§2) |
| host-metrics-collection: `Collection survives a telemetry store restart without losing the queued interval` | tasks.md 2.4, 3.4; `2.4-red-…`, `2.4-queue-…`; `fleet-ingress` back-pressure and restart cases (`3.4-fleet-ingress-…`) | A52 | discharged |
| host-metrics-collection: `Stored unit names carry no owner's name` | tasks.md 2.2; the `omnigent-host-nobody` override fails (`2.2-assertions-…`) | — | discharged |
| host-metrics-collection: `A failed collection or store job notifies a person` | tasks.md 2.8, 3.3, 7.6, 9.2; notified units per host (`2.8-notify-20261029T052048Z.log`, `2.8-units-20261029T053823Z.log`); `envelopeNotNotified` and electrum's override (`3.3-red-20261029T055552Z.log`, `3.3-units-20261029T055646Z.log`, `3.3-units-scratch-20261029T063930Z.log`, `3.3-envelope-notified-20261029T055845Z.log`); `7.6-dropin-…`; `9.2-cinnabar-…` | A33, A37 | discharged |
| telemetry-store-interface: `Listeners are bound to loopback only` | tasks.md 2.1, 4.5; `2.1-red-…`; `ss -tlnH` on magnetite (`4.5-magnetite-…`) | — | discharged |
| telemetry-store-interface: `Scrape targets are reached on loopback` | tasks.md 2.6, 9.3; `2.6-scrapes-…`; `LocalExporterDown cinnabar` fired and resolved (`9.3-exporter-20261101T051622Z.log`) | — | discharged |
| telemetry-store-interface: `Ingest is OTLP over HTTP with a database header` | tasks.md 2.5, 3.4; `2.5-r31-…`; `fleet-ingress` delivery | — | discharged |
| telemetry-store-interface: `Credentials exist only as activation-resolved files owned by non-worker users` | tasks.md 2.3, 2.9, 7.3; `2.3-vars-…`; `workerOwnsOtelKey` red then rejected (`2.9-red-20261029T052211Z.log`, `2.9-r82-20261029T052229Z.log`); `7.3-holders-…` | — | discharged |
| telemetry-store-interface: `The telemetry store and the collector run inside a declared envelope` | tasks.md 2.4; `MemoryMax` 256M and the limiter override (`2.4-queue-…`) | — | discharged |
| telemetry-store-interface: `The collector's configuration bounds what it gathers` | tasks.md 2.2, 2.6, 7.2; `2.2-assertions-…`, `2.6-scrapes-…`, `7.2-check-…` | — | discharged |
| telemetry-store-interface: `Omnigent unit names are stored under aliases` | tasks.md 2.2; `2.2-assertions-…` | — | discharged |
| telemetry-store-interface: `Failure notices are posted to one topic` | tasks.md 2.8, 3.3, 9.2; `2.8-notify-…`, `3.3-units-…`, `9.2-cinnabar-…` | — | discharged |
| world-assumptions: `A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine` (MODIFIED) | world assumption; tasks.md 5.6; pyrite fell silent by leaving its network and raised nothing (`5.6-offline-…`, `5.6-acceptance-…`); pyrite's journal holds no `systemd-suspend` run since boot 0 began on 2026-10-28 (`review.md` F13) | — | assumption, not violated; 5.6 exercised network loss only, not a suspend or a resume; 5.8 records the suspend count over its window (§2) |
| world-assumptions: `A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user` (MODIFIED by tasks.md 12.4) | world assumption; the cited paths read at the `binwiederhier/ntfy` v2.31.0 tag, the source of cinnabar's package, with their text unchanged from 2.28.0; cinnabar has run 2.31.0 since 2026-10-25T16:09:05Z, its `ntfy serve --help` lists the three provisioning flags, and ntfy started at 06:03:17Z under 2.31.0 with its declared access entries (`12.4-ntfy-2.31-20261101T183920Z.log`) | — | assumption, holding at 2.31.0 |
| world-assumptions: `A38 — One ntfy access entry decides a request, a named user's before the anonymous one's` (MODIFIED by tasks.md 12.4) | world assumption; the access query and the access cache at v2.31.0, unchanged from 2.28.0, and the cache off on cinnabar; the dead-man's anonymous-publish probe refused with 403 on each of 1,088 runs from 2026-10-29T00:00Z to 18:39Z, 151 of them after ntfy's 06:03:17Z start, with no other outcome logged (`12.4-ntfy-2.31-20261101T183920Z.log`) | — | assumption, holding at 2.31.0 |
| world-assumptions: `A39 — ntfy refuses a request whose token it does not know, even where anonymous access is allowed` (MODIFIED by tasks.md 12.4) | world assumption; `server/server_auth.go` at v2.31.0, identical to 2.28.0's (`12.4-ntfy-2.31-20261101T183920Z.log`); nothing monitors it at runtime | — | assumption, holding at 2.31.0 by reading |
| world-assumptions: `A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header` (MODIFIED by tasks.md 12.4) | world assumption; `visitorID`, `extractIPAddress` and the rate-limit paragraph at v2.31.0, unchanged from 2.28.0; the 2.31.0 binary's `ntfy serve --help` lists `behind-proxy`, `proxy-trusted-hosts` and `visitor-prefix-bits-ipv6`, the last defaulting to 64 (`12.4-ntfy-2.31-20261101T183920Z.log`); the two-client visitor observation was made under 2.28.0 and not repeated | — | assumption, holding at 2.31.0 by reading; its runtime monitor last ran under 2.28.0 |
| world-assumptions: `A42 — ntfy keeps a topic's messages for a week and returns a recent window to a poll` (MODIFIED and RENAMED by #3666, which brought it into the deltas) | no `tasks.md` item; cinnabar's running `server.yml` sets `cache-duration: 168h` and `cache-file: /var/lib/ntfy-sh/cache-file.db` under ntfy 2.31.0; the 700 heartbeats published after ntfy's 06:03:17Z restart expire 604,800 s after publication; an anonymous `since=168h` poll at 18:07:35Z returned 724 messages, four of them older than 12 h, the oldest 12.05 h, a `since=10m` poll returned 10, and the 20 messages published before the restart survived it, carrying the old 12 h expiry, and expired on schedule (`a42-ntfy-retention-20261101T174340Z.log`, `a42-ntfy-retention-past12h-20261101T180734Z.log`) | — | assumption, holding against its violation condition: the 168 h is configured and seen in each new message's `expires`, retention is observed to 12.05 h, and a cache that survives a restart is observed only for messages under the old 12 h expiry; a poll after 2026-11-08T06:04Z observes the week |
| world-assumptions: `A50 — electrum, galena and scheelite exist only while provisioned on demand` | world assumption; tasks.md 2.10, 9.4; `2.10-hosts-…`, `9.4-unprovisioned-…` | — | assumption, holding |
| world-assumptions: `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools` | world assumption; tasks.md 5.3, 5.7; the controller rejects the Error Information log page with `Invalid Log Page (0x109)`, and smartctl_exporter 0.15.0 dropped the device for it (`5.3-smart-20261101T060029Z.log`); read through #3668's `--smartctl.path` wrapper, which removes `--log=error`, the health log answered (`5.3-smart-20261101T063202Z.log`), and the store held pyrite's SMART samples every minute from 06:28:38Z to 17:32:38Z (`5.7-pyrite-replay-20261101T173317Z.log`) | — | assumption, holding for the health log; the error-information log is not answered and not read |
| world-assumptions: `A52 — The collector answers back-pressure with a retryable refusal and keeps its persistent queue across an outage and a restart` | world assumption; tasks.md 3.4; `fleet-ingress` back-pressure case (`3.4-fleet-ingress-…`) | — | assumption, holding |
| world-assumptions: `Grounded vocabulary for behavioral requirements` (MODIFIED) | tasks.md 10.1, 12.8; the delta's table and §8a | — | discharged; the seven nouns of §8a.2 resolve to the rows and rewordings of tasks.md 12.8 |

The three requirements #3666 brought into the deltas have no `tasks.md` item; each is discharged by evidence taken on 2026-11-01 at origin/main `fcaf4e2d0`, except the dead-man's live silence test, which is S3's of 2026-10-18.
A37 to A40 entered the delta through tasks.md 12.4, read at the v2.31.0 tag and on cinnabar on 2026-11-01.
Every ADDED or MODIFIED requirement is discharged; four depend on observations due after 2026-11-02T05:59Z (§2).

### 8c. Alphabet check

HMC `Collection survives a telemetry store restart without losing the queued interval` states "24 hours" and "512 MiB", the agent's queue assertion phrased as world quantities; recorded, not counted.
HMC `Each agent host contributes its own signals to the telemetry store` names the `fleet` database and the capability `devloop-collection` by their identifiers; recorded, not counted.
No interface requirement references world state the machine cannot observe: both trust-boundary requirements name a certificate's CN, revocation, ZeroTier, root on magnetite and the sources' own records only to disclaim them (§8d).

### 8d. Trust boundaries

Two requirements state the trust boundary of a capability this change adds or modifies, and each is discharged by its own statement; no regulator applies.
Their scenarios state them as follows.

**fleet-ingress-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a host's series reach the store.

- Read as a set, the properties establish that each agent host holds a certificate from `otel-ca`, that the ingress accepts only such holders on magnetite's ZeroTier address at TLS 1.3, that each agent queues and retries toward it, and that `otel-envelope` regulates each collector and the fleet budget, each as far as its check, container test or recorded observation reaches.
- A host cannot be shown to write series only under its own name: any holder of an `otel-ca` certificate is trusted to write, and a certificate's CN is not bound to the `host.name` its agent stamps.
- A lost or stolen agent key is not shown to stop being accepted: certificates have no revocation, and a lost key stays valid until `otel-ca` is rotated, which the CA key, kept only in the encrypted repository vars, makes possible.
- ZeroTier does not authenticate the writer: it is trusted to carry packets between members and nothing more, so the two Android members and stibnite reach the handshake and only mTLS refuses them.
- These properties do not guarantee that a given series reaches the store: each stage's configuration, the gating checks, the container test and `otel-envelope` behave as stated, and nothing here observes a series' whole path.

**devloop-collection-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a dev-loop event reaches the store.

- Read as a set, the properties establish that the queries, the journal parse and the deploy snippet select, parse and write the stated fields; that the tables, pipelines and routes carry them into `devloop` keyed as stated; that the readers authenticate by peer under column grants; and that the reconcile compares each signal with its source daily, each as far as its check, container test or recorded observation reaches.
- An event nixbot or gitea-mq never records is not detected: nixbot and gitea-mq produce the source rows and lines, this machine only reads them, and their schema and messages are trusted at the pinned revisions.
- Not only the reconcile can read the `regulator` password or the deploy-record file: any root process on magnetite can read both, and the deploy-record file is world-readable on every host.
- Deploys on hosts other than magnetite are not reconciled: every NixOS agent host ships its records through the ingress, but `devloop-reconcile` compares magnetite's alone, the darwin machines ship none until they run collectors of their own, and the snippets are held by the build-time check only on the five x86_64-linux NixOS machines.
- A `deploy_record` row's `host` does not prove which host sent it: any holder of an `otel-ca` certificate can send a row naming any host.
- These properties do not guarantee that a given event reaches the store: each stage's configuration, the gating checks, the container tests and the daily reconcile behave as stated, and nothing here observes every event's whole path.

---

## 9. Evaluation cost and pending observations

### 9.1 Evaluation cost of each new or changed check

The budget is 0.5 GiB, 536,870,912 bytes of `gc.totalBytes` (tasks.md preamble line 8).
Unless a row says otherwise, the method is `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`, reading `.gc.totalBytes` and `.cpuTime` from the stats file; the files of 1.2 and 3.5 print it in their header, and those of 2.5, 2.9, 3.2, 6.3 and 7.2 print the figures alone under the commands of `plan/task-2.md:401`, `plan/task-2.md:559`, `plan/task-3.md:114`, `plan/task-6.md:96` and `plan/task-7.md`.
The figures at origin/main `fcaf4e2d0` were taken on 2026-11-01 in one detached worktree by the same method, and for the container tests at `.#.vmTests.x86_64-linux.<test>.drvPath`; all are in `costs-origin-main-20261101T174417Z.log`, with each run's stats file under `costs-origin-main-20261101T174417Z.stats/`.
The figures at origin/main `f889b8321` were taken on 2026-11-01 at 18:42Z for tasks.md 12.7 by the same method, with the flake named `git+file://$PWD?rev=f889b8321…` rather than a worktree, and `otel-collector-config` measured beside them as a control; they are in `costs-envelopes-20261101T184219Z.log`, with the stats files under `costs-envelopes-20261101T184219Z.stats/`.

| Check | Point | `gc.totalBytes` | GiB | cpuTime (s) | Log |
|---|---|---|---|---|---|
| `otel-collector-config` (changed) | design baseline, GR §6 | 488,430,112 | 0.455 | 1.57 | `logs/s4/evalstats/run2/otel-collector-config.json` |
| | before: `main@origin` `8d91b3301` | 488,500,368 | 0.455 | 1.49 | `1.2-baseline-20261029T044822Z.log` |
| | after 2.1–2.5 | 475,059,936 | 0.442 | 1.47 | `2.5-r31-20261029T051525Z.log` |
| | after 3.2, at 05:58Z | 475,975,216 | 0.443 | 1.51 | `3.2-cost-20261029T055823Z.log` |
| | after: pull request 1's head | 475,987,136 | 0.443 | 1.37 | `3.5-cost-20261029T064230Z.log` |
| | after 7.2 | 476,111,040 | 0.443 | 1.45 | `7.2-cost-after-20261029T095302Z.log` |
| | origin/main `fcaf4e2d0` | 476,108,544 | 0.443 | 1.46 | `costs-origin-main-20261101T174417Z.log` |
| `otel-envelope` (new) | before | none | — | — | the check did not exist |
| | after 3.2 | 156,291,488 | 0.146 | 0.56 | `3.2-cost-…` |
| | after: pull request 1's head | 156,304,304 | 0.146 | 0.50 | `3.5-cost-…` |
| | before 7.2 / after 7.2 (two runs) | 156,304,304 / 156,537,440 and 156,537,840 | 0.146 | 0.58 / 0.51 and 0.56 | `7.2-cost-before-20261029T094410Z.log`, `7.2-cost-after-…` |
| | origin/main `f889b8321` | 156,780,640 | 0.146 | 0.68 | `costs-envelopes-20261101T184219Z.log` |
| `fleet-alert` (changed) | before: `main@origin` | 339,763,552 | 0.316 | 0.95 | `1.2-baseline-…` |
| | after 2.8 (two runs) | 340,372,288 and 340,419,040 | 0.317 | 0.95 and 0.96 | `2.8-fleet-alert-20261029T052539Z.log`, `2.8-fleet-alert-20261029T053142Z.log` |
| | after: pull request 1's head | 340,497,248 | 0.317 | 0.90 | `3.5-cost-…` |
| | before 6.3: `main@origin` `20a396b55`, without 6.2's legs | 340,809,424 | 0.317 | 1.22 | `fleet-alert-458M-repro-20261101T174622Z.log` |
| | after 6.3 | 351,503,264 | 0.327 | 1.00 | `6.3-rules-20261029T101800Z.log` |
| | after #3669: origin/main `fcaf4e2d0` | 351,526,272 | 0.327 | 1.01 | `costs-origin-main-…` |
| `greptimedb-envelope` (changed) | before: `main@origin` | 399,913,392 | 0.372 | 1.03 | `1.2-baseline-…` |
| | after 2.9 | 400,701,584 | 0.373 | 1.07 | `2.9-r82-20261029T052229Z.log` |
| | after: pull request 1's head | 400,779,440 | 0.373 | 1.01 | `3.5-cost-…` |
| | before 7.2 / after 7.2 | 400,779,440 / 400,779,008 | 0.373 | 1.41 / 1.05 | `7.2-cost-before-…`, `7.2-cost-after-…` |
| | after #3667: origin/main `f889b8321` | 401,034,624 | 0.373 | 1.15 | `costs-envelopes-20261101T184219Z.log` |
| `nixos-magnetite` (machine check) | before / after 2.10 | 2,856,483,312 / 2,860,219,344 | 2.660 / 2.664 | 11.72 / 10.92 | `1.2-baseline-…`, `2.10-hosts-20261029T061006Z.log` |
| | origin/main `fcaf4e2d0` | 2,860,693,600 | 2.664 | 11.20 | `costs-origin-main-…` |
| `nixos-cinnabar` | before / after 2.10, `collect` false | 2,648,967,568 / 2,651,020,528 | 2.467 / 2.469 | 13.56 / 11.96 | same |
| | origin/main `fcaf4e2d0`, `collect` true | 2,659,133,216 | 2.477 | 11.99 | `costs-origin-main-…` |
| `nixos-pyrite` | before / after 2.10, `collect` false | 3,047,780,768 / 3,050,194,208 | 2.838 / 2.841 | 11.48 / 11.36 | same |
| | origin/main `fcaf4e2d0`, `collect` true | 3,055,497,248 | 2.846 | 11.38 | `costs-origin-main-…` |
| `nixos-electrum` | before / after 2.10 | never measured / 2,267,366,960 | — / 2.112 | — / 7.69 | `2.10-hosts-…` |
| | origin/main `fcaf4e2d0` | 2,267,601,760 | 2.112 | 7.83 | `costs-origin-main-…` |
| `nixos-galena` | before / after 2.10 | never measured / 2,440,631,248 | — / 2.273 | — / 8.68 | `2.10-hosts-…` |
| | origin/main `fcaf4e2d0` | 2,440,885,072 | 2.273 | 8.93 | `costs-origin-main-…` |
| `vmTests.fleet-ingress` (new container test) | before | none | — | — | the test did not exist |
| | origin/main `fcaf4e2d0` | 1,130,006,512 | 1.052 | 2.94 | `costs-origin-main-…` |
| `vmTests.devloop-ingest` (changed in #3632) | origin/main `fcaf4e2d0` | 1,806,107,984 | 1.682 | 5.04 | `costs-origin-main-…` |
| `vmTests.greptimedb-pipeline` (changed in #3632) | origin/main `fcaf4e2d0` | 902,539,664 | 0.841 | 3.57 | `costs-origin-main-…` |

Every check under the budget stayed under it; at origin/main, `otel-collector-config` and `fleet-alert` were measured at `fcaf4e2d0`, and `otel-envelope` and `greptimedb-envelope` at `f889b8321`, which adds to `fcaf4e2d0` this change's `verify.md`, an agent-context commit and a worktrunk update (`git log fcaf4e2d0..f889b8321`).
The control `otel-collector-config` measured 476,352,624 B (0.444 GiB, 1.83 s) at `f889b8321` against 476,108,544 B at `fcaf4e2d0`, a difference of 244,080 B.
`otel-collector-config` fell from 0.455 to 0.443 GiB, because 2.2 moved the unit-cap and alias clauses into module assertions.
`otel-envelope` landed inside design D10's estimate of 0.12 to 0.2 GiB, `fleet-alert` inside 0.30 to 0.34 GiB and `greptimedb-envelope` under 0.38 GiB.
`6.3-cost-before-20261029T094622Z.log` recorded 458,012,080 B for `fleet-alert` before 6.3, and its command, not the check, explains the figure.
That command, recorded in the measuring session's transcript, named the attribute as `git+file://$PWD?rev=$rev#checks.x86_64-linux.fleet-alert.drvPath`, with no `.` after `#`, so nix looked for it under `packages` and `legacyPackages` first.
It ran at `main@origin` `20a396b55`, which does not contain 6.2's legs.
Re-run at that revision, the same derivation (`m48gsafrb25mfq1nbq79xh1ghcmsgrl7-fleet-alert.drv`) costs 458,014,384 B named that way and 340,809,424 B named `#.checks…` (`fleet-alert-458M-repro-20261101T174622Z.log`), so the pre-6.3 figure is 340,809,424 B (0.317 GiB).
The machine checks are outside the 0.5 GiB budget by design D10 (`design.md:323`); their 2.10 "after" figures were taken where cinnabar's and pyrite's `collect` was false, and the origin/main `fcaf4e2d0` figures are the first with the agent role on those two hosts.
The container tests live under `vmTests`, outside pull-request gating (`modules/README.md:32`, `:48`).
`design.md:36` and tasks.md's preamble line 8 state the 0.5 GiB budget for checks measured at `.#.checks.x86_64-linux.<check>.drvPath`, a budget that exists because nixbot evaluates every check attribute on every pull request; nixbot does not evaluate `vmTests`, so the budget does not bind the container tests, and their 0.841 to 1.682 GiB are recorded without a budget verdict.
`2.10-interim-hosts-20261029T053252Z.log` records five earlier figures without cpuTime.

Costs this change never measured:

- `nixos-electrum` and `nixos-galena` before the change; scheelite has no machine check.
- `vmTests.x86_64-linux.devloop-ingest` and `vmTests.x86_64-linux.greptimedb-pipeline` before #3632.
- Each machine check between 2.10 and origin/main `fcaf4e2d0`, so the separate cost of #3633, #3635, #3636, #3665, #3667 and #3668 is unknown.

### 9.2 Deploy and control times

Times are from `logs/s4-evidence/window.env` and the `done:` notes of `tasks.md`.

| Event | Time (UTC) | Evidence |
|---|---|---|
| cinnabar deployed with the agent role | `CINNABAR_DEPLOY_EPOCH=1793261551` (2026-10-29T08:12:31Z) | `4.2-cinnabar-active-20261029T081437Z.log`, `4.3-cinnabar-20261029T081444Z.log` |
| magnetite's ingress receiver started | `MAGNETITE_RECEIVER_EPOCH=1793262973` (2026-10-29T08:36:13Z) | `4.4-magnetite-active-20261029T083632Z.log`, `4.5-magnetite-…` |
| magnetite deployed with pull request 2 | 2026-10-29, before 10:38Z | `6.5-magnetite-20261029T103752Z.log` |
| magnetite deployed with #3636; drop-in control | 2026-10-29T12:20:21Z–12:21:25Z; the first scheduled hourly run 13:00:00Z–13:00:02Z, greptimedb at most 527,511,552 B during it | `7.5-pre-20261029T121256Z.log`, `7.5-post-20261029T121431Z.log`, `7.6-dropin-…` |
| cinnabar's collector stopped (9.2) | `CINNABAR_STOP_EPOCH=1793278947` to `CINNABAR_START_EPOCH=1793279849` (2026-10-29T13:02:27Z–13:17:29Z) | `9.2-cinnabar-…` |
| cinnabar's node exporter stopped (9.3) | `EXPORTER_STOP_EPOCH=1793508928` to `EXPORTER_START_EPOCH=1793509832` (2026-11-01T04:55:28Z, 904 s) | `9.3-exporter-…` |
| pyrite deployed with the agent role | 2026-11-01T05:55:54Z–05:59:05Z | tasks.md 5.2 |
| pyrite off its network (5.6) | `PYRITE_OFFLINE_START=1793542957` to `PYRITE_OFFLINE_END=1793544344` (2026-11-01T14:22:37Z–14:45:44Z) | `5.6-acceptance-…` |

### 9.3 Pending after 2026-11-02T05:59Z

- tasks.md 5.8: pyrite's replay over its full first day, recording any would-be firing after 17:33Z with its cause, and pyrite's `systemd-suspend` count over the window; with a count of zero, the laptop's resume path is recorded here as unexercised (§2).
- tasks.md 11.1: the integration verification, recorded here beside the controls of 4.5, 5.6, 7.6, 9.2 and 9.3.
- tasks.md 9.1's pyrite capture, from `PYRITE_DEPLOY_EPOCH` (2026-11-01T05:55:54Z) for 24 h, run with 5.8.
- tasks.md 10.3's `comm` output, at archive time (§8a.3).

---

## Overall Decision

Not set; it follows §1's validation and §9.3's pending observations.
