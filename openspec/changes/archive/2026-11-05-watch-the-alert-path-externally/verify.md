# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `watch-the-alert-path-externally`
**Verified at**: `2026-11-05 14:30 UTC`
**Verifier**: `Cam76Closeout (agent), writing tasks.md 6.1 read-only from tasks.md, design.md, proposal.md, plan/, specs/ and logs/cam76-evidence/; the done notes of tasks.md are authoritative, and every evidence file named below is under logs/cam76-evidence/, which is git-ignored; it measured no cost and ran nothing on the hosts`

---

## 1. Structural Validation (`openspec validate watch-the-alert-path-externally --strict`)

- [x] The change reports valid

**Result**:

`openspec validate watch-the-alert-path-externally --strict` and plan Task 6 Step 1's discharge-name comparison ran on 2026-11-05 against the working copy:

```text
Change 'watch-the-alert-path-externally' is valid
```

The comparison of every name quoted after `Discharges:` in `tasks.md` against the names this file quotes printed nothing, run with `LC_ALL=C sort -u` on both sides; with the plan's unqualified `sort`, `comm` rejects its input as unsorted under the workstation's locale.

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | none |

**At archive, 2026-11-05 (`openspec validate --all --strict`).**
The criterion is that the archive adds no strict failure, because the repository failed `--all --strict` before the sync for reasons outside this change.
Before the sync, at 14:17:52Z: 12 passed and 31 failed of 43 items (`6.3-validate-before-20261105T141752Z.json`).
The 14 failing changes are `adopt-queue-landing-protocol`, `annotate-discharge-evidence`, `capi-hetzner-cluster`, `declarative-cognee-endpoint`, `deploy-omnigent-magnetite`, `filter-check-sources-for-substitution`, `k3s-nixos-vm-tests`, `path-scope-plugin-releases`, `pyrite-bluetooth-boot`, `pyrite-dankgreeter`, `pyrite-dms-session`, `sso-gateway`, `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.
The 17 failing specs are `agentic-workflow-routing`, `apple-laptop-hardware-support`, `bare-metal-install-path`, `encrypted-zfs-root`, `first-party-skill-distribution`, `graphical-desktop-session`, `openspec-linear-sync`, `pi-agent-environment`, `project-management-hub`, `requirements-stratification`, `satisfaction-argument-audit`, `shared-reference-tree`, `shared-reference-tree-interface`, `skill-corpus-interface`, `stratified-change-authoring`, `third-party-plugin-dependency` and `world-assumptions`.
`world-assumptions` failed before the sync with 12 warnings: its placeholder Purpose and 11 statements over 500 characters.
`fleet-alerting`, `fleet-alerting-interface` and this change passed.
A first sync, run on a copy of `openspec/`, added one failure: spec `fleet-alerting-interface`, whose MODIFIED `The rule check runs promtool, fixture mutants and a property test` had a 528-character statement.
It was fixed in the delta before the sync by dropping the statement's closing clause, "within an evaluation budget of 0.5 GiB", which the same requirement's scenario `The check's evaluation cost is measured` already states; the statement is now 488 characters, with its title and obligations unchanged.
After the archive, at 14:23:49Z: 11 passed and 31 failed of 42 items, with the same 31 failing items (`6.3-validate-after-20261105T142349Z.json`); this change left the list, `fleet-alerting` and `fleet-alerting-interface` pass, and `world-assumptions` keeps the same 12 warnings.

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

Every item is ticked; 2.8, 4.4 and 5.3 were ticked on 2026-11-05 from their logs, and 6.1 to 6.3 and 7.1 at the archive.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

For each delta spec file under `openspec/changes/watch-the-alert-path-externally/specs/`, compared against the corresponding main capability spec:

| Capability | Sync status | Notes |
|---|---|---|
| `fleet-alerting` | synced at archive | ADDS `An outage of the alert path reaches the operator by email from outside the fleet`. |
| `fleet-alerting-interface` | synced at archive | ADDS `The dead-man pings the watch service only after a passing run` and `The ping URL travels only as a credential read on stdin`; MODIFIES `The rule check runs promtool, fixture mutants and a property test` and `This capability states its own trust boundary`; 6.3 edits its Purpose. |
| `world-assumptions` | synced at archive | MODIFIES `Grounded vocabulary for behavioral requirements` (192 main rows, 195 in the delta) and A33; ADDS A53, A54 and A55. |

All three synced on 2026-11-05, as `openspec archive` merges them; each main spec now reads as already synced.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D2 | the ping is the last step of a run whose probe, poll and posts all passed, and is skipped when the poll held no heartbeat | FAI `The dead-man pings the watch service only after a passing run` | none; the five mutants are each rejected at their named leg (`2.4-green-20261102T051034Z.log`) |
| D4, D5 | the URL reaches curl on stdin from a `LoadCredential` file, never the store, argv or the environment | FAI `The ping URL travels only as a credential read on stdin` | none at build and on cinnabar; the prompt's rejection was shown by the generator's script, not at the prompt (§10) |
| D6 | period 5 min, grace 10 min, so the down email arrives 15 to 20 min after the last accepted ping | FA `An outage of the alert path reaches the operator by email from outside the fleet`; A53 | none; both stops emailed 15 min after the last accepted ping, at the minute resolution the operator reported |

**Drift warnings** (non-blocking):

- 4.2 expected `FAILED fleet-deadman on cinnabar` once ntfy was back; none arrived, because the notifier posted the failures to the stopped ntfy and does not retry (§10).

---

## 5. Implementation Signal

- [x] All related commits have been pushed
- [ ] No unstaged files in the worktree

The change's pull requests, all merged to `main`:

| Pull request | Merged (UTC) | Content | tasks.md |
|---|---|---|---|
| #3678 | 2026-11-01T18:50Z | the planning pull request | — |
| #3689 | 2026-11-02T05:10Z | the plan corrected after its review | 1.1 |
| #3716 | 2026-11-04T14:25Z | pull request 1: the ping step, its credential, R9.6 and the generated var files | 2.1–2.8 |
| #3717 | 2026-11-04T21:34Z | pull request 2: the runbook, ADR-009 and the observability corpus | 5.1–5.3 |

The working copy also carries other agents' unmerged chains, which this verification did not inspect.

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

`plan.md` and `plan/task-*.md` have no row marked `[~]`, so this section is blank by the template's rule.
The operator-timed items were 2.6, 2.7, 3.2, 4.1 to 4.4; §8b cites how each closed.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.

### 8a. Designation lint

#### 8a.1 Method

The proposal tags `fleet-alerting` `behavioral` (`proposal.md:40`).
The pass read the title and statement of its one new requirement, `An outage of the alert path reaches the operator by email from outside the fleet`, excluding scenarios and the `Discharged by` line.
Each content noun was looked up in the `Term` column of this change's `world-assumptions` delta table, 195 rows: main's 192, every one carried (§8a.3), and this change's `watch service`, `ping` and `email`.
Quantities and identifiers (`cinnabar`, "15 and at most 20 minutes") were not counted as nouns.

#### 8a.2 Result

Three nouns resolve to a row this change's delta adds: `watch service`, `ping` ("the dead-man's last accepted ping", "pings again") and `email`.

Eight nouns resolve to a main row: `operator`, `fleet`, `notification service`, `evaluator` (the alerting sense), `heartbeat`, `dead-man`, `alert` (in "alert path"), and `path`, whose `alert delivery` sense is the chain of services an alert travels; the statement's "the path by which the evaluator's heartbeat reaches that service" names part of that chain.

One noun resolves to no row:

| Noun | Requirement | Finding |
|---|---|---|
| outage | FA `An outage of the alert path reaches the operator by email from outside the fleet` (title only) | no row; the statement grounds it as the listed components "stop working", so the title reads as a summary of the statement; recorded, not changed at archive |

#### 8a.3 Archive-time row check (tasks.md 6.2)

Run on 2026-11-05 before the sync:

```bash
row() { awk '/^\| /' "$1" | grep -vE '^\| *(Term|---)' | LC_ALL=C sort -u; }
LC_ALL=C comm -23 <(row openspec/specs/world-assumptions/spec.md) <(row openspec/changes/watch-the-alert-path-externally/specs/world-assumptions/spec.md)
```

It printed nothing; `comm -13` printed exactly the three added rows.
Main's `world-assumptions` spec last changed in `79d5cee3d` ("openspec: archive the fleet-collection change"), before the 2026-11-02 retake, so the block was not retaken again: the delta's `Grounded vocabulary for behavioral requirements` block equals main's apart from the three rows, and its A33 differs from main's only in the evidence and scenario text this change revises.

### 8b. Discharge coherence

Each behavioral requirement's `Discharged by` line names its interface requirements and world assumptions, and each `tasks.md` `Discharges:` clause names the requirements its task discharges.
Statuses name what was observed: "observed" with its window, "configured" where only the configuration is shown, and "not violated" where nothing exercised the assumption.

| Requirement | Discharged by (tasks, evidence) | Under (W) | Status |
|---|---|---|---|
| fleet-alerting: `An outage of the alert path reaches the operator by email from outside the fleet` | tasks.md 2.4, 4.2, 4.3, 4.4; the ping legs and mutants (`2.4-green-20261102T051034Z.log`); the ntfy stop: last accepted ping 15:25:00Z, ntfy stopped 15:25:06Z, down email 15:40Z, ntfy started 15:50:06Z, first ping 15:55:02Z, up email 15:55Z; the evaluator stop: timer stopped 16:05:08Z, last ping 16:15:02Z, `[FIRING] AlertEvaluatorSilent magnetite` 16:20Z, down email 16:30Z, timer started 16:35:08Z, `[RESOLVED]` 16:40Z, ping 16:40:03Z, up email 16:40Z (`4.2-4.3-results-20261104T190037Z.log`, `4.2-4.3-operator-20261104T212115Z.log`, `4.2-4.3-schedule-20261104T152101Z.log`); the quiet window: 260 `external ping accepted`, 0 `no external ping`, 0 failed runs and no email (`4.4-day-20261105T141643Z.log`) | A53, A54, A55 | observed: both stops on 2026-11-04 emailed 15 min after the last accepted ping, at the operator's minute resolution, and emailed again after the first ping; no email over 2026-11-04T16:40:03Z to 2026-11-05T14:16:43Z, a window the operator shortened from 24 h (§10); the scenario `The watch service fails together with the fleet` is accepted, not exercised |
| fleet-alerting-interface: `The dead-man pings the watch service only after a passing run` | tasks.md 2.1, 2.4, 3.2, 4.2, 4.3, 4.4; RED (`2.1-red-20261102T050640Z.log`), nine `ok:` legs and five mutants rejected at their named legs (`2.4-green-20261102T051034Z.log`); 6 of 6 runs pinged over 14:28:53Z to 14:59:53Z (`3.2-first-pings-20261104T142853Z.log`); the five runs of the ntfy stop failed at the probe with `HTTP 000` and sent no ping, and the four runs without a heartbeat logged `no external ping` (`4.2-4.3-results-20261104T190037Z.log`); 260 of 260 runs pinged over the quiet window (`4.4-day-20261105T141643Z.log`) | A53 | discharged at build; observed on cinnabar from 2026-11-04T14:28:53Z to 2026-11-05T14:16:43Z; the `OK (not found)` and closed-port scenarios are shown at build only |
| fleet-alerting-interface: `The ping URL travels only as a credential read on stdin` | tasks.md 2.2, 2.3, 2.5, 2.7, 3.2; RED (`2.2-red-20261102T050655Z.log`), the URL on stdin and the argv mutant rejected (`2.3-transport-20261102T050814Z.log`); the store-path assertion fails an `extendModules` override (`2.5-store-path-20261102T051202Z.log`); the generator's script rejects `https://hc-ping.com/not-a-uuid` with exit 1 and no `curl-config`, run on magnetite (`2.7-validation-20261104T140219Z.log`); `LoadCredential` names the `curl-config` path (`2.8-eval-20261104T140122Z.log`); the deployed unit's two lines, and `hc-ping` 0 times in its environment and in cinnabar's journal (`3.2-first-pings-20261104T142853Z.log`) | — | discharged; the prompt's rejection was shown by running the generator's script, not at the gated prompt (§10) |
| fleet-alerting-interface: `The rule check runs promtool, fixture mutants and a property test` (MODIFIED) | tasks.md 2.1, 2.4; the ping legs and the five ping mutants (`2.4-green-20261102T051034Z.log`); S3's `deadmanRehearsal` and `deadmanClause` keep main's `drvPath`s (`2.5-store-path-20261102T051202Z.log`); the cost under 0.5 GiB (§9.1); `fleet-alert` built after the generation (`2.8-check-20261104T140253Z.log`) and passed nixbot in #3716 | — | discharged |
| fleet-alerting-interface: `This capability states its own trust boundary` (MODIFIED) | tasks.md 5.1, 6.1; the runbook's section "The external watch" (#3717); the requirement's own statement, §8d | — | discharged by statement |
| world-assumptions: `Grounded vocabulary for behavioral requirements` (MODIFIED) | tasks.md 6.1, 6.2; the delta's table, §8a | — | discharged; one title noun, `outage`, has no row (§8a.2) |
| world-assumptions: `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path` (MODIFIED) | no `tasks.md` item; the delta revises its evidence and its scenario `A second delivery path appears`, because the watch service's email carries no alert or failure notice | — | configured: the change adds no second delivery path for alerts; every alert of 4.3 arrived through ntfy |
| world-assumptions: `A53 — healthchecks.io counts a ping by its URL and emails when pings stop for longer than a check's period and grace` | world assumption; tasks.md 2.6, 4.2, 4.3; period 5 min and grace 10 min (`2.6-check-20261104T135831Z.log`); the check went `new ➔ up` at 14:30Z with one ping per 5 min (`3.2-first-pings-20261104T142853Z.log`); the down emails 15 min after the last ping and the up emails after the first ping (`4.2-4.3-operator-20261104T212115Z.log`) | — | observed twice on 2026-11-04, 15:25 to 15:55Z and 16:05 to 16:40Z; not violated over the quiet window to 2026-11-05T14:16:43Z |
| world-assumptions: `A54 — healthchecks.io runs outside the fleet, on Hetzner in Germany` | world assumption; no `tasks.md` item; the service's privacy and comparison pages, read on 2026-11-01, as the requirement's evidence cites | — | not violated: no outage of the service observed from 2026-11-04T14:30Z to 2026-11-05T14:16:43Z; its hosting is read from its pages, not observed |
| world-assumptions: `A55 — The operator's mailbox is reached without the fleet` | world assumption; tasks.md 2.6, 4.2; the integration address is at `gmail.com` (`2.6-check-20261104T135831Z.log`); the down email arrived at 15:40Z while ntfy on cinnabar was stopped (`4.2-4.3-operator-20261104T212115Z.log`) | — | observed during the ntfy stop of 2026-11-04 15:25:06Z to 15:50:06Z; an outage of cinnabar itself was not exercised |

Every ADDED or MODIFIED requirement is discharged or carries its world-assumption status; none waits on a later observation.
One observed gap is recorded and not discharged: a dead-man failure during an ntfy outage posts no `FAILED fleet-deadman`, because the notifier does not retry (§10).

### 8c. Alphabet check

FA `An outage of the alert path reaches the operator by email from outside the fleet` names cinnabar by its identifier and states "15 and at most 20 minutes" as a world quantity; recorded, not counted.
FAI `The ping URL travels only as a credential read on stdin` names `hc-ping.com`, the generator, `LoadCredential` and the module's assertion, all machine-observable at evaluation or on cinnabar.
The trust-boundary requirement names healthchecks.io, the mail provider and root on cinnabar only to disclaim them (§8d).

### 8d. Trust boundaries

One requirement states the trust boundary of the capability this change modifies, and it is discharged by its own statement; no regulator applies.
Its scenarios state it as follows.

**fleet-alerting-interface: `This capability states its own trust boundary`.**
The capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

- Read as a set, the properties establish that the evaluator queries each rule's database as `regulator` on the path its language names, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats, the dead-man and its ping behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured with the stated access entries, provisioning and proxy settings.
- ntfy's enforcement is not guaranteed: ntfy enforces the access entries and rate limits and delivers to subscribed devices, and this machine only configures it, which R9.4's probe and the acceptance observations monitor.
- The `alerter` token's secrecy is not guaranteed: any root process on magnetite or cinnabar can read it.
- An outage of cinnabar or its ntfy is reported because the dead-man stops pinging healthchecks.io, which emails the operator once the check's period and grace pass; healthchecks.io evaluates the period and grace and sends the email, the operator's mail provider delivers it, and this machine only pings, so nothing reports the outage if healthchecks.io fails at the same time.
- The watch's configuration is not guaranteed: the check's period, grace and email integration are set in healthchecks.io's web interface, not by this machine, and only the acceptance stops and later outages observe them.
- The ping URL's secrecy is not guaranteed: the URL is a bearer credential, any root process on cinnabar can read it, and anyone holding it can keep the check up while the alert path is down.
- These properties do not guarantee that an alert reaches a person: each stage's configuration, the fixture check and the recorded acceptance observations behave as stated, and nothing here observes an alert or an email reaching a person's device.

---

## 9. Evaluation cost and observations

### 9.1 Evaluation cost of each changed check

The budget is 0.5 GiB, 536,870,912 bytes of `gc.totalBytes` (tasks.md preamble line 6).
The method is `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`, reading `.gc.totalBytes` and `.cpuTime` from the stats file; each log prints the method in its header.
The "before" figures were taken at origin/main `79d5cee3d` in a detached worktree; the "after" figures in the working copy.

| Check | Point | `gc.totalBytes` | GiB | cpuTime (s) | Log |
|---|---|---|---|---|---|
| `fleet-alert` (changed) | before: origin/main `79d5cee3d` | 351,526,304 | 0.327 | 1.01 | `1.2-baseline-20261102T044146Z.log` |
| | after 2.1–2.5 | 351,807,696 | 0.328 | 1.03 | `2.4-cost-20261102T051315Z.log` |
| | after 2.7's generator and option | 351,808,048 | 0.328 | 0.96 | `2.8-cost-20261102T051632Z.log` |
| `nixos-cinnabar` (machine check) | before: origin/main `79d5cee3d` | 2,659,407,696 | 2.477 | 12.06 | `1.2-baseline-20261102T044146Z.log` |
| | after 2.7's generator and option | 2,659,865,600 | 2.477 | 11.80 | `2.8-cost-20261102T051632Z.log` |

`fleet-alert` grew by 281,744 B, 0.08 %, and stays under the budget.
The machine check is outside the 0.5 GiB budget, as for the fleet-collection change, and is recorded for comparison.
The figures after 2.7 were taken before the operator generated the var; the generation adds var files and no Nix code, and the cost was not measured again after it.

### 9.2 Acceptance and control times

Times are from the done notes of `tasks.md` and the logs they cite; the operator's times are EST read to the minute and converted to UTC.
The acceptance evidence of 4.2 and 4.3 lives in `4.2-4.3-results-20261104T190037Z.log` (cinnabar's and magnetite's journals), `4.2-4.3-operator-20261104T212115Z.log` (the operator's received times) and `4.2-4.3-schedule-20261104T152101Z.log` (the one-shot timers), not in the per-item files `4.2-ntfy-stop-<ts>.log` and `4.3-evaluator-stop-<ts>.log` that tasks.md and plan Task 6 Step 4 name (§10).

| Event | Time (UTC) | Evidence |
|---|---|---|
| #3716 merged; cinnabar deployed from `af9854117` | 2026-11-04T14:25:18Z; first ping 14:30:03Z | tasks.md 3.1, `3.2-first-pings-20261104T142853Z.log` |
| ntfy stop (4.2) | last ping 15:25:00Z; stopped 15:25:06Z; down email 15:40Z; started 15:50:06Z; ping 15:55:02Z; up email 15:55Z | `4.2-4.3-results-20261104T190037Z.log`, `4.2-4.3-operator-20261104T212115Z.log` |
| evaluator stop (4.3) | stopped 16:05:08Z; last ping 16:15:02Z; FIRING 16:20:02Z, received 16:20Z; down email 16:30Z; started 16:35:08Z; RESOLVED 16:40:02Z; ping 16:40:03Z; up email 16:40Z | same |
| quiet window (4.4) | 2026-11-04T16:40:03Z to 2026-11-05T14:16:43Z | `4.4-day-20261105T141643Z.log` |

---

## 10. Deviations and observed gaps

- **4.1, confirmed afterwards.** The operator was not present at a device during 4.2 and 4.3: so that the workstation could sleep, both controls ran from one-shot `systemd-run` timers on cinnabar and magnetite (`4.2-4.3-schedule-20261104T152101Z.log`), and the operator confirmed afterwards, from the received messages' times, that the phone and the `gmail.com` mailbox received every expected message (`4.2-4.3-operator-20261104T212115Z.log`).
- **4.4, shortened.** The quiet window ran 21 h 37 min, 2026-11-04T16:40:03Z to 2026-11-05T14:16:43Z, rather than 24 h, by the operator's decision: the unobserved slice of 14:00 to 16:40Z holds only the 5-min, frequent and hourly timers, randomized acme renewals and cinnabar's `systemd-tmpfiles-clean`, and the window already absorbed magnetite's 13:54Z deploy, which restarted kanidm and nginx, and the 14:06Z perses kill. The log records the operator's statement that no email arrived, and no reading of the check's own ping log.
- **2.7, rejection shown by the script.** The operator entered the real URL at the hidden prompt without the malformed first attempt, so the rejection of `https://hc-ping.com/not-a-uuid` was shown by running the generator's own script on magnetite with prompt files: exit 1, the generator's message, and no `curl-config`; a well-formed UUID URL exits 0 (`2.7-validation-20261104T140219Z.log`).
- **7.1, evidence file names.** The 4.2 and 4.3 evidence is in the combined files of §9.2, not in `4.2-ntfy-stop-*.log` and `4.3-evaluator-stop-*.log`.
- **Observed gap, not discharged: no `FAILED fleet-deadman` after the ntfy outage.** 4.2 expected `FAILED fleet-deadman on cinnabar` to arrive once ntfy was back. None arrived: the five failing runs' notifier posts went to the stopped ntfy, and the notifier does not retry, so a dead-man failure during an ntfy outage is never posted. The healthchecks.io email reported the outage; the lost failure notices are a gap in the notifier, recorded in the runbook's section "The external watch" (tasks.md 5.1) and not closed by this change.
  Correction of 2026-11-06: the failed notifier unit was reported after all, by magnetite's `[FIRING] SystemdUnitFailed cinnabar` for `observability-notify@fleet-deadman.service.service` at 2026-11-04T15:51:03Z, a minute after ntfy returned; it was missed because only `fleet-deadman`'s own notices were looked for. That alert stayed open until cinnabar's deploy of 2026-11-06 reset the unit and resolved it at 03:06:03Z, so the remaining gap is that a failed notifier unit stays failed and hides a second failure; the runbook states this, and CAM-84 tracks it.

---

## Overall Decision

Every `tasks.md` item is done; the requirements are discharged or carry their observed status as §8b states, with the deviations and the one observed gap of §10.
